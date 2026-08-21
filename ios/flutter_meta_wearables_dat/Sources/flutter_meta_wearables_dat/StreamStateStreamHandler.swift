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

  /// Detaches from the current stream and pushes a terminal `stopped` to Dart.
  ///
  /// Plain `session = nil` detaches *silently*: `resubscribe()` cancels the
  /// listener and returns early on a nil session, so nothing is emitted. That is
  /// wrong for every plugin-initiated teardown, because those run on paths the
  /// SDK never reports on — the device-availability watchdog and a DeviceSession
  /// that stopped underneath us. Dart was left holding a live texture id and a
  /// `Texture` frozen on its last frame, with no state change and no error to
  /// act on. Emitting the terminal state here is what makes those teardowns
  /// observable.
  ///
  /// Safe to double-emit: if the SDK also reported `.stopped` before we
  /// detached, Dart sees the same terminal state twice.
  ///
  /// The emit is **synchronous** on purpose. The sole caller,
  /// `performTeardownStreamOnly()`, is `@MainActor` and calls this before its
  /// first suspension, so we are already on the platform thread and may touch
  /// the sink directly. Deferring it onto a `Task` instead would hand this
  /// terminal `stopped` an unordered slot: a restart that re-seeds the channel
  /// from `session`'s `didSet` could publish `starting`/`streaming` first, and
  /// the late `stopped` would then tell the app to drop a texture id that
  /// belongs to the *new* stream.
  @MainActor
  func detachEmittingStopped() {
    session = nil
    guard let events = eventSink else { return }
    events(Self.stoppedValue)
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

  /// The Dart-facing value for `stopped`. Kept next to `stateToInt` so the two
  /// can't drift.
  private static let stoppedValue = 1

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
