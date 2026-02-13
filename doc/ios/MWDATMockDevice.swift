import AVFoundation
import Foundation
import MWDATCore

/// A suite for mocking camera functionality.
public protocol MockCameraKit {

    /// Sets the camera feed from a video file.
    ///
    /// Supported codecs: h.265
    ///
    /// - Parameter fileURL: URL of the file containing the video stream.
    func setCameraFeed(fileURL: URL) async

    /// Sets the captured image from an image file.
    /// - Parameter fileURL: URL of the file containing the image.
    func setCapturedImage(fileURL: URL) async
}

@MainActor public protocol MockDevice {

    /// The unique device identifier for this mock device.
    @MainActor var deviceIdentifier: MWDATCore.DeviceIdentifier { get }

    /// Powers on the mock device.
    @MainActor func powerOn()

    /// Powers off the mock device.
    @MainActor func powerOff()

    /// Simulates putting on (donning) the device.
    @MainActor func don()

    /// Simulates taking off (doffing) the device.
    @MainActor func doff()
}

/// The entry-point to the MockDeviceKit for managing simulated Meta Wearables devices.
/// Use this in testing and development scenarios to simulate real hardware behavior.
@MainActor public enum MockDeviceKit {

    /// The shared instance of MockDeviceKit for managing simulated devices.
    @MainActor public static let shared: any MWDATMockDevice.MockDeviceKitInterface
}

extension MockDeviceKit : Sendable {
}

/// Errors that can occur when using MockDeviceKit.
@frozen public enum MockDeviceKitError : Error {

    /// A generic unknown error occurred.
    case unknown

    /// Returns a Boolean value indicating whether two values are equal.
    ///
    /// Equality is the inverse of inequality. For any values `a` and `b`,
    /// `a == b` implies that `a != b` is `false`.
    ///
    /// - Parameters:
    ///   - lhs: A value to compare.
    ///   - rhs: Another value to compare.
    public static func == (a: MWDATMockDevice.MockDeviceKitError, b: MWDATMockDevice.MockDeviceKitError) -> Bool

    /// Hashes the essential components of this value by feeding them into the
    /// given hasher.
    ///
    /// Implement this method to conform to the `Hashable` protocol. The
    /// components used for hashing must be the same as the components compared
    /// in your type's `==` operator implementation. Call `hasher.combine(_:)`
    /// with each of these components.
    ///
    /// - Important: In your implementation of `hash(into:)`,
    ///   don't call `finalize()` on the `hasher` instance provided,
    ///   or replace it with a different instance.
    ///   Doing so may become a compile-time error in the future.
    ///
    /// - Parameter hasher: The hasher to use when combining the components
    ///   of this instance.
    public func hash(into hasher: inout Hasher)

    /// The hash value.
    ///
    /// Hash values are not guaranteed to be equal across different executions of
    /// your program. Do not save hash values to use during a future execution.
    ///
    /// - Important: `hashValue` is deprecated as a `Hashable` requirement. To
    ///   conform to `Hashable`, implement the `hash(into:)` requirement instead.
    ///   The compiler provides an implementation for `hashValue` for you.
    public var hashValue: Int { get }
}

extension MockDeviceKitError : Equatable {
}

extension MockDeviceKitError : Hashable {
}

extension MockDeviceKitError : BitwiseCopyable {
}

/// Interface for managing mock Meta Wearables devices for testing and development.
@MainActor public protocol MockDeviceKitInterface {

    /// Pairs a simulated Ray-Ban Meta device.
    /// - Returns: A mock Ray-Ban Meta device instance.
    @MainActor func pairRaybanMeta() -> any MWDATMockDevice.MockRaybanMeta

    /// Unpairs a simulated device.
    /// - Parameter device: The mock device to unpair.
    @MainActor func unpairDevice(_ device: any MWDATMockDevice.MockDevice)

    /// The list of all currently paired mock devices.
    @MainActor var pairedDevices: [any MWDATMockDevice.MockDevice] { get }
}

/// Protocol for simulating displayless smart glasses behavior in testing and development.
/// Provides functionality for simulating folding/unfolding actions and camera capabilities.
@MainActor public protocol MockDisplaylessGlasses : MWDATMockDevice.MockDevice {

    /// Simulates folding the glasses into a closed position.
    @MainActor func fold()

    /// Simulates unfolding the glasses into an open position.
    @MainActor func unfold()

    /// Gets the suite for mocking camera functionality.
    /// - Returns: A MockCameraKit instance for controlling camera features.
    @MainActor func getCameraKit() -> any MWDATMockDevice.MockCameraKit
}

/// Protocol for simulating Ray-Ban Meta smart glasses behavior in testing and development.
/// Inherits all functionality from MockDisplaylessGlasses while providing a specific type
/// for Ray-Ban Meta device simulation.
@MainActor public protocol MockRaybanMeta : MWDATMockDevice.MockDisplaylessGlasses {
}

@objc(MockCameraKit) final public class ObjC_MockCameraKit : NSObject {

    /// Set camera feed from a video file. Supported codecs: h.265
    /// - Parameter fileURL: URL of the file containing video stream
    @objc final public func setCameraFeed(fileURL: URL) async

    /// Set captured image from an image file.
    /// - Parameter fileURL: URL of the file containing image
    @objc final public func setCapturedImage(fileURL: URL) async

    @objc deinit
}

@MainActor @objc(MockDevice) public protocol ObjC_MockDevice {

    /// Returns the device identifier
    @MainActor @objc var deviceIdentifier: String { get }

    /// Powers on the mock device.
    @MainActor @objc func powerOn()

    //// Powers off the mock device.
    @MainActor @objc func powerOff()

    //// Simulates putting on (donning) the device.
    @MainActor @objc func don()

    //// Simulates taking off (doffing) the device.
    @MainActor @objc func doff()
}

@MainActor @objc(MWDATMockDeviceKit) final public class ObjC_MockDeviceKit : NSObject {

    @MainActor @objc public static let sharedInstance: MWDATMockDevice.ObjC_MockDeviceKit

    /// All paired devices.
    @MainActor @objc final public var pairedDevices: [any MWDATMockDevice.ObjC_MockDevice] { get }

    /// Pair simulated RBM glasses
    @MainActor @objc final public func pairRaybanMeta() -> any MWDATMockDevice.ObjC_MockRaybanMeta

    /// Unpair simulated device
    @MainActor @objc final public func unpairDevice(_ device: any MWDATMockDevice.ObjC_MockDevice)

    @objc deinit
}

extension ObjC_MockDeviceKit : Sendable {
}

@MainActor @objc(MockDisplaylessGlasses) public protocol ObjC_MockDisplaylessGlasses : MWDATMockDevice.ObjC_MockDevice {

    /// Simulates folding the glasses into a closed position.
    @MainActor @objc func fold()

    /// Simulates unfolding the glasses into an open position.
    @MainActor @objc func unfold()

    /// Get the suite for mocking the camera functionality.
    @MainActor @objc func getCameraKit() -> MWDATMockDevice.ObjC_MockCameraKit
}

@MainActor @objc(MockRaybanMeta) public protocol ObjC_MockRaybanMeta : MWDATMockDevice.ObjC_MockDisplaylessGlasses {
}

