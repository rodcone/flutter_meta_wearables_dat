import Flutter

/// Connection state is retained independently of camera subscriptions.
final class DeviceSessionStateStreamHandler: NSObject, FlutterStreamHandler {
  private var sink: FlutterEventSink?
  private var state = "stopped"
  func send(_ next: String) {
    state = next
    sink?(next)
  }
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    events(state)
    return nil
  }
  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }
}
