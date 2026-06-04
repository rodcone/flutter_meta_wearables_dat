import Flutter
import MWDATCamera
import MWDATCore

/// Stream handler for stream state updates.
///
/// Set the `session` property when a `Stream` is created.
/// Clear it when the stream is torn down.
class StreamStateStreamHandler: NSObject, FlutterStreamHandler {
  /// The active stream to observe. Setting this property
  /// re-subscribes to the stream's state publisher.
  var session: MWDATCamera.Stream? {
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

  /// Maps StreamState to the int values expected by Dart.
  private static func stateToInt(_ state: StreamState) -> Int {
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
