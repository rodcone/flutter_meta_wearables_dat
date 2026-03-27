import Flutter
import MWDATCamera
import MWDATCore

/// Stream handler for stream session state updates.
///
/// Set the `session` property when a stream session is created.
/// Clear it when the session is torn down.
class StreamSessionStateStreamHandler: NSObject, FlutterStreamHandler {
  /// The active stream session to observe. Setting this property
  /// re-subscribes to the session's state publisher.
  var session: StreamSession? {
    didSet { resubscribe() }
  }

  private var eventSink: FlutterEventSink?
  private var listenerToken: AnyListenerToken?

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    resubscribe()
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    cancelListener()
    return nil
  }

  private func resubscribe() {
    cancelListener()
    guard let session = session, let events = eventSink else { return }

    // Send current state immediately
    events(Self.stateToInt(session.state))

    // Listen for future changes
    listenerToken = session.statePublisher.listen { state in
      Task { @MainActor in
        events(Self.stateToInt(state))
      }
    }
  }

  private func cancelListener() {
    if let token = listenerToken {
      Task { await token.cancel() }
      listenerToken = nil
    }
  }

  /// Maps StreamSessionState to the int values expected by Dart.
  private static func stateToInt(_ state: StreamSessionState) -> Int {
    switch state {
    case .stopping:         return 0
    case .stopped:          return 1
    case .waitingForDevice: return 2
    case .starting:         return 3
    case .streaming:        return 4
    case .paused:           return 5
    @unknown default:       return 1 // default to stopped
    }
  }
}
