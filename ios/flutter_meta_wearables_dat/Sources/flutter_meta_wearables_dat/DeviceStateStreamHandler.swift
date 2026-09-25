import Flutter
import MWDATCore

/// Observes the selected device's thermal state through DAT 1.0 Device listeners.
class DeviceStateStreamHandler: NSObject, FlutterStreamHandler {
  private let deviceSelectorProvider: @MainActor () -> AutoDeviceSelector
  private var outerTask: Task<Void, Never>?
  private var listenerToken: AnyListenerToken?
  private var eventSink: FlutterEventSink?
  private var isMonitoring = false
  private var monitoringGeneration = 0
  private var deviceGeneration = 0

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
    monitoringGeneration &+= 1
    outerTask?.cancel()
    outerTask = nil
    cancelDeviceListener()
    eventSink = nil
    isMonitoring = false
    return nil
  }

  func restartMonitoring(force: Bool = false) {
    guard eventSink != nil else { return }
    if !force, isMonitoring { return }
    startMonitoring()
  }

  private func cancelDeviceListener() {
    // Cancellation is async: invalidate queued callbacks before scheduling it.
    deviceGeneration &+= 1
    if let token = listenerToken {
      listenerToken = nil
      Task { await token.cancel() }
    }
  }

  private func startMonitoring() {
    outerTask?.cancel()
    cancelDeviceListener()
    guard eventSink != nil else { return }
    monitoringGeneration &+= 1
    let generation = monitoringGeneration
    isMonitoring = true
    outerTask = Task { @MainActor in
      defer {
        if self.monitoringGeneration == generation {
          self.isMonitoring = false
          self.cancelDeviceListener()
        }
      }
      guard !Task.isCancelled, self.monitoringGeneration == generation else { return }
      let selector = self.deviceSelectorProvider()
      var currentDeviceId = selector.activeDevice
      if let deviceId = currentDeviceId { self.subscribe(toDevice: deviceId) }
      for await deviceId in selector.activeDeviceStream() {
        guard !Task.isCancelled, self.monitoringGeneration == generation else { return }
        if deviceId == currentDeviceId { continue }
        self.cancelDeviceListener()
        currentDeviceId = deviceId
        if let deviceId = deviceId { self.subscribe(toDevice: deviceId) }
      }
    }
  }

  @MainActor
  private func subscribe(toDevice deviceId: DeviceIdentifier) {
    guard let device = Wearables.shared.deviceForIdentifier(deviceId) else { return }
    let generation = deviceGeneration
    // The SDK delivers a snapshot immediately, then on each device-state change.
    listenerToken = device.addDeviceStateListener { [weak self] state in
      Task { @MainActor in
        guard let self, self.deviceGeneration == generation else { return }
        self.eventSink?(Self.stateToMap(state))
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
