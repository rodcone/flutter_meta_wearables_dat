import Flutter
import MWDATCore

/// Stream handler for active device availability updates from the DAT SDK.
class ActiveDeviceStreamHandler: NSObject, FlutterStreamHandler {
  private var activeDeviceTask: Task<Void, Never>?
  private var deviceSelector: AutoDeviceSelector?

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    Task { @MainActor in
      let selector = AutoDeviceSelector(wearables: Wearables.shared)
      self.deviceSelector = selector

      // Send initial state
      events(selector.activeDevice != nil)

      // Listen to device availability changes
      self.activeDeviceTask = Task { @MainActor in
        for await deviceId in selector.activeDeviceStream() {
          events(deviceId != nil)
        }
      }
    }

    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    Task { @MainActor in
      self.activeDeviceTask?.cancel()
      self.activeDeviceTask = nil
      self.deviceSelector = nil
    }
    return nil
  }
}
