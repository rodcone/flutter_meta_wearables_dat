import Flutter
import MWDATCamera
import MWDATCore

/// Stream handler for stream-related errors (both `Stream` errors and the
/// `DeviceSession` errors that gate the stream). They share the same Flutter
/// event channel because the Dart side exposes a single `streamErrorStream()`
/// API — consumers don't need to care which layer produced the error.
///
/// Set `session` when a `Stream` is created; clear it on teardown. Pre-stream
/// failures (createSession / DeviceSession.start / addCamera throws) are
/// forwarded via `sendError(code:message:)`.
class StreamErrorStreamHandler: NSObject, FlutterStreamHandler {
  /// The active stream to observe. Setting this property re-subscribes to the
  /// stream's error publisher.
  var session: MWDATCamera.Stream? {
    didSet { resubscribe() }
  }

  private var eventSink: FlutterEventSink?
  private var listenerToken: AnyListenerToken?

  /// See `StreamStateStreamHandler.subscriptionGeneration` — same hazard, same
  /// guard. It matters at least as much here: consumers treat a subset of these
  /// codes as terminal and tear the session down on them, so a stale
  /// `hingesClosed` from a stream we already dropped would take down its
  /// replacement.
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

  /// True while the plugin is deliberately tearing the session down because
  /// the app was backgrounded. See `beginBackgroundStopSuppression()`.
  private var isStoppingForBackground = false
  private var suppressionExpiry: Task<Void, Never>?

  /// Suppresses teardown noise for the duration of a deliberate background
  /// stop.
  ///
  /// The SDK emits `videoStreamingError` as the pipeline comes down. That is
  /// accurate when the stream died on its own and actively false when *we*
  /// stopped it: the app implicitly asked for the stop by backgrounding, so
  /// telling it "video streaming encountered an error" is misinformation, and
  /// consumers reasonably render it as a red banner.
  ///
  /// Bounded on purpose. A teardown that stalls must not be able to hide
  /// unrelated later errors indefinitely, so the window closes on a timer even
  /// if `endBackgroundStopSuppression()` never arrives. Meta's CameraAccess
  /// sample solves the same problem the same way, app-side; doing it here means
  /// every consumer gets it rather than each rediscovering the banner.
  ///
  /// The 15s bound tracks the teardown's own worst case — `streamStopTimeout`
  /// (3s) plus `deviceSessionStopTimeout` (10s), both backstops, plus slack.
  /// The window still closes early the moment teardown completes; the timer
  /// only ever matters while teardown is *still running*, which is exactly
  /// when the noise it exists to hide is still being produced.
  ///
  /// `stoppedForBackground` is emitted *before* this opens, so the app still
  /// learns why the session ended.
  @MainActor
  func beginBackgroundStopSuppression(timeout: Duration = .seconds(15)) {
    isStoppingForBackground = true
    suppressionExpiry?.cancel()
    suppressionExpiry = Task { @MainActor [weak self] in
      try? await Task.sleep(for: timeout)
      guard let self, !Task.isCancelled else { return }
      self.isStoppingForBackground = false
      self.suppressionExpiry = nil
    }
  }

  @MainActor
  func endBackgroundStopSuppression() {
    suppressionExpiry?.cancel()
    suppressionExpiry = nil
    isStoppingForBackground = false
  }

  /// Pushes a synthesised error onto the event channel. Used by the plugin
  /// to surface errors that happen before a `Stream` exists (e.g.
  /// `DeviceSession.start()` throwing `.noEligibleDevice`).
  ///
  /// `bypassSuppression` is for the plugin's own deliberate-stop notice, which
  /// must reach Dart even though it opens the suppression window immediately
  /// afterwards.
  func sendError(code: String, message: String, bypassSuppression: Bool = false) {
    guard let events = eventSink else { return }
    Task { @MainActor in
      guard bypassSuppression || !self.isStoppingForBackground else {
        MWDATLog.log("suppressed '\(code)' during background stop")
        return
      }
      events(["code": code, "message": message])
    }
  }

  /// Maps a `DeviceSessionError` onto the Flutter channel. Matches the
  /// naming used by the native enum so Dart consumers can reason about
  /// failures uniformly across layers.
  func send(deviceSessionError: DeviceSessionError) {
    let (code, message) = Self.map(deviceSessionError: deviceSessionError)
    sendError(code: code, message: message)
  }

  private func resubscribe() {
    cancelListener()
    guard let session = session, let events = eventSink else { return }

    let generation = subscriptionGeneration
    listenerToken = session.errorPublisher.listen { [weak self] error in
      Task { @MainActor in
        guard let self, self.subscriptionGeneration == generation else { return }
        // Teardown noise from a stop we asked for is not an error. This is the
        // path that produced "Video streaming encountered an error" right after
        // a deliberate background stop.
        guard !self.isStoppingForBackground else {
          MWDATLog.log("suppressed stream error during background stop")
          return
        }
        // `errorToMap` returns nil for errors that are deliberately not part of
        // this channel's contract (see `.photoCaptureFailed`).
        guard let payload = Self.errorToMap(error) else { return }
        events(payload)
      }
    }
  }

  private func cancelListener() {
    // Bump before cancelling — see StreamStateStreamHandler for why the async
    // token cancel cannot be relied on to stop an in-flight callback.
    subscriptionGeneration &+= 1
    if let token = listenerToken {
      Task { await token.cancel() }
      listenerToken = nil
    }
  }

  /// Converts a `StreamError` to a dictionary for the platform channel, or
  /// `nil` when the error is intentionally not forwarded on this channel.
  private static func errorToMap(_ error: StreamError) -> [String: Any]? {
    let code: String
    let message: String

    switch error {
    case .photoCaptureFailed:
      // Deliberately NOT forwarded. Photo capture failure is request-scoped: it
      // belongs on the `capturePhoto` result (as `CAPTURE_PHOTO_FAILED` /
      // `photoCaptureFailed`), which is where `capturePhoto` observes this same
      // publisher directly. Android agrees — its `StreamError` has no photo
      // case, so capture failures are Future-only there too, and this channel's
      // codes are documented as identical across platforms. Handling the case
      // explicitly (rather than letting `@unknown default` relabel it
      // `unknown`) is what keeps it off the channel.
      return nil
    case .internalError:
      code = "internalError"
      message = "An internal error occurred."
    case .deviceNotFound(let deviceId):
      code = "deviceNotFound"
      message = "Device not found: \(deviceId)."
    case .deviceNotConnected(let deviceId):
      code = "deviceNotConnected"
      message = "Device not connected: \(deviceId)."
    case .timeout:
      code = "timeout"
      message = "The operation timed out."
    case .videoStreamingError:
      code = "videoStreamingError"
      message = "Video streaming encountered an error."
    case .permissionDenied:
      code = "permissionDenied"
      message = "Camera permission was denied."
    case .hingesClosed:
      code = "hingesClosed"
      // DAT 0.9.0 also raises this when the glasses are taken off (doff), not
      // just when the arms are folded.
      message = "The glasses were closed or taken off."
    case .thermalCritical:
      code = "thermalCritical"
      message = "Device is overheating. Streaming has been paused to protect the device."
    case .thermalEmergency:
      code = "thermalEmergency"
      message = "Device thermal state is emergency — streaming stopped."
    case .peakPowerShutdown:
      code = "peakPowerShutdown"
      message = "Device exceeded peak power limit and shut down streaming."
    case .batteryCritical:
      code = "batteryCritical"
      message = "Device battery is critically low — streaming stopped."
    @unknown default:
      code = "unknown"
      message = "An unknown streaming error occurred."
    }

    return ["code": code, "message": message]
  }

  private static func map(deviceSessionError error: DeviceSessionError) -> (String, String) {
    switch error {
    case .noEligibleDevice:
      return ("noEligibleDevice", "No eligible device is available to start the session.")
    case .sessionAlreadyStopped:
      return ("sessionAlreadyStopped", "The device session has already been stopped.")
    case .sessionAlreadyExists:
      return ("sessionAlreadyExists", "A device session already exists for this device.")
    case .sessionIdle:
      return ("sessionIdle", "The device session has not been started yet.")
    case .capabilityAlreadyActive:
      return ("capabilityAlreadyActive", "A capability of this type is already attached to the session.")
    case .capabilityNotFound:
      return ("capabilityNotFound", "The requested capability is not attached to the session.")
    case .unexpectedError(let description):
      return ("unexpectedError", "Unexpected device session error: \(description)")
    case .thermalCritical:
      return ("deviceThermalCritical", "Device thermal state is critical.")
    case .thermalEmergency:
      return ("deviceThermalEmergency", "Device thermal state is emergency.")
    case .peakPowerShutdown:
      return ("devicePeakPowerShutdown", "Device exceeded peak power limit and shut down.")
    case .batteryCritical:
      return ("deviceBatteryCritical", "Device battery is critically low.")
    case .datAppOnTheGlassesUpdateRequired:
      return (
        "datAppOnTheGlassesUpdateRequired",
        "The DAT app on the glasses needs to be updated. Call MetaWearablesDat.openDATGlassesAppUpdate() to prompt the user."
      )
    case .dwaUnavailable:
      return ("dwaUnavailable", "The DAT Wearables App is unavailable.")
    @unknown default:
      return ("unknown", "An unknown device session error occurred.")
    }
  }
}
