// Host-only SDK doubles. Real SDK signatures are checked by the iOS build.
import Foundation
public protocol AnyListenerToken: Sendable { func cancel() async }
public final class Token: AnyListenerToken, @unchecked Sendable {
  private let lock = NSLock()
  private var count = 0
  public var cancellations: Int { lock.lock(); defer { lock.unlock() }; return count }
  public func cancel() async { increment() }
  private func increment() { lock.lock(); count += 1; lock.unlock() }
}
public enum LinkState { case connected, disconnected }
public enum DonState { case donned, doffed }
public enum HingeState { case open, closed }
public enum Compatibility { case compatible }
public enum ThermalLevel { case none }
public enum DeviceSessionState { case starting, stopped }
public enum DeviceSessionError {
  case unexpectedError(description: String)
  case noEligibleDevice
  public var description: String {
    switch self {
    case .unexpectedError(let message): return message
    case .noEligibleDevice: return "No eligible device"
    }
  }
}
public struct DeviceState {
  public var linkState = LinkState.connected
  public var donState = DonState.donned
  public var hingeState = HingeState.open
  public var compatibility = Compatibility.compatible
  public var batteryLevel: Int? = nil
  public var thermalLevel = ThermalLevel.none
  public init() {}
}
public final class Device {
  public let linkState = LinkState.connected
  public let donState = DonState.donned
  public let hingeState = HingeState.open
  public let batteryLevel: Int? = nil
  public let thermalLevel = ThermalLevel.none
  public func compatibility() -> Compatibility { .compatible }
  public let linkToken = Token()
  public let stateToken = Token()
  public var linkCallback: (@Sendable (LinkState) -> Void)?
  public var stateCallback: (@Sendable (DeviceState) -> Void)?
  public init() {}
  public func addLinkStateListener(_ listener: @escaping @Sendable (LinkState) -> Void) -> any AnyListenerToken {
    linkCallback = listener; return linkToken
  }
  public func addDeviceStateListener(_ listener: @escaping @Sendable (DeviceState) -> Void) -> any AnyListenerToken {
    stateCallback = listener; listener(DeviceState()); return stateToken
  }
}
