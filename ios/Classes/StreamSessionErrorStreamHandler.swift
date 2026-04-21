import Flutter
import MWDATCamera
import MWDATCore

/// Stream handler for stream-related errors (both `StreamSession` errors and
/// the `DeviceSession` errors that gate the stream). They share the same
/// Flutter event channel because the Dart side exposes a single
/// `streamSessionErrorStream()` API — consumers don't need to care which
/// layer produced the error.
///
/// Set `session` when a `StreamSession` is created; clear it on teardown.
/// Pre-stream failures (createSession / DeviceSession.start / addStream
/// throws) are forwarded via `sendError(code:message:)`.
class StreamSessionErrorStreamHandler: NSObject, FlutterStreamHandler {
  /// The active stream session to observe. Setting this property
  /// re-subscribes to the session's error publisher.
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

  /// Pushes a synthesised error onto the event channel. Used by the plugin
  /// to surface errors that happen before a `StreamSession` exists (e.g.
  /// `DeviceSession.start()` throwing `.noEligibleDevice`).
  func sendError(code: String, message: String) {
    guard let events = eventSink else { return }
    Task { @MainActor in
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

    listenerToken = session.errorPublisher.listen { error in
      Task { @MainActor in
        let payload = Self.errorToMap(error)
        events(payload)
      }
    }
  }

  private func cancelListener() {
    if let token = listenerToken {
      Task { await token.cancel() }
      listenerToken = nil
    }
  }

  /// Converts a StreamSessionError to a dictionary for the platform channel.
  private static func errorToMap(_ error: StreamSessionError) -> [String: Any] {
    let code: String
    let message: String

    switch error {
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
      message = "The hinges on the glasses were closed."
    case .thermalCritical:
      code = "thermalCritical"
      message = "Device is overheating. Streaming has been paused to protect the device."
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
    @unknown default:
      return ("unknown", "An unknown device session error occurred.")
    }
  }
}
