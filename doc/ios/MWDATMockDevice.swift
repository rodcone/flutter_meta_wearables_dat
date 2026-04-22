import AVFoundation
import Foundation
import ImageIO
import MWDATCore
import Network

/// The camera to use for live streaming from the phone.
public enum CameraFacing : Sendable {

    case front

    case back

    /// Returns a Boolean value indicating whether two values are equal.
    ///
    /// Equality is the inverse of inequality. For any values `a` and `b`,
    /// `a == b` implies that `a != b` is `false`.
    ///
    /// - Parameters:
    ///   - lhs: A value to compare.
    ///   - rhs: Another value to compare.
    public static func == (a: MWDATMockDevice.CameraFacing, b: MWDATMockDevice.CameraFacing) -> Bool

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

extension CameraFacing : Equatable {
}

extension CameraFacing : Hashable {
}

/// A suite for mocking camera functionality.
public protocol MockCameraKit : Sendable {

    /// Sets the camera feed from a video file.
    ///
    /// Supported codecs: h.265
    ///
    /// Mutually exclusive with ``setCameraFeed(cameraFacing:)``.
    /// Calling this clears any active camera source.
    ///
    /// - Parameter fileURL: URL of the file containing the video stream.
    func setCameraFeed(fileURL: URL)

    /// Sets the camera feed to stream live from the phone's camera.
    ///
    /// Mutually exclusive with ``setCameraFeed(fileURL:)``.
    /// Calling this clears any active camera feed file.
    ///
    /// - Parameter cameraFacing: Which phone camera to use.
    func setCameraFeed(cameraFacing: MWDATMockDevice.CameraFacing) async

    /// Sets the captured image from an image file.
    /// - Parameter fileURL: URL of the file containing the image.
    func setCapturedImage(fileURL: URL)
}

public protocol MockDevice : Sendable {

    /// The unique device identifier for this mock device.
    var deviceIdentifier: MWDATCore.DeviceIdentifier { get }

    /// Powers on the mock device.
    func powerOn()

    /// Powers off the mock device.
    func powerOff()

    /// Simulates putting on (donning) the device.
    func don()

    /// Simulates taking off (doffing) the device.
    func doff()
}

/// The entry-point to the MockDeviceKit for managing simulated Meta Wearables devices.
/// Use this in testing and development scenarios to simulate real hardware behavior.
public enum MockDeviceKit : Sendable {

    /// The shared instance of MockDeviceKit for managing simulated devices.
    public static let shared: any MWDATMockDevice.MockDeviceKitInterface
}

/// Configuration options for MockDeviceKit.
@frozen public struct MockDeviceKitConfig : Sendable {

    /// Whether the mock device should start in a registered state.
    /// When `true` (default), `enable()` immediately transitions to `.registered`.
    /// When `false`, the state starts as `.unavailable`, allowing `startRegistration()` to be tested.
    public let initiallyRegistered: Bool

    /// Whether permissions should start as granted.
    /// When `true` (default), all permissions are granted after `enable()`.
    /// When `false`, all permissions start denied — tests must explicitly grant via `set(_ permission:, .granted)`.
    /// Forced to `false` when `initiallyRegistered` is `false` (can't have permissions without registration).
    public let initialPermissionsGranted: Bool

    public init(initiallyRegistered: Bool = true, initialPermissionsGranted: Bool = true)
}

extension MockDeviceKitConfig : BitwiseCopyable {
}

/// Interface for managing mock Meta Wearables devices for testing and development.
public protocol MockDeviceKitInterface : Sendable {

    /// Whether MockDeviceKit is currently enabled.
    var isEnabled: Bool { get }

    /// Enables MockDeviceKit, injecting fake providers into the registration and device layers.
    ///
    /// Safe to call regardless of whether `Wearables.configure()` has been called —
    /// MockDeviceKit will auto-configure Wearables if needed.
    ///
    /// - Parameter config: Configuration options for MockDeviceKit behavior.
    func enable(config: MWDATMockDevice.MockDeviceKitConfig)

    /// Disables MockDeviceKit, restoring real providers and unpairing all mock devices.
    func disable()

    /// Pairs a simulated Ray-Ban Meta device.
    /// MockDeviceKit must be enabled before calling this method.
    /// - Returns: A mock Ray-Ban Meta device instance.
    func pairRaybanMeta() -> any MWDATMockDevice.MockRaybanMeta

    /// Unpairs a simulated device.
    /// - Parameter device: The mock device to unpair.
    func unpairDevice(_ device: any MWDATMockDevice.MockDevice)

    /// The list of all currently paired mock devices.
    var pairedDevices: [any MWDATMockDevice.MockDevice] { get }

    /// Interface for configuring mock permission behavior.
    var permissions: any MWDATMockDevice.MockPermissions { get }
}

extension MockDeviceKitInterface {

    public func enable()
}

/// Protocol for simulating displayless smart glasses behavior in testing and development.
/// Provides functionality for simulating folding/unfolding actions and camera capabilities.
public protocol MockDisplaylessGlasses : MWDATMockDevice.MockDevice {

    /// Simulates folding the glasses into a closed position.
    func fold()

    /// Simulates unfolding the glasses into an open position.
    func unfold()

    /// Container for services available on this device.
    var services: any MWDATMockDevice.MockDisplaylessGlassesServices { get }
}

/// Container for accessing mock device service kits.
public protocol MockDisplaylessGlassesServices : Sendable {

    /// The suite for mocking camera functionality.
    var camera: any MWDATMockDevice.MockCameraKit { get }
}

/// Interface for configuring mock permission behavior during testing.
///
/// Use this to simulate granted/denied permission states and control
/// the outcome of `requestPermission()` calls without launching the
/// Meta AI companion app.
public protocol MockPermissions : Sendable {

    /// Sets the status of a permission on the mock device.
    ///
    /// This affects both `checkPermissionStatus()` (via the DataX service)
    /// and subsequent `requestPermission()` calls.
    ///
    /// - Parameters:
    ///   - permission: The permission to configure.
    ///   - status: The status to assign to the permission.
    func set(_ permission: MWDATCore.Permission, _ status: MWDATCore.PermissionStatus)

    /// Configures the result that `requestPermission()` will return for a
    /// specific permission.
    ///
    /// - Parameters:
    ///   - permission: The permission to configure.
    ///   - result: The status to return when the permission is requested.
    func setRequestResult(_ permission: MWDATCore.Permission, result: MWDATCore.PermissionStatus)
}

/// Protocol for simulating Ray-Ban Meta smart glasses behavior in testing and development.
/// Inherits all functionality from MockDisplaylessGlasses while providing a specific type
/// for Ray-Ban Meta device simulation.
public protocol MockRaybanMeta : MWDATMockDevice.MockDisplaylessGlasses {
}

@objc(MockCameraKit) final public class ObjC_MockCameraKit : NSObject, Sendable {

    /// Set camera feed from a video file. Supported codecs: h.265
    /// - Parameter fileURL: URL of the file containing video stream
    @objc final public func setCameraFeed(fileURL: URL)

    /// Set the camera source to stream live from the phone's camera.
    /// - Parameter cameraFacing: 0 for front camera, 1 for back camera.
    @objc final public func setCameraFeed(cameraFacing: Int) async

    /// Set captured image from an image file.
    /// - Parameter fileURL: URL of the file containing image
    @objc final public func setCapturedImage(fileURL: URL)

    @objc deinit
}

@objc(MockDevice) public protocol ObjC_MockDevice : Sendable {

    /// Returns the device identifier
    @objc var deviceIdentifier: String { get }

    /// Powers on the mock device.
    @objc func powerOn()

    /// Powers off the mock device.
    @objc func powerOff()

    /// Simulates putting on (donning) the device.
    @objc func don()

    /// Simulates taking off (doffing) the device.
    @objc func doff()
}

@objc(MWDATMockDeviceKit) final public class ObjC_MockDeviceKit : NSObject, Sendable {

    @objc public static let sharedInstance: MWDATMockDevice.ObjC_MockDeviceKit

    /// Whether MockDeviceKit is currently enabled.
    @objc final public var isEnabled: Bool { get }

    /// Enables MockDeviceKit with the default configuration (initially registered).
    @objc final public func enable()

    /// Enables MockDeviceKit with the specified initial registration state.
    /// - Parameter initiallyRegistered: When `true`, enables in `.registered` state.
    ///   When `false`, enables in `.unavailable` state, allowing `startRegistration()` to be tested.
    @objc final public func enable(initiallyRegistered: Bool)

    /// Disables MockDeviceKit and unpairs all devices.
    @objc final public func disable()

    /// All paired devices.
    @objc final public var pairedDevices: [any MWDATMockDevice.ObjC_MockDevice] { get }

    /// Pair simulated RBM glasses
    @objc final public func pairRaybanMeta() -> any MWDATMockDevice.ObjC_MockRaybanMeta

    /// Unpair simulated device
    @objc final public func unpairDevice(_ device: any MWDATMockDevice.ObjC_MockDevice)

    @objc deinit
}

@objc(MockDisplaylessGlasses) public protocol ObjC_MockDisplaylessGlasses : MWDATMockDevice.ObjC_MockDevice {

    /// Simulates folding the glasses into a closed position.
    @objc func fold()

    /// Simulates unfolding the glasses into an open position.
    @objc func unfold()

    /// Container for accessing mock device service kits (camera, voice invocation, etc.).
    @objc var services: MWDATMockDevice.ObjC_MockDisplaylessGlassesServices { get }
}

@objc(MockDisplaylessGlassesServices) final public class ObjC_MockDisplaylessGlassesServices : NSObject, Sendable {

    @objc final public let camera: MWDATMockDevice.ObjC_MockCameraKit

    @objc deinit
}

@objc(MockRaybanMeta) public protocol ObjC_MockRaybanMeta : MWDATMockDevice.ObjC_MockDisplaylessGlasses {
}

