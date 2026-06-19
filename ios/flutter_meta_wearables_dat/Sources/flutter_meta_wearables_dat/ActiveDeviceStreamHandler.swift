import Flutter
import MWDATCore

/// Stream handler for active device availability updates from the DAT SDK.
///
/// Uses a provider closure to reach the plugin's long-lived `AutoDeviceSelector`
/// instead of spinning up a fresh one per `onListen`. A fresh selector needs a
/// moment to discover the active device, which produced spurious "waiting for
/// an active device" states when Dart subscribed late in the app lifecycle.
class ActiveDeviceStreamHandler: NSObject, FlutterStreamHandler {
  private let deviceSelectorProvider: @MainActor () -> any DeviceSelector
  private var activeDeviceTask: Task<Void, Never>?
  private var eventSink: FlutterEventSink?
  // True while the `activeDeviceStream()` collection loop is running. The SDK
  // terminates that stream when the device unregisters, so the loop exits and
  // is never restarted on its own — `restartMonitoring()` uses this flag to
  // tell a dead loop (safe to relaunch) from a healthy one (leave alone).
  private var isMonitoring = false
  // Bumped on every `startMonitoring()`. A cancelled task's `defer` can run
  // after its replacement has started; the generation check stops a stale
  // defer from clearing `isMonitoring` out from under the live run.
  private var monitoringGeneration = 0

  init(deviceSelectorProvider: @escaping @MainActor () -> any DeviceSelector) {
    self.deviceSelectorProvider = deviceSelectorProvider
    super.init()
  }

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    startMonitoring()
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    activeDeviceTask?.cancel()
    activeDeviceTask = nil
    eventSink = nil
    isMonitoring = false
    return nil
  }

  /// Relaunch the active-device collection loop after a disconnect/re-register
  /// cycle. Dart calls this via the `restartActiveDeviceMonitoring` method
  /// channel on returning from Meta AI; without it the loop stays dead and the
  /// active-device boolean never flips back to `true`. Idempotent — a no-op
  /// when there is no Dart subscriber or the loop is already healthy.
  ///
  /// Pass `force: true` when the plugin has swapped its `AutoDeviceSelector`:
  /// a healthy-looking loop may still be attached to the old (blind) selector
  /// instance, so it must be relaunched to pick up the new one.
  func restartMonitoring(force: Bool = false) {
    guard eventSink != nil else { return }
    if !force, isMonitoring { return }
    startMonitoring()
  }

  private func startMonitoring() {
    activeDeviceTask?.cancel()
    guard let events = eventSink else { return }
    monitoringGeneration += 1
    let generation = monitoringGeneration
    isMonitoring = true
    activeDeviceTask = Task { @MainActor in
      defer {
        if self.monitoringGeneration == generation { self.isMonitoring = false }
      }
      let selector = self.deviceSelectorProvider()

      // Seed the subscriber with the selector's current state so a device that
      // was already active before Dart subscribed is reported immediately.
      events(selector.activeDevice != nil)

      for await deviceId in selector.activeDeviceStream() {
        events(deviceId != nil)
      }
    }
  }
}
