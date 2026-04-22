import Flutter
import MWDATCore

/// Stream handler for active device availability updates from the DAT SDK.
///
/// Uses a provider closure to reach the plugin's long-lived `AutoDeviceSelector`
/// instead of spinning up a fresh one per `onListen`. A fresh selector needs a
/// moment to discover the active device, which produced spurious "waiting for
/// an active device" states when Dart subscribed late in the app lifecycle.
class ActiveDeviceStreamHandler: NSObject, FlutterStreamHandler {
  private let deviceSelectorProvider: @MainActor () -> AutoDeviceSelector
  private var activeDeviceTask: Task<Void, Never>?

  init(deviceSelectorProvider: @escaping @MainActor () -> AutoDeviceSelector) {
    self.deviceSelectorProvider = deviceSelectorProvider
    super.init()
  }

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    activeDeviceTask?.cancel()
    activeDeviceTask = Task { @MainActor in
      let selector = self.deviceSelectorProvider()

      // Seed the subscriber with the selector's current state so a device that
      // was already active before Dart subscribed is reported immediately.
      events(selector.activeDevice != nil)

      for await deviceId in selector.activeDeviceStream() {
        events(deviceId != nil)
      }
    }

    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    activeDeviceTask?.cancel()
    activeDeviceTask = nil
    return nil
  }
}
