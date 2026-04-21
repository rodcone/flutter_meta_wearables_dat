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

  public func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    sinkQueue.sync { eventSink = events }
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sinkQueue.sync { eventSink = nil }
    return nil
  }

  func dispose() {
    sinkQueue.sync { eventSink = nil }
  }

  // MARK: - Emission

  /// Emit a decoded raw BGRA pixel buffer. Caller passes the already-locked
  /// pixel buffer base address; we memcpy into a Data so Flutter owns the
  /// bytes on the main isolate.
  func emitRaw(
    pixelBuffer: CVPixelBuffer,
    ptsUs: Int64
  ) {
    guard let sink = eventSink else { return }

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
    _ = sink  // silence unused-capture
  }

  /// Emit a compressed hvc1 sample buffer. Extracts the CMBlockBuffer bytes
  /// and reads the dependency flag so callers can gate mp4 writes on keyframes.
  func emitHvc1(
    sampleBuffer: CMSampleBuffer,
    ptsUs: Int64
  ) {
    guard eventSink != nil else { return }
    guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
      return
    }

    var totalLength: Int = 0
    var dataPointer: UnsafeMutablePointer<Int8>?
    let status = CMBlockBufferGetDataPointer(
      blockBuffer,
      atOffset: 0,
      lengthAtOffsetOut: nil,
      totalLengthOut: &totalLength,
      dataPointerOut: &dataPointer
    )
    guard status == kCMBlockBufferNoErr, let dataPointer else { return }

    let data = Data(bytes: dataPointer, count: totalLength)

    // Pull dimensions from the format description.
    var width = 0
    var height = 0
    if let fd = CMSampleBufferGetFormatDescription(sampleBuffer) {
      let dims = CMVideoFormatDescriptionGetDimensions(fd)
      width = Int(dims.width)
      height = Int(dims.height)
    }

    // Keyframe detection — if the "DependsOnOthers" attachment is false, the
    // frame is a keyframe (I-frame). Missing attachment is treated as a
    // keyframe since hvc1 parameter sets are attached there.
    var isKeyframe = true
    if let attachments = CMSampleBufferGetSampleAttachmentsArray(
      sampleBuffer,
      createIfNecessary: false
    ) as? [[CFString: Any]],
       let first = attachments.first,
       let dependsOnOthers = first[kCMSampleAttachmentKey_DependsOnOthers] as? Bool {
      isKeyframe = !dependsOnOthers
    }

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
}
