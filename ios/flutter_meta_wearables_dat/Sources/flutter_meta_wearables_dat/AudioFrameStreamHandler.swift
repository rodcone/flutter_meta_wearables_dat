import AVFoundation
import Flutter

/// Surfaces the glasses' microphone to Dart as 16-bit little-endian PCM.
///
/// The audio rides on the camera stream (`StreamConfiguration.audioCodec`), so
/// it keeps flowing while the app is backgrounded with background streaming
/// enabled. That matters for voice apps: iOS refuses to start an
/// `AVAudioSession` recording from the background, but this audio never
/// touches the phone's audio input. It also leaves the glasses on A2DP instead
/// of the 8 kHz hands-free link.
///
/// Each event is a `FlutterStandardTypedData` with the samples of one frame,
/// mono, at the configured rate (16 kHz). Multi-channel buffers are reduced to
/// their first channel; float buffers are converted to Int16.
final class AudioFrameStreamHandler: NSObject, FlutterStreamHandler {
  private let lock = NSLock()
  private var eventSink: FlutterEventSink?
  private var loggedFormat = false

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    lock.lock()
    eventSink = events
    lock.unlock()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    lock.lock()
    eventSink = nil
    lock.unlock()
    return nil
  }

  /// Called at the start of every stream, so the format is logged once per
  /// stream.
  func resetSessionState() {
    lock.lock()
    loggedFormat = false
    lock.unlock()
  }

  /// Copies the buffer synchronously (it belongs to the SDK) and delivers the
  /// bytes on the main thread, where Flutter expects event sinks to be called.
  func send(_ buffer: AVAudioPCMBuffer) {
    lock.lock()
    let sink = eventSink
    let logFormat = !loggedFormat
    loggedFormat = true
    lock.unlock()

    if logFormat {
      let f = buffer.format
      NSLog("[MWDAT-AUDIO] first frame: \(f.sampleRate) Hz, \(f.channelCount) ch, format \(f.commonFormat.rawValue), interleaved \(f.isInterleaved), \(buffer.frameLength) frames")
    }
    guard let sink, let data = Self.pcm16(buffer) else { return }
    // Channel messages must be sent from the platform thread.
    DispatchQueue.main.async {
      assert(Thread.isMainThread)
      sink(FlutterStandardTypedData(bytes: data))
    }
  }

  static func pcm16(_ buffer: AVAudioPCMBuffer) -> Data? {
    let frames = Int(buffer.frameLength)
    guard frames > 0 else { return nil }
    let channels = Int(buffer.format.channelCount)
    // In an interleaved buffer all channels share the first pointer, one
    // sample of each after the other.
    let step = buffer.format.isInterleaved ? max(channels, 1) : 1

    if let int16 = buffer.int16ChannelData {
      let source = int16[0]
      if step == 1 {
        return Data(bytes: source, count: frames * MemoryLayout<Int16>.size)
      }
      var out = [Int16](repeating: 0, count: frames)
      for i in 0..<frames { out[i] = source[i * step] }
      return out.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    if let float = buffer.floatChannelData {
      let source = float[0]
      var out = [Int16](repeating: 0, count: frames)
      for i in 0..<frames {
        let v = max(-1, min(1, source[i * step]))
        out[i] = Int16(v * Float(Int16.max))
      }
      return out.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    if let int32 = buffer.int32ChannelData {
      let source = int32[0]
      var out = [Int16](repeating: 0, count: frames)
      for i in 0..<frames { out[i] = Int16(truncatingIfNeeded: source[i * step] >> 16) }
      return out.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    return nil
  }
}
