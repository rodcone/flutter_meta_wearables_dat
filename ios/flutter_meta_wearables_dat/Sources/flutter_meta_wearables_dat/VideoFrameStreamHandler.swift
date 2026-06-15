import CoreMedia
import CoreVideo
import Flutter
import Foundation

/// Event-channel handler that forwards each stream frame to Dart as a
/// serialized payload. Only emits while a Dart subscriber is attached —
/// serialization is skipped entirely when `hasListener` is false so there
/// is no per-frame cost for apps that don't need the feed.
final class VideoFrameStreamHandler: NSObject, FlutterStreamHandler {
    private var eventSink: FlutterEventSink?
    private let sinkQueue = DispatchQueue(
        label: "io.rodcone.mwdat.video_frames",
        qos: .userInitiated
    )

    var hasListener: Bool { eventSink != nil }

    func onListen(
        withArguments _: Any?,
        eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        sinkQueue.sync { eventSink = events }
        return nil
    }

    func onCancel(withArguments _: Any?) -> FlutterError? {
        sinkQueue.sync { eventSink = nil }
        return nil
    }

    // MARK: - Emission

    /// Emit a decoded raw BGRA pixel buffer. Caller passes the already-locked
    /// pixel buffer base address; we memcpy into a Data so Flutter owns the
    /// bytes on the main isolate.
    func emitRaw(
        pixelBuffer: CVPixelBuffer,
        ptsUs: Int64
    ) {
        guard eventSink != nil else { return }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }

        let length = bytesPerRow * height
        let data = Data(bytes: base, count: length)

        let payload: [String: Any] = [
            "codec": "raw",
            "bytes": FlutterStandardTypedData(bytes: data),
            "width": width,
            "height": height,
            "bytesPerRow": bytesPerRow,
            "ptsUs": ptsUs,
            "isKeyframe": true,
        ]

        sinkQueue.async { [weak self] in
            self?.eventSink?(payload)
        }
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
        guard eventSink != nil else { return }
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

        var data = Data()
        if isKeyframe, let fd = formatDescription {
            data.append(Self.hevcParameterSetsAsHvcc(formatDescription: fd))
        }
        data.append(Data(bytes: dataPointer, count: totalLength))

        let payload: [String: Any] = [
            "codec": "hvc1",
            "bytes": FlutterStandardTypedData(bytes: data),
            "width": width,
            "height": height,
            "ptsUs": ptsUs,
            "isKeyframe": isKeyframe,
        ]

        sinkQueue.async { [weak self] in
            self?.eventSink?(payload)
        }
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
