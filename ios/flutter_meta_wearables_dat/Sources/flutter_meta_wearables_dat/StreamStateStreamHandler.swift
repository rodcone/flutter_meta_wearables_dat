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

  /// Bumped every time we detach from a stream. Callbacks capture the value
  /// current at subscribe time and drop themselves if it has moved on.
  ///
  /// Cancellation alone is not enough to stop a stale state reaching Dart.
  /// `cancelListener()` can only *start* the cancel (`token.cancel()` is async
  /// and fire-and-forget), and the listener callback hops through a
  /// `Task { @MainActor }` before it touches the sink. So an old stream's state
  /// can already be in flight when we swap streams, and would otherwise land
  /// after the replacement was seeded — telling Dart the *new* stream is
  /// `stopped`, or reviving a torn-down one with a stale `streaming`.
  ///
  /// Mutated only from `resubscribe()` / `cancelListener()`, which the plugin
  /// drives from the main thread (`didSet` on `session`, and Flutter's
  /// `onListen` / `onCancel`), and read on the main actor — the same
  /// confinement `eventSink` and `listenerToken` already rely on.
  private var subscriptionGeneration: UInt64 = 0

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

    // Listen for future changes. The generation captured here is what makes a
    // late callback from a superseded stream drop itself instead of publishing.
    let generation = subscriptionGeneration
    listenerToken = session.statePublisher.listen { [weak self] state in
      Task { @MainActor in
        guard let self, self.subscriptionGeneration == generation else { return }
        events(Self.stateToInt(state))
      }
    }
  }

  private func cancelListener() {
    // Bump first and unconditionally: in-flight callbacks are invalidated the
    // moment we decide to detach, not whenever the async cancel gets around to
    // landing. `resubscribe()` calls this before capturing the new generation,
    // so the new listener always gets a value no stale callback can match.
    subscriptionGeneration &+= 1
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
