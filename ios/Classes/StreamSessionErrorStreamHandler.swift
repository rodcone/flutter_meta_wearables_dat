import Flutter
import MWDATCamera
import MWDATCore

/// Stream handler for stream session errors.
///
/// Set the `session` property when a stream session is created.
/// Clear it when the session is torn down.
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
}
