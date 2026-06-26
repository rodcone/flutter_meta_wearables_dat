import AVFoundation
import CoreMedia
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

/// Identifies a glasses model for use with ``MockDeviceKitInterface/pairGlasses(model:)``.
///
/// Each case represents a supported displayless glasses model that MockDeviceKit can simulate.
/// Display-capable devices and non-glasses form factors will use separate types when supported.
public enum GlassesModel : String, CaseIterable, Sendable {

    /// Ray-Ban Meta smart glasses.
    case rayBanMeta

    /// Oakley Meta HSTN smart glasses.
    case oakleyMetaHSTN

    /// Oakley Meta Vanguard smart glasses.
    case oakleyMetaVanguard

    /// Ray-Ban Meta Optics smart glasses.
    case rayBanMetaOptics

    /// Meta Glasses smart glasses.
    case metaGlasses

    /// Creates a new instance with the specified raw value.
    ///
    /// If there is no value of the type that corresponds with the specified raw
    /// value, this initializer returns `nil`. For example:
    ///
    ///     enum PaperSize: String {
    ///         case A4, A5, Letter, Legal
    ///     }
    ///
    ///     print(PaperSize(rawValue: "Legal"))
    ///     // Prints "Optional(PaperSize.Legal)"
    ///
    ///     print(PaperSize(rawValue: "Tabloid"))
    ///     // Prints "nil"
    ///
    /// - Parameter rawValue: The raw value to use for the new instance.
    public init?(rawValue: String)

    /// A type that can represent a collection of all values of this type.
    public typealias AllCases = [MWDATMockDevice.GlassesModel]

    /// The raw type that can be used to represent all values of the conforming
    /// type.
    ///
    /// Every distinct value of the conforming type has a corresponding unique
    /// value of the `RawValue` type, but there may be values of the `RawValue`
    /// type that don't have a corresponding value of the conforming type.
    public typealias RawValue = String

    /// A collection of all values of this type.
    nonisolated public static var allCases: [MWDATMockDevice.GlassesModel] { get }

    /// The corresponding value of the raw type.
    ///
    /// A new instance initialized with `rawValue` will be equivalent to this
    /// instance. For example:
    ///
    ///     enum PaperSize: String {
    ///         case A4, A5, Letter, Legal
    ///     }
    ///
    ///     let selectedSize = PaperSize.Letter
    ///     print(selectedSize.rawValue)
    ///     // Prints "Letter"
    ///
    ///     print(selectedSize == PaperSize(rawValue: selectedSize.rawValue)!)
    ///     // Prints "true"
    public var rawValue: String { get }
}

extension GlassesModel : Equatable {
}

extension GlassesModel : Hashable {
}

extension GlassesModel : RawRepresentable {
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

/// Public interface for simulating captouch gestures on a mock device.
///
/// This interface allows test code to simulate captouch inputs that the device firmware would
/// normally send during an active session. These gestures are delivered to the SDK's session
/// and can trigger session behaviors like pause/resume or stop.
///
/// Usage example:
/// ```swift
/// let mockDevice = MockDeviceKit.shared.pairGlasses(type: .rayBanMeta)
/// mockDevice?.powerOn()
/// mockDevice?.don()
/// mockDevice?.unfold()
///
/// // Start a session, then simulate a tap gesture
/// mockDevice?.services.captouch.tap()
/// ```
public protocol MockCaptouchKit : Sendable {

    /// Simulate a single tap gesture on the device's capacitive touch sensor (1-finger captouch).
    ///
    /// The SDK's session will toggle between paused and running states, matching the behavior
    /// of a physical single tap on the glasses.
    ///
    /// Requires an active session — if no session is running, this call is a no-op with a warning log.
    func tap()

    /// Simulate a tap-and-hold gesture on the device's capacitive touch sensor (1-finger captouch).
    ///
    /// This stops the active session, matching the behavior of a physical tap-and-hold on the
    /// glasses which terminates the streaming session.
    ///
    /// Requires an active session — if no session is running, this call is a no-op with a warning log.
    func tapAndHold()
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

/// Errors thrown by MockDeviceKit.
public enum MockDeviceKitError : Error, Sendable, Equatable {

    /// MockDeviceKit is not enabled. Call ``MockDeviceKitInterface/enable(config:)`` first.
    case notEnabled

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

extension MockDeviceKitError : Hashable {
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

    /// Pairs a simulated glasses device of the specified model.
    ///
    /// - Parameter model: The glasses model to simulate.
    /// - Returns: A mock glasses instance.
    /// - Throws: ``MockDeviceKitError/notEnabled`` if MockDeviceKit has not been enabled.
    func pairGlasses(model: MWDATMockDevice.GlassesModel) throws(MWDATMockDevice.MockDeviceKitError) -> any MWDATMockDevice.MockGlasses

    /// Unpairs a simulated device.
    /// - Parameter device: The mock device to unpair.
    func unpairDevice(_ device: any MWDATMockDevice.MockDevice)

    /// The list of all currently paired mock devices.
    var pairedDevices: [any MWDATMockDevice.MockDevice] { get }

    /// Interface for configuring mock permission behavior.
    var permissions: any MWDATMockDevice.MockPermissions { get }

    /// Starts a local test server for mock device communication.
    /// - Parameter portFilePath: Optional path to a file where the server port will be written.
    /// - Returns: The port number the server is listening on.
    func startTestServer(portFilePath: String?) async throws -> UInt16

    /// Stops the running test server.
    func stopTestServer() async
}

extension MockDeviceKitInterface {

    public func enable()
}

/// Protocol for simulating smart glasses behavior in testing and development.
/// Provides functionality for simulating folding/unfolding actions and camera capabilities.
public protocol MockGlasses : MWDATMockDevice.MockDevice {

    /// Simulates folding the glasses into a closed position.
    func fold()

    /// Simulates unfolding the glasses into an open position.
    func unfold()

    /// Container for services available on this device.
    var services: any MWDATMockDevice.MockGlassesServices { get }
}

/// Container for accessing mock device service kits.
public protocol MockGlassesServices : Sendable {

    /// The suite for mocking camera functionality.
    var camera: any MWDATMockDevice.MockCameraKit { get }

    /// The suite for simulating captouch gestures (tap, hold, etc.).
    var captouch: any MWDATMockDevice.MockCaptouchKit { get }
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

@objc(MockCaptouchKit) final public class ObjC_MockCaptouchKit : NSObject, Sendable {

    /// Simulate a single tap gesture on the device's capacitive touch sensor.
    @objc final public func tap()

    /// Simulate a tap-and-hold gesture that stops the active session.
    @objc final public func tapAndHold()

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

    /// Pairs a simulated glasses device of the specified model.
    /// - Parameter modelRawValue: Raw string value of `GlassesModel` (e.g. `"Ray-Ban Meta"`).
    /// - Returns: A mock glasses device, or `nil` if the model is invalid or MockDeviceKit is not enabled.
    @objc final public func pairGlasses(modelRawValue: String) -> (any MWDATMockDevice.ObjC_MockGlasses)?

    /// Unpair simulated device
    @objc final public func unpairDevice(_ device: any MWDATMockDevice.ObjC_MockDevice)

    @objc deinit
}

@objc(MockGlasses) public protocol ObjC_MockGlasses : MWDATMockDevice.ObjC_MockDevice {

    /// Simulates folding the glasses into a closed position.
    @objc func fold()

    /// Simulates unfolding the glasses into an open position.
    @objc func unfold()

    /// Container for accessing mock device service kits (camera, voice invocation, etc.).
    @objc var services: MWDATMockDevice.ObjC_MockGlassesServices { get }
}

@objc(MockGlassesServices) final public class ObjC_MockGlassesServices : NSObject, Sendable {

    @objc final public let camera: MWDATMockDevice.ObjC_MockCameraKit

    @objc final public let captouch: MWDATMockDevice.ObjC_MockCaptouchKit

    @objc deinit
}

