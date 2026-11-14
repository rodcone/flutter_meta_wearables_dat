import Flutter
import Foundation
import MWDATCore

/// Observes physical and connection metadata without owning a device session.
class DeviceStateStreamHandler: NSObject, FlutterStreamHandler {
  private let deviceSelectorProvider: @MainActor () -> AutoDeviceSelector
  private var registrationTask: Task<Void, Never>?
  private var outerTask: Task<Void, Never>?
  private var deviceListTask: Task<Void, Never>?
  private var listenerToken: AnyListenerToken?
  private var eventSink: FlutterEventSink?
  private var monitoringGeneration = 0
  private var selectionGeneration = 0
  private var deviceGeneration = 0
  private var disposed = false

  init(deviceSelectorProvider: @escaping @MainActor () -> AutoDeviceSelector) {
    self.deviceSelectorProvider = deviceSelectorProvider
    super.init()
  }

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    guard !disposed else { return nil }
    eventSink = events
    startMonitoring()
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    monitoringGeneration &+= 1
    registrationTask?.cancel()
    registrationTask = nil
    cancelSelection()
    eventSink = nil
    return nil
  }

  func dispose() {
    _ = onCancel(withArguments: nil)
    disposed = true
  }

  func restartMonitoring(force: Bool = false) {
    guard !disposed, eventSink != nil else { return }
    if !force, registrationTask != nil, outerTask != nil { return }
    startMonitoring()
  }

  private func cancelDeviceListener() {
    deviceGeneration &+= 1
    if let token = listenerToken {
      listenerToken = nil
      Task { await token.cancel() }
    }
  }

  private func cancelSelection() {
    selectionGeneration &+= 1
    outerTask?.cancel()
    outerTask = nil
    deviceListTask?.cancel()
    deviceListTask = nil
    cancelDeviceListener()
  }

  private func startMonitoring() {
    monitoringGeneration &+= 1
    registrationTask?.cancel()
    cancelSelection()
    eventSink?(Self.emptySnapshot())
    let generation = monitoringGeneration
    registrationTask = Task { @MainActor [weak self] in
      guard let self, !Task.isCancelled, self.monitoringGeneration == generation else { return }
      defer {
        if self.monitoringGeneration == generation {
          self.registrationTask = nil
          self.cancelSelection()
          self.eventSink?(Self.emptySnapshot())
        }
      }
      let states = Wearables.shared.registrationStateStream()
      var registered = Wearables.shared.registrationState == .registered
      if registered { self.startSelection() }
      for await state in states {
        guard !Task.isCancelled, self.monitoringGeneration == generation else { return }
        let next = state == .registered
        if next == registered { continue }
        registered = next
        self.cancelSelection()
        self.eventSink?(Self.emptySnapshot())
        if registered { self.startSelection() }
      }
    }
  }

  @MainActor
  private func startSelection() {
    let generation = selectionGeneration
    outerTask = Task { @MainActor [weak self] in
      guard let self, !Task.isCancelled, self.selectionGeneration == generation else { return }
      defer {
        if self.selectionGeneration == generation {
          self.outerTask = nil
          self.deviceListTask?.cancel()
          self.deviceListTask = nil
          self.cancelDeviceListener()
          self.eventSink?(Self.emptySnapshot())
        }
      }
      let selector = self.deviceSelectorProvider()
      let devices = selector.activeDeviceStream()
      var knownDeviceIds: Set<DeviceIdentifier>?
      self.deviceListTask = Task { @MainActor [weak self] in
        for await ids in Wearables.shared.devicesStream() {
          guard let self, !Task.isCancelled, self.selectionGeneration == generation else { return }
          knownDeviceIds = Set(ids)
          if let id = selector.activeDevice, ids.contains(id) {
            if self.listenerToken == nil { self.subscribe(toDevice: id) }
          } else {
            self.cancelDeviceListener()
            self.eventSink?(Self.emptySnapshot())
          }
        }
      }
      var currentDeviceId = selector.activeDevice
      if let id = currentDeviceId { self.subscribe(toDevice: id) }
      for await selectedId in devices {
        guard !Task.isCancelled, self.selectionGeneration == generation else { return }
        // The selector can replay an ID after the SDK has removed its device.
        let id = selectedId.flatMap { knownDeviceIds?.contains($0) == false ? nil : $0 }
        if id == currentDeviceId, id == nil || self.listenerToken != nil { continue }
        self.cancelDeviceListener()
        currentDeviceId = id
        self.eventSink?(Self.emptySnapshot())
        if let id { self.subscribe(toDevice: id) }
      }
    }
  }

  @MainActor
  private func subscribe(toDevice id: DeviceIdentifier) {
    eventSink?(Self.emptySnapshot(id: id))
    guard let device = Wearables.shared.deviceForIdentifier(id) else { return }
    let generation = deviceGeneration
    listenerToken = device.addDeviceStateListener { [weak self] state in
      Task { @MainActor in
        guard let self, self.deviceGeneration == generation,
              Wearables.shared.registrationState == .registered else { return }
        self.eventSink?(Self.stateToMap(state, id: id))
      }
    }
  }

  private static func emptySnapshot(id: DeviceIdentifier? = nil) -> [String: Any] {
    ["deviceId": id as Any? ?? NSNull(), "linkState": "unknown", "compatibility": "undefined",
     "thermalLevel": 0, "batteryLevel": NSNull(), "chargingState": "unknown",
     "donState": "unknown", "hingeState": "unknown"]
  }

  private static func stateToMap(_ state: DeviceState, id: DeviceIdentifier) -> [String: Any] {
    let connected = state.linkState == .connected
    let battery = state.batteryLevel.flatMap { connected && (0...100).contains($0) ? $0 : nil }
    return [
      "deviceId": id,
      "linkState": linkCode(state.linkState),
      "compatibility": compatibilityCode(state.compatibility),
      "thermalLevel": connected ? thermalLevelToInt(state.thermalLevel) : 0,
      "batteryLevel": battery as Any? ?? NSNull(),
      "chargingState": connected ? chargingCode(state.chargingState) : "unknown",
      "donState": connected ? donCode(state.donState) : "unknown",
      "hingeState": connected ? hingeCode(state.hingeState) : "unknown",
    ]
  }

  private static func linkCode(_ value: LinkState) -> String {
    switch value {
    case .connected: return "connected"
    case .connecting: return "connecting"
    case .disconnected: return "disconnected"
    @unknown default: return "unknown"
    }
  }

  private static func compatibilityCode(_ value: Compatibility) -> String {
    switch value {
    case .compatible: return "compatible"
    case .deviceUpdateRequired: return "deviceUpdateRequired"
    case .sdkUpdateRequired: return "sdkUpdateRequired"
    default: return "undefined"
    }
  }

  private static func chargingCode(_ value: ChargingState) -> String {
    switch value {
    case .charging: return "charging"
    case .notCharging: return "notCharging"
    default: return "unknown"
    }
  }

  private static func donCode(_ value: DonState) -> String {
    switch value {
    case .donned: return "donned"
    case .doffed: return "doffed"
    default: return "unknown"
    }
  }

  private static func hingeCode(_ value: HingeState) -> String {
    switch value {
    case .open: return "open"
    case .closed: return "closed"
    default: return "unknown"
    }
  }

  private static func thermalLevelToInt(_ level: ThermalLevel) -> Int {
    switch level {
    case .unknown: return 0
    case .none: return 1
    case .light: return 2
    case .moderate: return 3
    case .severe: return 4
    case .critical: return 5
    case .emergency: return 6
    case .shutdown: return 7
    @unknown default: return 0
    }
  }
}
