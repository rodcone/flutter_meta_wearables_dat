import Flutter

/// Stream handler that surfaces the video frame dimensions of the active
/// stream to Dart, so the Flutter side can wrap the `Texture` widget in an
/// `AspectRatio` matching the source instead of stretching it into a
/// hardcoded box.
///
/// The plugin pushes a size whenever the pixel buffer dimensions change
/// (first frame of a new stream, or a mid-stream resolution change).
class VideoStreamSizeStreamHandler: NSObject, FlutterStreamHandler {
  private var eventSink: FlutterEventSink?
  private var lastWidth: Int = 0
  private var lastHeight: Int = 0

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    if lastWidth > 0 && lastHeight > 0 {
      events(["width": lastWidth, "height": lastHeight])
    }
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  func send(width: Int, height: Int) {
    guard width > 0, height > 0 else { return }
    if width == lastWidth && height == lastHeight { return }
    lastWidth = width
    lastHeight = height
    let sink = eventSink
    DispatchQueue.main.async {
      sink?(["width": width, "height": height])
    }
  }

  func reset() {
    lastWidth = 0
    lastHeight = 0
  }

  func dispose() {
    eventSink = nil
    lastWidth = 0
    lastHeight = 0
  }
}
