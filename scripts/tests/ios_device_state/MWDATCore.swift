// Host-only controllable SDK boundary. The production handler is compiled unchanged.
import Foundation

public typealias DeviceIdentifier = String
public enum RegistrationState: Sendable { case available, registering, registered }
public enum LinkState: Sendable { case disconnected, connecting, connected }
public enum Compatibility: Sendable { case undefined, compatible, deviceUpdateRequired, sdkUpdateRequired }
public enum ChargingState: Sendable { case unknown, charging, notCharging }
public enum DonState: Sendable { case unknown, doffed, donned }
public enum HingeState: Sendable { case unknown, closed, open }
public enum ThermalLevel: CaseIterable, Sendable { case unknown, none, light, moderate, severe, critical, emergency, shutdown }
public struct DeviceState: Sendable {
  public var linkState: LinkState = .connected
  public var compatibility: Compatibility = .compatible
  public var batteryLevel: Int? = 72
  public var chargingState: ChargingState = .notCharging
  public var donState: DonState = .donned
  public var hingeState: HingeState = .open
  public var thermalLevel: ThermalLevel = .moderate
  public init() {}
}
public protocol AnyListenerToken { func cancel() async }
public final class Token: AnyListenerToken {
  public var cancelled = false
  public func cancel() async { cancelled = true }
}
public final class Device {
  public var state = DeviceState()
  public var listeners: [(DeviceState) -> Void] = []
  public var tokens: [Token] = []
  public init() {}
  public func addDeviceStateListener(_ listener: @escaping @Sendable (DeviceState) -> Void) -> any AnyListenerToken {
    listeners.append(listener)
    let token = Token(); tokens.append(token)
    listener(state)
    return token
  }
  public func emit() { for listener in listeners { listener(state) } }
}
public final class AutoDeviceSelector {
  public var activeDevice: String?
  public var continuations: [AsyncStream<String?>.Continuation] = []
  public init(_ id: String? = "a") { activeDevice = id }
  public func activeDeviceStream() -> AsyncStream<String?> {
    AsyncStream { continuation in
      continuations.append(continuation)
      continuation.yield(activeDevice)
    }
  }
  public func select(_ id: String?) {
    activeDevice = id
    for continuation in continuations { continuation.yield(id) }
  }
  public func finish() { for continuation in continuations { continuation.finish() } }
}
public final class Wearables {
  public init() {}
  public static var shared = Wearables()
  public var registrationState: RegistrationState = .registered
  public var devices: [String: Device] = [:]
  public var deviceContinuations: [AsyncStream<[String]>.Continuation] = []
  public func devicesStream() -> AsyncStream<[String]> {
    AsyncStream { continuation in
      deviceContinuations.append(continuation)
      continuation.yield(Array(devices.keys))
    }
  }
  public func announceDevices() {
    for continuation in deviceContinuations { continuation.yield(Array(devices.keys)) }
  }
  public var continuations: [AsyncStream<RegistrationState>.Continuation] = []
  public func deviceForIdentifier(_ id: String) -> Device? { devices[id] }
  public func registrationStateStream() -> AsyncStream<RegistrationState> {
    AsyncStream { continuation in
      continuations.append(continuation)
      continuation.yield(registrationState)
    }
  }
  public func registration(_ value: RegistrationState) {
    registrationState = value
    for continuation in continuations { continuation.yield(value) }
  }
}
