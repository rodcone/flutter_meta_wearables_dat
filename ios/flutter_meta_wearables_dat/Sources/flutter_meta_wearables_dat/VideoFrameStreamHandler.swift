import CoreMedia
import CoreVideo
import Flutter
import Foundation

/// Event-channel handler that forwards each stream frame to Dart as a
/// serialized payload. Only emits while a Dart subscriber is attached —
/// serialization is skipped entirely when `hasListener` is false so there
/// is no per-frame cost for apps that don't need the feed.
final class VideoFrameStreamHandler: NSObject, FlutterStreamHandler {
    /// Guarded by `sinkLock`. Written from the platform thread in
    /// `onListen`/`onCancel`, read from the SDK's frame queue on every frame.
    private var eventSink: FlutterEventSink?
    private let sinkLock = NSLock()

    /// Payloads handed to the platform thread but not yet delivered.
    ///
    /// Every frame has to hop to the platform thread (see `send`), and a busy
    /// main thread must not be allowed to accumulate an unbounded backlog of
    /// multi-megabyte payloads — at 504x896 BGRA that is ~1.8 MB each. Past
    /// this many in flight, new frames are dropped rather than queued: a
    /// recording consumer losing frames under load is recoverable, running the
    /// app out of memory is not.
    private static let maxPendingDeliveries = 8
    private var pendingDeliveries = 0
    private var droppedFrames = 0
    private var sinkGeneration: UInt64 = 0

    /// Converts DAT's documented 420v raw frames into the BGRA layout promised
    /// by the public Dart API. Accessed only from the serial frame queue.
    private let rawConverter = RawVideoFrameBGRAConverter()

    /// HEVC IRAP NAL unit types — the pictures a decoder can start on.
    /// H.265 Table 7-1: 16-18 BLA, 19-20 IDR, 21 CRA, 22-23 reserved IRAP.
    private static let irapNalTypeRange: ClosedRange<UInt8> = 16 ... 23

    /// HEVC parameter-set NAL unit types: 32 VPS, 33 SPS, 34 PPS.
    private static let vpsNalType: UInt8 = 32
    private static let spsNalType: UInt8 = 33
    private static let ppsNalType: UInt8 = 34

    /// HVCC NAL-unit length-prefix size. `hevcParameterSetsAsHvcc` writes
    /// 4-byte prefixes, so the scan assumes the same. HVCC also permits 1 and
    /// 2; the format description reports which, and `hevcParameterSetsAsHvcc`
    /// logs when it is not 4 rather than letting the scan mis-parse silently.
    private static let nalLengthSize = 4

    /// Last parameter sets seen, refreshed from every frame that carries a
    /// format description. Prepended to any IRAP-opening frame whose own
    /// sample lacked them, so a burst starting on that IRAP is always
    /// self-decodable — the SDK's `DependsOnOthers` keyframe flag and a true
    /// IRAP picture do not always agree, and when they disagree (routinely so
    /// once the app backgrounds and the keyframe cadence stretches) an IRAP
    /// used to ship without VPS/SPS/PPS and decoded to green.
    private var cachedParameterSets = Data()
    private let cacheLock = NSLock()

    var hasListener: Bool {
        sinkLock.lock()
        defer { sinkLock.unlock() }
        return eventSink != nil
    }

    func onListen(
        withArguments _: Any?,
        eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        sinkLock.lock()
        sinkGeneration &+= 1
        eventSink = events
        droppedFrames = 0
        sinkLock.unlock()
        return nil
    }

    func onCancel(withArguments _: Any?) -> FlutterError? {
        sinkLock.lock()
        sinkGeneration &+= 1
        eventSink = nil
        sinkLock.unlock()
        return nil
    }

    // MARK: - Delivery

    /// Delivers one payload to Dart on the platform thread.
    ///
    /// Flutter requires channel messages to be sent from the platform thread.
    /// This handler used to invoke the sink on its own serial queue, which the
    /// engine reports as "sent a message from a non-platform thread" and which
    /// left the frames undelivered — `videoFramesStream()` produced nothing at
    /// all on iOS. Every other stream handler in this plugin already hops to
    /// the main actor; this one was the exception.
    ///
    /// Frame *preparation* deliberately stays off the platform thread: the
    /// pixel copy and the NAL scan both happen on the caller's queue, and only
    /// the finished payload crosses over.
    private struct DeliveryReservation {
        let sinkGeneration: UInt64
    }

    /// Reserves bounded space on the platform-thread queue before any frame
    /// bytes are copied or converted. Under backpressure, dropping here avoids
    /// doing a multi-megabyte BGRA conversion for a frame Dart cannot receive.
    private func reserveDelivery() -> DeliveryReservation? {
        sinkLock.lock()
        guard eventSink != nil else {
            sinkLock.unlock()
            return nil
        }
        guard pendingDeliveries < Self.maxPendingDeliveries else {
            droppedFrames += 1
            let dropped = droppedFrames
            sinkLock.unlock()
            // Logged occasionally rather than per frame: if the platform thread
            // is far enough behind to be dropping frames, a line per frame
            // makes it worse.
            if dropped % 30 == 1 {
                NSLog(
                    "[MWDAT] video_frames: platform thread behind, dropped \(dropped) frame(s) so far")
            }
            return nil
        }
        pendingDeliveries += 1
        let reservation = DeliveryReservation(sinkGeneration: sinkGeneration)
        sinkLock.unlock()
        return reservation
    }

    private func abandonDelivery() {
        sinkLock.lock()
        pendingDeliveries = max(0, pendingDeliveries - 1)
        sinkLock.unlock()
    }

    private func send(
        _ payload: [String: Any],
        reservation: DeliveryReservation
    ) {

        let deliver: () -> Void = { [weak self] in
            guard let self else { return }
            // Re-read under the lock rather than capturing the sink above:
            // `onCancel` can land between the check and this block running, and
            // invoking a torn-down sink is exactly the race this avoids.
            self.sinkLock.lock()
            let sink = self.sinkGeneration == reservation.sinkGeneration
                ? self.eventSink
                : nil
            self.pendingDeliveries = max(0, self.pendingDeliveries - 1)
            self.sinkLock.unlock()
            assert(
                Thread.isMainThread,
                "FlutterEventSink must be invoked on the platform thread")
            sink?(payload)
        }

        // Emissions come from one serial queue, so main-queue blocks retain
        // frame order. Always enqueue: a synchronous main-thread fast path can
        // overtake an older frame that is already waiting on that queue.
        DispatchQueue.main.async(execute: deliver)
    }

    /// Drops the cached parameter sets. Called when a stream session starts,
    /// because the handler outlives every session: sets describing the
    /// previous stream's resolution must never be prepended to a new stream's
    /// IRAP, which would activate an SPS whose dimensions disagree with the
    /// coded picture. Sessions restart routinely now that backgrounding tears
    /// the DeviceSession down.
    func resetSessionState() {
        cacheLock.lock()
        cachedParameterSets = Data()
        cacheLock.unlock()
        rawConverter.reset()
    }

    // MARK: - Emission

    /// Emit a raw frame as packed BGRA, matching the public Dart contract.
    /// DAT supplies raw frames as 420v bi-planar YUV, so conversion and the
    /// ownership copy both finish before the SDK publisher callback returns.
    func emitRaw(
        pixelBuffer: CVPixelBuffer,
        ptsUs: Int64
    ) {
        guard let reservation = reserveDelivery() else { return }
        guard let frame = rawConverter.convert(pixelBuffer) else {
            abandonDelivery()
            return
        }

        let payload: [String: Any] = [
            "codec": "raw",
            "bytes": FlutterStandardTypedData(bytes: frame.bytes),
            "width": frame.width,
            "height": frame.height,
            "bytesPerRow": frame.bytesPerRow,
            "ptsUs": ptsUs,
            "isKeyframe": true,
        ]

        send(payload, reservation: reservation)
    }

    /// Emit a compressed hvc1 sample buffer. Extracts the CMBlockBuffer bytes
    /// and reads the dependency flag so callers can gate mp4 writes on keyframes.
    /// On keyframes, prepends the VPS/SPS/PPS parameter-set NAL units from the
    /// format description so downstream consumers (ffmpeg, VTDecompressionSession,
    /// mp4 muxers) can decode without needing a separate params channel.
    func emitHvc1(
        sampleBuffer: CMSampleBuffer,
        ptsUs: Int64
    ) {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return
        }

        var totalLength = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(
            blockBuffer,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &totalLength,
            dataPointerOut: &dataPointer
        )
        guard status == kCMBlockBufferNoErr, let dataPointer else { return }
        guard let reservation = reserveDelivery() else { return }

        let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer)

        /// Pull dimensions from the format description.
        var width = 0
        var height = 0
        if let fd = formatDescription {
            let dims = CMVideoFormatDescriptionGetDimensions(fd)
            width = Int(dims.width)
            height = Int(dims.height)
        }

        /// Keyframe detection — if the "DependsOnOthers" attachment is false, the
        /// frame is a keyframe (I-frame). Missing attachment is treated as a
        /// keyframe.
        var isKeyframe = true
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(
            sampleBuffer,
            createIfNecessary: false
        ) as? [[CFString: Any]],
            let first = attachments.first,
            let dependsOnOthers = first[kCMSampleAttachmentKey_DependsOnOthers] as? Bool
        {
            isKeyframe = !dependsOnOthers
        }

        let frameBytes = Data(bytes: dataPointer, count: totalLength)

        // Refresh the cached parameter sets from any frame that carries a
        // format description, so an IRAP that arrives without one can still be
        // made decodable from the last known sets.
        if let fd = formatDescription {
            let params = Self.hevcParameterSetsAsHvcc(formatDescription: fd)
            if !params.isEmpty {
                cacheLock.lock()
                cachedParameterSets = params
                cacheLock.unlock()
            }
        }

        cacheLock.lock()
        let params = cachedParameterSets
        cacheLock.unlock()

        // A burst opens on a true IRAP picture, keyed off the NAL type. The
        // SDK's `DependsOnOthers` attachment is consulted ONLY when the scan
        // could not read the framing: the attachment is absent on most
        // predicted frames (which reads as isKeyframe == true), and treating
        // that as "opens a burst" stapled VPS/SPS/PPS onto nearly every
        // P-frame — parameter sets are the universal "decode from here"
        // marker, so downstream decoders sampled mid-GOP P-frames as entry
        // points and produced green, glitched frames. Verified on hardware
        // 2026-08-24: keying off the scan alone restored clean recognition.
        let summary = Self.summarizeNalUnits(frameBytes)
        let opensBurst = summary.hasIrap || (!summary.parsed && isKeyframe)

        // Only withhold the cached sets when the frame genuinely carries all
        // three itself. Checking just the first NAL is not enough: encoders
        // commonly repeat the PPS per access unit, so `[PPS, IDR]` would look
        // self-sufficient while its VPS and SPS are missing.
        let willPrepend = opensBurst
            && !summary.carriesAllParameterSets
            && !params.isEmpty

        var data = Data()
        if willPrepend {
            data.append(params)
        }
        data.append(frameBytes)

        // `isKeyframe` is documented as "carries parameter sets and can be
        // decoded without prior frames", so it tracks what actually shipped.
        // Flagging an IRAP that went out without its sets would point a
        // recorder at an undecodable segment start.
        let selfContained = opensBurst
            && (summary.carriesAllParameterSets || willPrepend)

        let payload: [String: Any] = [
            "codec": "hvc1",
            "bytes": FlutterStandardTypedData(bytes: data),
            "width": width,
            "height": height,
            "ptsUs": ptsUs,
            "isKeyframe": selfContained,
        ]

        send(payload, reservation: reservation)
    }

    /// What a single walk of an access unit's NAL units established.
    private struct NalSummary {
        /// The walk read the framing cleanly end to end. False when the data
        /// was too short or a length prefix was malformed — only then is the
        /// SDK's keyframe attachment worth consulting as a fallback.
        var parsed = true
        /// An IRAP picture appears in the access unit.
        var hasIrap = false
        /// VPS, SPS and PPS all appear ahead of the first IRAP, so the frame
        /// is self-decodable without anything being prepended.
        var carriesAllParameterSets = false
    }

    /// Walks the HVCC length-prefixed NAL units in [data] once, reporting
    /// whether the access unit opens a burst and whether it already carries
    /// the full parameter-set trio.
    ///
    /// Fails closed: malformed or unexpected framing returns an empty summary,
    /// which leaves the decision to the SDK's keyframe attachment rather than
    /// mangling a frame the scan could not read.
    private static func summarizeNalUnits(_ data: Data) -> NalSummary {
        var summary = NalSummary()
        var sawVps = false
        var sawSps = false
        var sawPps = false

        guard data.count >= nalLengthSize + 1 else {
            summary.parsed = false
            return summary
        }

        var pos = data.startIndex
        while pos + nalLengthSize < data.endIndex {
            var length = 0
            for offset in 0 ..< nalLengthSize {
                length = (length << 8) | Int(data[pos + offset])
            }
            let payloadStart = pos + nalLengthSize
            guard length > 0, payloadStart + length <= data.endIndex else {
                summary.parsed = false
                return summary
            }
            let type = (data[payloadStart] >> 1) & 0x3F
            if irapNalTypeRange.contains(type) {
                summary.hasIrap = true
                summary.carriesAllParameterSets = sawVps && sawSps && sawPps
                return summary
            }
            switch type {
            case vpsNalType: sawVps = true
            case spsNalType: sawSps = true
            case ppsNalType: sawPps = true
            default: break
            }
            pos = payloadStart + length
        }
        return summary
    }

    /// Extract HEVC parameter-set NAL units (VPS, SPS, PPS, …) from the supplied
    /// `CMFormatDescription` and return them concatenated with the same HVCC
    /// 4-byte big-endian length-prefix framing that the sample buffer data uses,
    /// so a downstream Annex B converter can treat every NAL identically.
    /// Returns an empty `Data` on any failure.
    private static func hevcParameterSetsAsHvcc(
        formatDescription: CMFormatDescription
    ) -> Data {
        var paramSetCount: size_t = 0
        var nalUnitHeaderLength: Int32 = 0
        let countStatus = CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(
            formatDescription,
            parameterSetIndex: 0,
            parameterSetPointerOut: nil,
            parameterSetSizeOut: nil,
            parameterSetCountOut: &paramSetCount,
            nalUnitHeaderLengthOut: &nalUnitHeaderLength
        )
        guard countStatus == noErr, paramSetCount > 0 else { return Data() }
        if nalUnitHeaderLength != Int32(nalLengthSize) {
            NSLog(
                "[MWDAT] HEVC NAL length prefix is \(nalUnitHeaderLength) bytes, not \(nalLengthSize) — parameter-set framing may not match the sample data")
        }

        var output = Data()
        for index in 0 ..< paramSetCount {
            var paramPointer: UnsafePointer<UInt8>?
            var paramSize: size_t = 0
            let status = CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(
                formatDescription,
                parameterSetIndex: index,
                parameterSetPointerOut: &paramPointer,
                parameterSetSizeOut: &paramSize,
                parameterSetCountOut: nil,
                nalUnitHeaderLengthOut: nil
            )
            guard status == noErr, let pointer = paramPointer, paramSize > 0 else {
                continue
            }
            var lengthBE = UInt32(paramSize).bigEndian
            withUnsafeBytes(of: &lengthBE) { output.append(contentsOf: $0) }
            output.append(pointer, count: paramSize)
        }
        return output
    }
}
