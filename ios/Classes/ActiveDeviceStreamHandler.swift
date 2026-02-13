import Flutter
import MWDATCore

/// Stream handler for active device availability updates from the DAT SDK.
class ActiveDeviceStreamHandler: NSObject, FlutterStreamHandler {
  private var activeDeviceTask: Task<Void, Never>?
  private var deviceSelector: AutoDeviceSelector?
  private var linkStateListenerToken: AnyListenerToken?
  
  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    Task { @MainActor in
      // Create AutoDeviceSelector to monitor device availability
      self.deviceSelector = AutoDeviceSelector(wearables: Wearables.shared)
      
      // Helper function to check if device is actually active (connected)
      @MainActor
      func checkDeviceActive() {
        guard let deviceSelector = self.deviceSelector,
              let deviceId = deviceSelector.activeDevice else {
          events(false)
          return
        }
        
        // Get the device from wearables to check its link state
        if let device = Wearables.shared.deviceForIdentifier(deviceId) {
          // Device is active only if it's connected
          let isActive = device.linkState == .connected
          events(isActive)
        } else {
          // Device not found
          events(false)
        }
      }
      
      // Send initial state
      checkDeviceActive()
      
      // Listen to device availability changes
      guard let deviceSelector = self.deviceSelector else {
        return
      }
      
      self.activeDeviceTask = Task { @MainActor in
        for await deviceId in deviceSelector.activeDeviceStream() {
          // When device changes, check if it's actually connected
          if let deviceId = deviceId,
             let device = Wearables.shared.deviceForIdentifier(deviceId) {
            // Check initial link state
            let isActive = device.linkState == .connected
            events(isActive)
            
            // Also listen to link state changes for this device
            await self.linkStateListenerToken?.cancel()
            self.linkStateListenerToken = device.addLinkStateListener { [weak self] linkState in
              Task { @MainActor in
                let isActive = linkState == .connected
                events(isActive)
              }
            }
          } else {
            // No device or device not found
            await self.linkStateListenerToken?.cancel()
            events(false)
          }
        }
      }
    }
    
    return nil
  }
  
  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    Task { @MainActor in
      self.activeDeviceTask?.cancel()
      self.activeDeviceTask = nil
      await self.linkStateListenerToken?.cancel()
      self.linkStateListenerToken = nil
      self.deviceSelector = nil
    }
    return nil
  }
}
