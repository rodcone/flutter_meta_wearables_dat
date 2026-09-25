// ⚠️ Reference snapshot of the DAT MockDevice API — may lag the vendored binaries.
// Authoritative source: the vendored `.swiftinterface` under
// flutter_meta_wearables_dat_mock_device/ios/.../Frameworks/MWDATMockDevice.xcframework/.../*.swiftinterface
import AVFoundation
import CoreMedia
import Foundation
import ImageIO
import MWDATCore
import Network
import Speech
import UIKit
import simd

/// A named hardware button.
///
/// @Unpublishable
@frozen public enum ButtonType : Sendable, Equatable {

    /// The primary action button.
    case action

    /// Returns a Boolean value indicating whether two values are equal.
    ///
    /// Equality is the inverse of inequality. For any values `a` and `b`,
    /// `a == b` implies that `a != b` is `false`.
    ///
    /// - Parameters:
    ///   - lhs: A value to compare.
    ///   - rhs: Another value to compare.
    public static func == (a: MWDATMockDevice.ButtonType, b: MWDATMockDevice.ButtonType) -> Bool

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

extension ButtonType : Hashable {
}

extension ButtonType : BitwiseCopyable {
}

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

/// The physical capture-button gesture.
///
/// @Unpublishable
@frozen public enum CapturePressType : Sendable, Equatable {

    /// A single short press of the capture button. Defaults to capturing a photo.
    case shortPress

    /// A press and hold of the capture button. Defaults to starting a video recording.
    case hold

    /// A double press of the capture button. Defaults to stopping an in-progress video recording.
    case doublePress

    /// Returns a Boolean value indicating whether two values are equal.
    ///
    /// Equality is the inverse of inequality. For any values `a` and `b`,
    /// `a == b` implies that `a != b` is `false`.
    ///
    /// - Parameters:
    ///   - lhs: A value to compare.
    ///   - rhs: Another value to compare.
    public static func == (a: MWDATMockDevice.CapturePressType, b: MWDATMockDevice.CapturePressType) -> Bool

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

extension CapturePressType : Hashable {
}

extension CapturePressType : BitwiseCopyable {
}

/// The phase of a drag interaction.
///
/// @Unpublishable
@frozen public enum DragAction : Sendable, Equatable {

    /// The pointer went down, beginning the drag.
    case down

    /// The pointer moved while down.
    case move

    /// The pointer went up, ending the drag.
    case up

    /// Returns a Boolean value indicating whether two values are equal.
    ///
    /// Equality is the inverse of inequality. For any values `a` and `b`,
    /// `a == b` implies that `a != b` is `false`.
    ///
    /// - Parameters:
    ///   - lhs: A value to compare.
    ///   - rhs: Another value to compare.
    public static func == (a: MWDATMockDevice.DragAction, b: MWDATMockDevice.DragAction) -> Bool

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

extension DragAction : Hashable {
}

extension DragAction : BitwiseCopyable {
}

/// Identifies a glasses model for use with ``MockDeviceKitInterface/pairGlasses(model:)``.
///
/// Each case represents a supported glasses model that MockDeviceKit can simulate.
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

    /// Meta Ray-Ban Display smart glasses.
    case metaRayBanDisplay

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

/// The device surface that produced an input event.
///
/// @Unpublishable
@frozen public enum InputSource : Sendable, Equatable {

    /// The capacitive touchpad on the glasses.
    case captouch

    /// Neural Band discrete gesture input.
    case neuralBand

    /// The dedicated capture button on the glasses.
    case captureButton

    /// The dedicated action button on the glasses.
    case actionButton

    /// Neural Band pinch-and-drag input.
    case neuralBandDrag

    /// The source could not be determined.
    case unknown

    /// Returns a Boolean value indicating whether two values are equal.
    ///
    /// Equality is the inverse of inequality. For any values `a` and `b`,
    /// `a == b` implies that `a != b` is `false`.
    ///
    /// - Parameters:
    ///   - lhs: A value to compare.
    ///   - rhs: Another value to compare.
    public static func == (a: MWDATMockDevice.InputSource, b: MWDATMockDevice.InputSource) -> Bool

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

extension InputSource : Hashable {
}

extension InputSource : BitwiseCopyable {
}

/// A suite for mocking photo capture from the glasses camera.
///
/// This controls the photo file that the mock device returns when the SDK requests a capture. The
/// image is delivered and correlated with its capture metadata exactly as a real device would, so
/// your capture, progress, and error handling are exercised end to end.
///
/// @Unpublishable
public protocol MockCameraCaptureKit : Sendable {

    /// Set the image file to return when a photo capture is triggered.
    ///
    /// - Parameter fileURL: URL of the file containing the image (JPEG or HEIC).
    func setCapturedPhoto(fileURL: URL)

    /// Simulate a capture failure on the next capture attempt.
    ///
    /// When this flag is set, the next capture responds with an error instead of delivering an image.
    /// The flag resets after one failure.
    func simulateCaptureFailure()
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
    func setCameraFeed(cameraFacing: MWDATMockDevice.CameraFacing)

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

    /// Sets the simulated battery charge level (0...100), or `nil` for unknown/empty. Drives the
    /// device state observed via `Device.batteryLevel` / `Device.addListener`.
    func setBatteryLevel(_ level: Int?)

    /// Sets the simulated charging state.
    func setChargingState(_ state: MWDATCore.ChargingState)

    /// Sets the simulated thermal level.
    func setThermalLevel(_ level: MWDATCore.ThermalLevel)
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
public enum MockDeviceKitError : MWDATCore.DatError, Equatable {

    /// MockDeviceKit is not enabled. Call ``MockDeviceKitInterface/enable(config:)`` first.
    case notEnabled

    /// The requested test-server configuration is unavailable.
    case testServerUnavailable

    /// A human-readable description of the error for logging and display.
    public var description: String { get }

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
    ///
    /// Fire-and-forget: transport teardown continues on a background stream I/O thread
    /// after this returns. In Swift concurrency contexts prefer the `async` overload,
    /// which suspends until teardown is initiated and each link torn down, so a
    /// subsequent ``enable(config:)`` gets a deterministic ordering. This synchronous
    /// form exists for non-async callers such as Objective-C and `deinit`.
    func disable()

    /// Disables MockDeviceKit and suspends until every mock device's teardown has been
    /// initiated and its link torn down — services unregistered, in-flight work
    /// cancelled, and the fake app manager stopped — before returning. Prefer this over
    /// the synchronous overload in async code: it gives the next ``enable(config:)`` a
    /// deterministic teardown ordering instead of racing fire-and-forget cleanup, a
    /// common source of flakiness when cycling enable/disable. Note the underlying
    /// stream I/O may still be closing on its background thread when this returns.
    func disable() async

    /// Pairs a simulated glasses device of the specified model.
    ///
    /// - Parameter model: The glasses model to simulate.
    /// - Returns: A mock glasses instance.
    /// - Throws: ``MockDeviceKitError/notEnabled`` if MockDeviceKit has not been enabled.
    func pairGlasses(model: MWDATMockDevice.GlassesModel) throws(MWDATMockDevice.MockDeviceKitError) -> any MWDATMockDevice.MockGlasses

    /// Unpairs a simulated device.
    /// - Parameter device: The mock device to unpair.
    ///
    /// Fire-and-forget: the device's transport teardown continues asynchronously. In
    /// async code prefer the `async` overload, which awaits link teardown before returning.
    func unpairDevice(_ device: any MWDATMockDevice.MockDevice)

    /// Unpairs a simulated device and suspends until its teardown has been initiated and
    /// the link torn down. Prefer this over the synchronous overload in async code to
    /// give a subsequent re-pair a deterministic ordering rather than racing teardown.
    /// - Parameter device: The mock device to unpair.
    func unpairDevice(_ device: any MWDATMockDevice.MockDevice) async

    /// The list of all currently paired mock devices.
    var pairedDevices: [any MWDATMockDevice.MockDevice] { get }

    /// Interface for configuring mock permission behavior.
    var permissions: any MWDATMockDevice.MockPermissions { get }

    /// Starts a loopback-only test server on an available system-assigned port.
    /// - Parameter portFilePath: Optional path to a file where the server port will be written.
    /// - Returns: The port number the server is listening on.
    func startTestServer(portFilePath: String?) async throws -> UInt16

    /// Starts a loopback-only test server for mock device communication.
    /// - Parameters:
    ///   - port: Requested loopback port. Port `0` requests an available system-assigned port.
    ///   - portFilePath: Optional path to a file where the server port will be written.
    /// - Returns: The port number the server is listening on.
    func startTestServer(port: UInt16, portFilePath: String?) async throws -> UInt16

    /// Stops the running test server.
    func stopTestServer() async
}

extension MockDeviceKitInterface {

    public func enable()

    /// Starts a loopback-only test server for mock device communication.
    /// - Parameters:
    ///   - port: Requested loopback port. Port `0` requests an available system-assigned port.
    ///   - portFilePath: Optional path to a file where the server port will be written.
    /// - Returns: The port number the server is listening on.
    public func startTestServer(port: UInt16, portFilePath: String?) async throws -> UInt16

    /// Starts the test server on a requested loopback port or an available port when omitted.
    public func startTestServer(port: UInt16 = 0) async throws -> UInt16
}

/// Captures and interacts with display content sent to simulated display glasses.
public protocol MockDisplayKit : Sendable {

    /// Sends a display click through the same DWA event path used by real glasses.
    /// - Returns: Whether the click was delivered to an active DISPLAY capability.
    @discardableResult
    func sendClick(identifier: String) -> Bool

    /// Creates a locally rendered preview of the captured display content.
    ///
    /// The view observes content while attached to a window. Removing it from its superview disposes
    /// its WebView, so create a new preview view instead of reattaching the removed instance.
    @MainActor func createPreviewView() -> UIView
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

    var camera: any MWDATMockDevice.MockCameraKit { get }

    var captouch: any MWDATMockDevice.MockCaptouchKit { get }

    /// Configures standalone photo capture behavior for the simulated glasses.
    ///
    /// @Unpublishable
    var cameraCapture: any MWDATMockDevice.MockCameraCaptureKit { get }

    /// Injects synthetic Speech capability events.
    ///
    /// @Unpublishable
    var speech: any MWDATMockDevice.MockSpeechKit { get }

    /// Injects deterministic Motion samples.
    ///
    /// @Unpublishable
    var motion: any MWDATMockDevice.MockMotionKit { get }

    /// Injects synthetic Inputs capability events.
    ///
    /// @Unpublishable
    var input: any MWDATMockDevice.MockInputKit { get }

    /// Captures display payloads and injects display interactions.
    var display: any MWDATMockDevice.MockDisplayKit { get }

    /// Injects simulated Hey Meta voice invocations.
    var voiceInvocation: any MWDATMockDevice.MockVoiceInvocationKit { get }
}

/// Injects synthetic input interactions into a connected app during testing.
///
/// Each method delivers one typed input event to the connected app over the same channel a real
/// device uses, so the app cannot tell the event is synthetic. Events are delivered only while the
/// app has an active input session streaming, and only when their source matches what that session
/// requested; calls made at any other time are dropped.
///
/// Access an instance from ``MockGlassesServices/input``.
///
/// ```swift
/// let glasses = try mockDeviceKit.pairGlasses(model: .raybanMeta)
/// // ...the app under test starts its input session...
/// glasses.services.input.navDown()
/// glasses.services.input.select()
/// glasses.services.input.capture(pressType: .shortPress)
/// ```
///
/// @Unpublishable
public protocol MockInputKit : Sendable {

    /// Injects an upward navigation event.
    ///
    /// - Parameter source: The surface the event should appear to come from.
    func navUp(source: MWDATMockDevice.InputSource)

    /// Injects a downward navigation event.
    ///
    /// - Parameter source: The surface the event should appear to come from.
    func navDown(source: MWDATMockDevice.InputSource)

    /// Injects a leftward navigation event.
    ///
    /// - Parameter source: The surface the event should appear to come from.
    func navLeft(source: MWDATMockDevice.InputSource)

    /// Injects a rightward navigation event.
    ///
    /// - Parameter source: The surface the event should appear to come from.
    func navRight(source: MWDATMockDevice.InputSource)

    /// Injects a select / confirm event.
    ///
    /// - Parameter source: The surface the event should appear to come from.
    func select(source: MWDATMockDevice.InputSource)

    /// Injects a back / dismiss event.
    ///
    /// - Parameter source: The surface the event should appear to come from.
    func back(source: MWDATMockDevice.InputSource)

    /// Injects a capture-button press resolved to the given press type. The event's source is always
    /// the capture button.
    ///
    /// - Parameter pressType: The capture-button gesture to simulate (short press, hold, or double
    ///   press).
    func capture(pressType: MWDATMockDevice.CapturePressType)

    /// Injects a physical button press. The event's source is always the corresponding button.
    ///
    /// - Parameter type: Which physical button was pressed.
    func button(type: MWDATMockDevice.ButtonType)

    /// Injects one sample of a continuous drag stream. The event's source is always the Neural Band.
    ///
    /// Deliver a full drag by calling this with ``DragAction/down``, then any number of
    /// ``DragAction/move`` samples, then ``DragAction/up``.
    ///
    /// - Parameters:
    ///   - action: The phase of the drag this sample represents.
    ///   - x: The absolute x position of this sample.
    ///   - y: The absolute y position of this sample.
    ///   - dx: The change in x since the previous sample.
    ///   - dy: The change in y since the previous sample.
    func drag(action: MWDATMockDevice.DragAction, x: Float, y: Float, dx: Float, dy: Float)
}

extension MockInputKit {

    /// Injects an upward navigation event from the captouch surface.
    public func navUp()

    /// Injects a downward navigation event from the captouch surface.
    public func navDown()

    /// Injects a leftward navigation event from the captouch surface.
    public func navLeft()

    /// Injects a rightward navigation event from the captouch surface.
    public func navRight()

    /// Injects a select / confirm event from the captouch surface.
    public func select()

    /// Injects a back / dismiss event from the captouch surface.
    public func back()

    /// Injects a press of the action button.
    public func button()
}

/// Mocks the on-glasses Motion / IMU capability for a deterministic IMU stream without glasses.
///
/// Keep in sync with `ObjC_MockMotionKit`.
///
/// @Unpublishable
public protocol MockMotionKit : Sendable {

    var isStreaming: Bool { get }

    /// Feed a CSV recording for deterministic replay. Columns, in order: `timestampNs,accelX,accelY,accelZ,gyroX,gyroY,gyroZ,magX,magY,magZ,orientationW,orientationX,orientationY,orientationZ` (units: accel m/s², gyro rad/s, mag µT).
    func setMotionFeed(fileURL: URL)

    /// Feed an in-memory recording for deterministic replay.
    func setMotionFeed(_ samples: [MWDATMockDevice.MotionSample])
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

/// Scripted source for the mock on-glasses Speech/ASR capability; `simulate*` events are delivered only while ``isListening``.
///
/// @Unpublishable
public protocol MockSpeechKit : Sendable {

    var isListening: Bool { get }

    /// Only allowed while not ``isListening``; ignored during an active session.
    func setTranscriptionSource(_ source: MWDATMockDevice.MockSpeechSource)

    /// - Parameter confidence: in `[0, 1]`.
    func simulateTranscription(text: String, isFinal: Bool, confidence: Float)

    /// Carries the raw on-wire error code, not the consumer-facing `SpeechError`.
    /// - Parameter errorCode: an `android.speech.SpeechRecognizer` error code.
    func simulateError(errorCode: Int32, message: String)

    func simulateCompletion()

    /// Defaults to `en_US`. No effect on an in-flight session.
    func setLocale(_ locale: String)

    /// Latest ``MockSpeechSource/liveDeviceAsr`` diagnostic; surfaced here NOT as a wire `SpeechError` (which would end the session and disable the injected fallback).
    var liveSourceDiagnostic: String? { get }

    var liveSourceDiagnosticPublisher: any MWDATCore.Announcer<String?> { get }
}

extension MockSpeechKit {

    /// Delivers `result` during an active session; otherwise ignored.
    /// Use this overload to replay a captured result or pass a fixture without decomposing it.
    /// All fields are forwarded unchanged, including the `-1` unavailable confidence sentinel.
    public func simulateTranscription(_ result: MWDATMockDevice.TranscriptionResult)

    /// Only allowed while not ``isListening``; ignored during an active session.
    public func setTranscriptionSource(_ source: MWDATMockDevice.MockSpeechSource)

    /// Latest ``MockSpeechSource/liveDeviceAsr`` diagnostic; surfaced here NOT as a wire `SpeechError` (which would end the session and disable the injected fallback).
    public var liveSourceDiagnostic: String? { get }

    public var liveSourceDiagnosticPublisher: any MWDATCore.Announcer<String?> { get }
}

/// Selects where a mock Speech session's transcriptions come from.
///
/// @Unpublishable
public enum MockSpeechSource : Sendable {

    /// Deterministic events from `MockSpeechKit.simulate*` calls (default).
    case injected

    /// Host mic + platform `SFSpeechRecognizer`; requires microphone + Speech Recognition permission.
    case liveDeviceAsr

    /// Returns a Boolean value indicating whether two values are equal.
    ///
    /// Equality is the inverse of inequality. For any values `a` and `b`,
    /// `a == b` implies that `a != b` is `false`.
    ///
    /// - Parameters:
    ///   - lhs: A value to compare.
    ///   - rhs: Another value to compare.
    public static func == (a: MWDATMockDevice.MockSpeechSource, b: MWDATMockDevice.MockSpeechSource) -> Bool

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

extension MockSpeechSource : Equatable {
}

extension MockSpeechSource : Hashable {
}

/// Protocol for simulating Voice Invocation capabilities on a mock device.
///
/// This allows sending simulated Voice Invocation messages to connected clients, enabling
/// end-to-end testing of Voice Invocation flows using MockDeviceKit.
public protocol MockVoiceInvocationKit : Sendable {

    /// Sends a launch app action to all connected clients.
    ///
    /// This simulates the device triggering a "start_partner_app" action, which tells the connected
    /// app that the user has invoked a voice command to launch the partner app.
    ///
    /// - Returns: The request ID of the sent action, or nil if no clients are connected.
    func sendLaunchAppAction() -> String?

    /// Sends a deliberately malformed / incomplete action to all connected clients.
    ///
    /// This simulates the device sending an invalid Voice Invocation payload, allowing tests to
    /// verify that the SDK surfaces the malformed message on its error stream without delivering a
    /// bogus invocation.
    ///
    /// - Returns: The request ID of the sent action, or nil if no clients are connected.
    func sendIncompleteAction() -> String?

    /// Returns true if there are connected clients.
    var hasConnectedClients: Bool { get }
}

/// A single motion measurement from the connected wearable.
///
/// @Unpublishable
public struct MotionSample : Sendable, Equatable {

    /// Sensor timestamp in nanoseconds (monotonic, CLOCK_BOOTTIME on the device).
    public let timestampNs: Int64

    /// Accelerometer reading in m/s², or `nil` if unavailable.
    public let accelerometer: MWDATMockDevice.Vector3?

    /// Gyroscope reading in rad/s, or `nil` if unavailable.
    public let gyroscope: MWDATMockDevice.Vector3?

    /// Magnetometer reading in microtesla (µT), or `nil` if unavailable.
    public let magnetometer: MWDATMockDevice.Vector3?

    /// Device orientation as a quaternion, or `nil` if unavailable.
    public let orientation: MWDATMockDevice.Quaternion?

    /// The origin of this sample (glasses vs Neural Band). Defaults to ``MotionSource/unknown``.
    public let source: MWDATMockDevice.MotionSource

    /// Creates a motion sample.
    ///
    /// - Parameters:
    ///   - timestampNs: Sensor timestamp in nanoseconds (monotonic, `CLOCK_BOOTTIME` on the device).
    ///   - accelerometer: Accelerometer reading in m/s², or `nil` if unavailable.
    ///   - gyroscope: Gyroscope reading in rad/s, or `nil` if unavailable.
    ///   - magnetometer: Magnetometer reading in microtesla (µT), or `nil` if unavailable.
    ///   - orientation: Device orientation as a quaternion, or `nil` if unavailable.
    ///   - source: The origin of this sample. Defaults to ``MotionSource/unknown``.
    public init(timestampNs: Int64, accelerometer: MWDATMockDevice.Vector3? = nil, gyroscope: MWDATMockDevice.Vector3? = nil, magnetometer: MWDATMockDevice.Vector3? = nil, orientation: MWDATMockDevice.Quaternion? = nil, source: MWDATMockDevice.MotionSource = .unknown)

    /// Returns a Boolean value indicating whether two values are equal.
    ///
    /// Equality is the inverse of inequality. For any values `a` and `b`,
    /// `a == b` implies that `a != b` is `false`.
    ///
    /// - Parameters:
    ///   - lhs: A value to compare.
    ///   - rhs: Another value to compare.
    public static func == (a: MWDATMockDevice.MotionSample, b: MWDATMockDevice.MotionSample) -> Bool
}

/// The device that produced a ``MotionSample``.
///
/// @Unpublishable
@frozen public enum MotionSource : Sendable, Equatable {

    /// The sensors on the glasses.
    case glasses

    /// Neural Band sensors.
    case neuralBand

    /// The source could not be determined.
    case unknown

    /// Returns a Boolean value indicating whether two values are equal.
    ///
    /// Equality is the inverse of inequality. For any values `a` and `b`,
    /// `a == b` implies that `a != b` is `false`.
    ///
    /// - Parameters:
    ///   - lhs: A value to compare.
    ///   - rhs: Another value to compare.
    public static func == (a: MWDATMockDevice.MotionSource, b: MWDATMockDevice.MotionSource) -> Bool

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

extension MotionSource : Hashable {
}

extension MotionSource : BitwiseCopyable {
}

/// A directional navigation gesture.
///
/// @Unpublishable
@frozen public enum NavDirection : Sendable, Equatable {

    /// An upward navigation gesture.
    case up

    /// A downward navigation gesture.
    case down

    /// A leftward navigation gesture.
    case left

    /// A rightward navigation gesture.
    case right

    /// Returns a Boolean value indicating whether two values are equal.
    ///
    /// Equality is the inverse of inequality. For any values `a` and `b`,
    /// `a == b` implies that `a != b` is `false`.
    ///
    /// - Parameters:
    ///   - lhs: A value to compare.
    ///   - rhs: Another value to compare.
    public static func == (a: MWDATMockDevice.NavDirection, b: MWDATMockDevice.NavDirection) -> Bool

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

extension NavDirection : Hashable {
}

extension NavDirection : BitwiseCopyable {
}

/// A named hardware button.
///
/// @Unpublishable
@objc(MWDATButtonType) @frozen public enum ObjC_ButtonType : Int, Sendable {

    /// The primary action button.
    case action

    /// Not a button event — set when the enclosing ``MWDATInputEvent/type`` is not `button`.
    case unknown

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
    public init?(rawValue: Int)

    /// The raw type that can be used to represent all values of the conforming
    /// type.
    ///
    /// Every distinct value of the conforming type has a corresponding unique
    /// value of the `RawValue` type, but there may be values of the `RawValue`
    /// type that don't have a corresponding value of the conforming type.
    public typealias RawValue = Int

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
    public var rawValue: Int { get }
}

extension ObjC_ButtonType : Equatable {
}

extension ObjC_ButtonType : Hashable {
}

extension ObjC_ButtonType : RawRepresentable {
}

extension ObjC_ButtonType : BitwiseCopyable {
}

/// The kind of capture interaction.
///
/// @Unpublishable
@objc(MWDATCapturePressType) @frozen public enum ObjC_CapturePressType : Int, Sendable {

    /// A single short press of the capture button. Defaults to capturing a photo.
    case shortPress

    /// A press and hold of the capture button. Defaults to starting a video recording.
    case hold

    /// A double press of the capture button. Defaults to stopping an in-progress video recording.
    case doublePress

    /// Not a capture event — set when the enclosing ``MWDATInputEvent/type`` is not `capture`.
    case unknown

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
    public init?(rawValue: Int)

    /// The raw type that can be used to represent all values of the conforming
    /// type.
    ///
    /// Every distinct value of the conforming type has a corresponding unique
    /// value of the `RawValue` type, but there may be values of the `RawValue`
    /// type that don't have a corresponding value of the conforming type.
    public typealias RawValue = Int

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
    public var rawValue: Int { get }
}

extension ObjC_CapturePressType : Equatable {
}

extension ObjC_CapturePressType : Hashable {
}

extension ObjC_CapturePressType : RawRepresentable {
}

extension ObjC_CapturePressType : BitwiseCopyable {
}

/// The phase of a drag interaction.
///
/// @Unpublishable
@objc(MWDATDragAction) @frozen public enum ObjC_DragAction : Int, Sendable {

    /// The pointer went down, beginning the drag.
    case down

    /// The pointer moved while down.
    case move

    /// The pointer went up, ending the drag.
    case up

    /// Not a drag event — set when the enclosing ``MWDATInputEvent/type`` is not `drag`.
    case unknown

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
    public init?(rawValue: Int)

    /// The raw type that can be used to represent all values of the conforming
    /// type.
    ///
    /// Every distinct value of the conforming type has a corresponding unique
    /// value of the `RawValue` type, but there may be values of the `RawValue`
    /// type that don't have a corresponding value of the conforming type.
    public typealias RawValue = Int

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
    public var rawValue: Int { get }
}

extension ObjC_DragAction : Equatable {
}

extension ObjC_DragAction : Hashable {
}

extension ObjC_DragAction : RawRepresentable {
}

extension ObjC_DragAction : BitwiseCopyable {
}

/// The device surface that produced an input event.
///
/// @Unpublishable
@objc(MWDATInputSource) @frozen public enum ObjC_InputSource : Int, Sendable, CaseIterable {

    /// The capacitive touchpad on the glasses.
    case captouch = 0

    /// Neural Band discrete gesture input.
    case neuralBand = 1

    /// The dedicated capture button on the glasses.
    case captureButton = 2

    /// The dedicated action button on the glasses.
    case actionButton = 3

    /// Neural Band pinch-and-drag input.
    case neuralBandDrag = 4

    /// The source could not be determined.
    case unknown = 5

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
    public init?(rawValue: Int)

    /// A type that can represent a collection of all values of this type.
    public typealias AllCases = [MWDATMockDevice.ObjC_InputSource]

    /// The raw type that can be used to represent all values of the conforming
    /// type.
    ///
    /// Every distinct value of the conforming type has a corresponding unique
    /// value of the `RawValue` type, but there may be values of the `RawValue`
    /// type that don't have a corresponding value of the conforming type.
    public typealias RawValue = Int

    /// A collection of all values of this type.
    nonisolated public static var allCases: [MWDATMockDevice.ObjC_InputSource] { get }

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
    public var rawValue: Int { get }
}

extension ObjC_InputSource : Equatable {
}

extension ObjC_InputSource : Hashable {
}

extension ObjC_InputSource : RawRepresentable {
}

extension ObjC_InputSource : BitwiseCopyable {
}

/// Objective-C bridge for configuring standalone photo capture on simulated glasses.
///
/// @Unpublishable
@objc(MockCameraCaptureKit) final public class ObjC_MockCameraCaptureKit : NSObject, Sendable {

    /// Set the image file to return when a photo capture is triggered.
    /// - Parameter fileURL: URL of the file containing the image (JPEG or HEIC).
    @objc final public func setCapturedPhoto(fileURL: URL)

    /// Simulate a capture failure on the next capture attempt.
    @objc final public func simulateCaptureFailure()

    @objc deinit
}

@objc(MockCameraKit) final public class ObjC_MockCameraKit : NSObject, Sendable {

    /// Set camera feed from a video file. Supported codecs: h.265
    /// - Parameter fileURL: URL of the file containing video stream
    @objc final public func setCameraFeed(fileURL: URL)

    /// Set the camera source to stream live from the phone's camera.
    /// - Parameter cameraFacing: 0 for front camera, 1 for back camera.
    @objc final public func setCameraFeed(cameraFacing: Int)

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

@objc(MockDisplayKit) final public class ObjC_MockDisplayKit : NSObject, Sendable {

    /// Sends a display click for the supplied element identifier.
    /// - Returns: Whether the click was delivered to an active DISPLAY capability.
    @objc final public func sendClick(identifier: String) -> Bool

    /// Creates a locally rendered preview of the captured display content. The returned view is
    /// single-use; create a new view after removing it from its superview.
    @MainActor @objc final public func createPreviewView() -> UIView

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

    /// Configures standalone photo capture behavior for the simulated glasses.
    ///
    /// @Unpublishable
    @objc final public let cameraCapture: MWDATMockDevice.ObjC_MockCameraCaptureKit

    /// Injects synthetic Speech capability events.
    ///
    /// @Unpublishable
    @objc final public let speech: MWDATMockDevice.ObjC_MockSpeechKit

    /// Injects deterministic Motion samples.
    ///
    /// @Unpublishable
    @objc final public let motion: MWDATMockDevice.ObjC_MockMotionKit

    /// Injects synthetic Inputs capability events.
    ///
    /// @Unpublishable
    @objc final public let input: MWDATMockDevice.ObjC_MockInputKit

    @objc final public let display: MWDATMockDevice.ObjC_MockDisplayKit

    @objc final public let voiceInvocation: MWDATMockDevice.ObjC_MockVoiceInvocationKit

    @objc deinit
}

/// Injects synthetic input interactions into a connected app during testing. Objective-C mirror of
/// ``MockInputKit``.
///
/// @Unpublishable
@objc(MockInputKit) final public class ObjC_MockInputKit : NSObject, Sendable {

    /// Injects an upward navigation event from the given source.
    @objc final public func navUp(source: MWDATMockDevice.ObjC_InputSource)

    /// Injects a downward navigation event from the given source.
    @objc final public func navDown(source: MWDATMockDevice.ObjC_InputSource)

    /// Injects a leftward navigation event from the given source.
    @objc final public func navLeft(source: MWDATMockDevice.ObjC_InputSource)

    /// Injects a rightward navigation event from the given source.
    @objc final public func navRight(source: MWDATMockDevice.ObjC_InputSource)

    /// Injects a select / confirm event from the given source.
    @objc final public func select(source: MWDATMockDevice.ObjC_InputSource)

    /// Injects a back / dismiss event from the given source.
    @objc final public func back(source: MWDATMockDevice.ObjC_InputSource)

    /// Injects a capture-button press resolved to the given press type.
    @objc final public func capture(pressType: MWDATMockDevice.ObjC_CapturePressType)

    /// Injects a physical button press.
    @objc final public func button(type: MWDATMockDevice.ObjC_ButtonType)

    /// Injects one sample of a continuous Neural Band drag stream.
    @objc final public func drag(action: MWDATMockDevice.ObjC_DragAction, x: Float, y: Float, dx: Float, dy: Float)

    @objc deinit
}

/// Keep in sync with the `MockMotionKit` Swift protocol.
///
/// @Unpublishable
@objc(MockMotionKit) final public class ObjC_MockMotionKit : NSObject, Sendable {

    @objc final public var isStreaming: Bool { get }

    /// Feed a CSV recording for deterministic replay; the in-memory `[MotionSample]` overload is Swift-only.
    @objc final public func setMotionFeed(fileURL: URL)

    @objc deinit
}

/// Controls synthetic Speech events for a mock device.
///
/// @Unpublishable
@objc(MockSpeechKit) final public class ObjC_MockSpeechKit : NSObject, Sendable {

    @objc final public var isListening: Bool { get }

    /// `MockSpeechSource` is a Swift enum that cannot cross to ObjC, so it is exposed as a Bool.
    /// Only takes effect while not ``isListening``.
    @objc final public func setLiveDeviceAsrEnabled(_ enabled: Bool)

    @objc final public func simulateTranscription(text: String, isFinal: Bool, confidence: Float)

    @objc final public func simulateError(errorCode: Int32, message: String)

    @objc final public func simulateCompletion()

    @objc final public func setLocale(_ locale: String)

    /// Snapshot only — the Swift `liveSourceDiagnosticPublisher` (`Announcer`) cannot cross to ObjC.
    @objc final public var liveSourceDiagnostic: String? { get }

    @objc deinit
}

@objc(MockVoiceInvocationKit) final public class ObjC_MockVoiceInvocationKit : NSObject, Sendable {

    /// Sends a launch app action to all connected clients.
    /// - Returns: The request ID of the sent action, or nil if no clients are connected.
    @objc final public func sendLaunchAppAction() -> String?

    /// Sends a deliberately malformed action to all connected clients.
    /// - Returns: The request ID of the sent action, or nil if no clients are connected.
    @objc final public func sendIncompleteAction() -> String?

    /// Returns true if there are connected clients.
    @objc final public var hasConnectedClients: Bool { get }

    @objc deinit
}

/// A rotation as a unit quaternion; `w` is the scalar component.
///
/// @Unpublishable
public struct Quaternion : Sendable, Equatable {

    /// The x component of the vector part.
    public let x: Float

    /// The y component of the vector part.
    public let y: Float

    /// The z component of the vector part.
    public let z: Float

    /// The scalar (real) component.
    public let w: Float

    /// Creates a quaternion from its components.
    ///
    /// - Parameters:
    ///   - x: The x component of the vector part.
    ///   - y: The y component of the vector part.
    ///   - z: The z component of the vector part.
    ///   - w: The scalar (real) component.
    public init(x: Float, y: Float, z: Float, w: Float)

    /// Creates a quaternion from a SIMD quaternion.
    ///
    /// - Parameter simd: The SIMD quaternion to convert.
    public init(_ simd: simd_quatf)

    /// This rotation as a SIMD quaternion.
    public var simd: simd_quatf { get }

    /// Returns a Boolean value indicating whether two values are equal.
    ///
    /// Equality is the inverse of inequality. For any values `a` and `b`,
    /// `a == b` implies that `a != b` is `false`.
    ///
    /// - Parameters:
    ///   - lhs: A value to compare.
    ///   - rhs: Another value to compare.
    public static func == (a: MWDATMockDevice.Quaternion, b: MWDATMockDevice.Quaternion) -> Bool
}

/// The result of an on-device speech recognition event.
///
/// Each ``TranscriptionResult`` represents either a partial (in-progress) or
/// final transcription from the glasses' ASR engine.
///
/// @Unpublishable
public struct TranscriptionResult : Sendable, Equatable {

    /// The recognized text (partial or final).
    public let text: String

    /// Whether this is the final result for the current utterance.
    /// When `true`, no further updates will arrive for this segment.
    public let isFinal: Bool

    /// Confidence score in the range `[0.0, 1.0]`, or `-1.0` if unavailable.
    public let confidence: Float

    /// Creates a transcription result.
    ///
    /// - Parameters:
    ///   - text: The recognized text (partial or final).
    ///   - isFinal: Whether this is the final result for the current utterance.
    ///   - confidence: Confidence score in `[0.0, 1.0]`, or `-1.0` if unavailable.
    public init(text: String, isFinal: Bool, confidence: Float)

    /// Returns a Boolean value indicating whether two values are equal.
    ///
    /// Equality is the inverse of inequality. For any values `a` and `b`,
    /// `a == b` implies that `a != b` is `false`.
    ///
    /// - Parameters:
    ///   - lhs: A value to compare.
    ///   - rhs: Another value to compare.
    public static func == (a: MWDATMockDevice.TranscriptionResult, b: MWDATMockDevice.TranscriptionResult) -> Bool
}

/// A 3D vector of sensor data.
///
/// @Unpublishable
public struct Vector3 : Sendable, Equatable {

    /// The x component.
    public let x: Float

    /// The y component.
    public let y: Float

    /// The z component.
    public let z: Float

    /// Creates a vector from its components.
    ///
    /// - Parameters:
    ///   - x: The x component.
    ///   - y: The y component.
    ///   - z: The z component.
    public init(x: Float, y: Float, z: Float)

    /// Creates a vector from a SIMD three-element vector.
    ///
    /// - Parameter simd: The SIMD vector whose components initialize this value.
    public init(_ simd: SIMD3<Float>)

    /// This vector as a SIMD three-element vector.
    public var simd: SIMD3<Float> { get }

    /// Returns a Boolean value indicating whether two values are equal.
    ///
    /// Equality is the inverse of inequality. For any values `a` and `b`,
    /// `a == b` implies that `a != b` is `false`.
    ///
    /// - Parameters:
    ///   - lhs: A value to compare.
    ///   - rhs: Another value to compare.
    public static func == (a: MWDATMockDevice.Vector3, b: MWDATMockDevice.Vector3) -> Bool
}

/// Z-axis accelerometer reading for an at-rest, face-up device (one g, m/s²).
///
/// @Unpublishable
public let mockMotionGravityMetersPerSecondSquared: Float

/// Z-axis accelerometer reading for an at-rest, face-up device (one g, m/s²).
///
/// @Unpublishable
public var mockMotionGravityMetersPerSecondSquared: Float

