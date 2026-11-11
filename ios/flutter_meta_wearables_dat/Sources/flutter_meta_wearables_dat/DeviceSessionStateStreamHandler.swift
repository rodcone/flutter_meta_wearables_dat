import Flutter

/// Connection state is retained independently of camera subscriptions.
final class DeviceSessionStateStreamHandler: NSObject, FlutterStreamHandler {
  private var sink: FlutterEventSink?
  private var state = "stopped"
  // Deliver synchronously to preserve ordering across stop and restart.
  @MainActor
  func send(_ next: String) {
    assert(Thread.isMainThread, "Device-session events must use the platform thread.")
    state = next
    sink?(next)
  }
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    assert(Thread.isMainThread, "Flutter stream callbacks must use the platform thread.")
    sink = events
    events(state)
    return nil
  }
  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    assert(Thread.isMainThread, "Flutter stream callbacks must use the platform thread.")
    sink = nil
    return nil
  }
}
