import Flutter
import MWDATCore

/// Stream handler for per-device state updates (currently: thermal level).
///
/// 0.7.0 added `Wearables.deviceStateStream(for:)` keyed by `DeviceIdentifier`.
/// The plugin's Dart-facing API exposes a single `deviceStateStream()` that
/// tracks the *active* device, so this handler wraps the per-device stream in
/// an outer subscription to `activeDeviceStream()` and switches its inner
/// subscription whenever the active device changes.
class DeviceStateStreamHandler: NSObject, FlutterStreamHandler {
  private let deviceSelectorProvider: @MainActor () -> AutoDeviceSelector
  private var outerTask: Task<Void, Never>?
  private var eventSink: FlutterEventSink?
  // See `ActiveDeviceStreamHandler`: the outer `activeDeviceStream()` loop dies
  // on unregister, taking thermal updates with it. These let
  // `restartMonitoring()` relaunch the loop exactly once after re-registration.
  private var isMonitoring = false
  private var monitoringGeneration = 0

  init(deviceSelectorProvider: @escaping @MainActor () -> AutoDeviceSelector) {
    self.deviceSelectorProvider = deviceSelectorProvider
    super.init()
  }

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    startMonitoring()
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    outerTask?.cancel()
    outerTask = nil
    eventSink = nil
    isMonitoring = false
    return nil
  }

  /// Relaunch the active-device tracking loop after a disconnect/re-register
  /// cycle so thermal updates resume. Mirrors
  /// `ActiveDeviceStreamHandler.restartMonitoring()`; the `!isMonitoring` guard
  /// also keeps us from a rapid cancel+resubscribe of `deviceStateStream(for:)`
  /// for a still-active device (which the SDK answers with an empty stream).
  func restartMonitoring() {
    guard eventSink != nil else { return }
    guard !isMonitoring else { return }
    startMonitoring()
  }

  private func startMonitoring() {
    outerTask?.cancel()
    guard let events = eventSink else { return }
    monitoringGeneration += 1
    let generation = monitoringGeneration
    isMonitoring = true
    outerTask = Task { @MainActor in
      defer {
        if self.monitoringGeneration == generation { self.isMonitoring = false }
      }
      let selector = self.deviceSelectorProvider()
      var innerTask: Task<Void, Never>?
      var currentDeviceId: DeviceIdentifier?

      // Seed: if a device is already active, attach the inner subscription
      // immediately so Dart subscribers see the first thermal value without
      // waiting for an `activeDeviceStream` tick.
      if let deviceId = selector.activeDevice {
        currentDeviceId = deviceId
        innerTask = Self.subscribe(toDevice: deviceId, events: events)
      }

      for await deviceId in selector.activeDeviceStream() {
        // `activeDeviceStream()` replays the current value to new collectors,
        // so we'll get an emit for the device we just seeded. The SDK's
        // `deviceStateStream(for:)` doesn't tolerate rapid cancel+resubscribe
        // for the same device (the second subscription closes immediately
        // with 0 emits), so only tear down + restart when the device
        // actually changes.
        if deviceId == currentDeviceId { continue }
        innerTask?.cancel()
        innerTask = nil
        currentDeviceId = deviceId
        if let deviceId = deviceId {
          innerTask = Self.subscribe(toDevice: deviceId, events: events)
        }
      }

      innerTask?.cancel()
    }
  }

  @MainActor
  private static func subscribe(
    toDevice deviceId: DeviceIdentifier,
    events: @escaping FlutterEventSink
  ) -> Task<Void, Never> {
    return Task { @MainActor in
      for await state in Wearables.shared.deviceStateStream(for: deviceId) {
        events(Self.stateToMap(state))
      }
    }
  }

  private static func stateToMap(_ state: DeviceState) -> [String: Any] {
    return ["thermalLevel": thermalLevelToInt(state.thermalLevel)]
  }

  /// Mirrors the int values exposed by the Dart `ThermalLevel` enum.
  private static func thermalLevelToInt(_ level: ThermalLevel) -> Int {
    switch level {
    case .unknown:    return 0
    case .none:       return 1
    case .light:      return 2
    case .moderate:   return 3
    case .severe:     return 4
    case .critical:   return 5
    case .emergency:  return 6
    case .shutdown:   return 7
    @unknown default: return 0
    }
  }
}
