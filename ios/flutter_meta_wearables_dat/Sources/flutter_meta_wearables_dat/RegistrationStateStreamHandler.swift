import Flutter
import MWDATCore

/// Stream handler for registration state updates from the DAT SDK.
class RegistrationStateStreamHandler: NSObject, FlutterStreamHandler {
  private var registrationStateTask: Task<Void, Never>?
  
  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    Task { @MainActor in
      // Send initial state
      let initialState = Wearables.shared.registrationState
      events(initialState.rawValue)
      
      // Listen to state changes
      registrationStateTask = Task {
        for await state in Wearables.shared.registrationStateStream() {
          events(state.rawValue)
        }
      }
    }
    
    return nil
  }
  
  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    registrationStateTask?.cancel()
    registrationStateTask = nil
    return nil
  }
}
