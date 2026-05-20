import CoreBluetooth
import CryptoKit
import Darwin
import Foundation
import MachO
import UIKit

final public class Analytics : MWDATCore.AnalyticsProtocol, Sendable {

    /// Shared instance of the Analytics class.
    public static let shared: MWDATCore.Analytics

    /// Logs an analytics event.
    /// - Parameter event: The event to log.
    final public func log(event: any MWDATCore.AnalyticsEvent)

    /// Static convenience method to log an analytics event.
    /// - Parameter event: The event to log.
    public static func log(event: any MWDATCore.AnalyticsEvent)

    final public func configure(with configuration: MWDATCore.Configuration, runtimeConfig: MWDATCore.AnalyticsRuntimeConfig)

    @objc deinit
}

extension Analytics {

    /// Start a QPL marker
    final public func markerStart(markerId: Int32, instanceKey: Int32)

    /// Annotate a QPL marker with any supported value type
    final public func markerAnnotate<T>(markerId: Int32, instanceKey: Int32, key: String, value: T) where T : MWDATCore.QPLAnnotatable

    /// End a QPL marker with an action ID
    final public func markerEnd(markerId: Int32, instanceKey: Int32, actionId: Int16)

    /// Add a point to a tracked QPL marker
    final public func markerPoint(markerId: Int32, instanceKey: Int32, name: String, level: MWDATCore.QPLLogLevel)
}

/// Configuration for analytics in DAT
public struct AnalyticsConfiguration : Sendable {

    /// Whether analytics are enabled.
    public let enabled: Bool

    /// The endpoint URL for analytics data.
    public let endpointUrl: String
}

/// Protocol defining the structure of an analytics event.
public protocol AnalyticsEvent : Sendable {

    /// The name of the event.
    var name: String { get }

    /// The data associated with the event.
    var data: [String : Any] { get }
}

/// Protocol of the logger.
public protocol AnalyticsProtocol : Sendable {

    /// Logs an analytics event.
    /// - Parameter event: The event to log.
    func log(event: any MWDATCore.AnalyticsEvent)

    /// Start a QPL marker
    func markerStart(markerId: Int32, instanceKey: Int32)

    /// Annotate a QPL marker with any supported value type
    func markerAnnotate<T>(markerId: Int32, instanceKey: Int32, key: String, value: T) where T : MWDATCore.QPLAnnotatable

    /// End a QPL marker with an action ID
    func markerEnd(markerId: Int32, instanceKey: Int32, actionId: Int16)

    /// Add a point to a tracked QPL marker
    func markerPoint(markerId: Int32, instanceKey: Int32, name: String, level: MWDATCore.QPLLogLevel)
}

extension AnalyticsProtocol {

    /// Start a QPL marker
    /// - Parameters:
    ///   - markerId: Unique marker identifier
    ///   - instanceKey: Unique instance key for this marker start/end pair
    public func markerStart(markerId: Int32, instanceKey: Int32)

    /// Annotate a QPL marker with any supported value type
    /// - Parameters:
    ///   - markerId: Marker identifier
    ///   - instanceKey: Instance key for this marker
    ///   - key: Annotation key
    ///   - value: Annotation value (String, Int, Int64, Double, Bool, or nil)
    public func markerAnnotate<T>(markerId: Int32, instanceKey: Int32, key: String, value: T) where T : MWDATCore.QPLAnnotatable

    /// End a QPL marker with an action ID
    /// - Parameters:
    ///   - markerId: Marker identifier
    ///   - instanceKey: Instance key for this marker
    ///   - actionId: Action ID
    public func markerEnd(markerId: Int32, instanceKey: Int32, actionId: Int16)

    /// Add a point to a tracked QPL marker
    /// - Parameters:
    ///   - markerId: Marker identifier
    ///   - instanceKey: Instance key for this marker
    ///   - name: Point name
    ///   - level: Log level for this point
    public func markerPoint(markerId: Int32, instanceKey: Int32, name: String, level: MWDATCore.QPLLogLevel)
}

public struct AnalyticsRuntimeConfig : Sendable {

    public init(sessionUuid: String, sessionStartTime: Int64, publicKeyHash: String)
}

/// A protocol for objects that can announce events to registered listeners.
public protocol Announcer<T> {

    associatedtype T : Sendable

    /// Registers a listener for events of type T.
    /// - Parameter listener: The callback to execute when an event occurs.
    /// - Returns: A token that can be used to cancel the listener.
    func listen(_ listener: @escaping @Sendable (Self.T) -> Void) -> any MWDATCore.AnyListenerToken
}

/// A type-erased wrapper for any AsyncSequence with a specific Element type.
/// This allows working with different AsyncSequence implementations through a common interface.
public struct AnyAsyncSequence<Element> : AsyncSequence, Sendable {

    /// Creates a type-erased async sequence that wraps the provided sequence.
    /// - Parameter sequence: The async sequence to wrap.
    public init<S>(_ sequence: S) where Element == S.Element, S : Sendable, S : AsyncSequence

    /// Creates an iterator that iterates over the elements of the sequence.
    /// - Returns: A type-erased iterator over the elements of the sequence.
    public func makeAsyncIterator() -> MWDATCore.AnyAsyncSequence<Element>.AnyAsyncIterator

    /// A type-erased async iterator that wraps any iterator with the same Element type.
    public struct AnyAsyncIterator : AsyncIteratorProtocol {

        /// Advances to the next element and returns it, or nil if no next element exists.
        /// - Returns: The next element, if it exists; otherwise, nil.
        /// - Throws: Any error encountered while advancing to the next element.
        public mutating func next() async -> Element?

        /// The type of failure produced by iteration.
        @available(iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, macOS 15.0, *)
        public typealias __AsyncIteratorProtocol_Failure = Never
    }

    /// The type of asynchronous iterator that produces elements of this
    /// asynchronous sequence.
    public typealias AsyncIterator = MWDATCore.AnyAsyncSequence<Element>.AnyAsyncIterator

    /// The type of errors produced when iteration over the sequence fails.
    @available(iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, macOS 15.0, *)
    public typealias __AsyncSequence_Failure = Never
}

public protocol AnyChannel : Sendable {

    func close()

    func send(_ data: Data, messageType: UInt16) -> UInt16
}

public protocol AnyConnection : Sendable {

    func openChannel(serviceID: UInt16, onReceived: @escaping (UInt16, Data) -> Void, onError: @escaping (UInt16) -> Void, onClosed: @escaping () -> Void) -> any MWDATCore.AnyChannel
}

/// A token that can be used to cancel a listener subscription.
/// When the token is no longer referenced, the listener is automatically canceled.
public protocol AnyListenerToken : Sendable {

    /// Cancels the listener subscription asynchronously.
    func cancel() async
}

/// Configuration for logging in DAT.
public struct AppConfiguration : Sendable {

    /// The app's bundle identifier.
    public let bundleIdentifier: String

    /// The app's name.
    public let appName: String

    /// The app's version (e.g. 1.2.3).
    public let appVersion: String

    /// The app's build number (e.g. 7)
    public let buildNumber: String

    /// The MWDAT version.
    public let mwdatVersion: String

    /// The app's app link URL scheme.
    public let appLinkURLScheme: String?

    public let metaAppId: String?

    public let clientToken: String?

    public let teamID: String?
}

final public class AppManager : Sendable {

    final public let registrationManager: MWDATCore.RegistrationManager

    final public let deviceManager: any MWDATCore.DeviceManager

    final public let permissionsManager: MWDATCore.PermissionsManager

    final public let sessionManager: any MWDATCore.SessionManager

    final public func start()

    @objc deinit
}

extension AppManager {

    public static func withSharedLinkedAppManager(configuration: MWDATCore.Configuration, deviceManager: (any MWDATCore.DeviceManager)? = nil) throws -> MWDATCore.AppManager
}

/// Configuration for attestation in DAT
public struct AttestationConfiguration : Sendable {

    /// The endpoint URL for attestation data.
    public let endpointUrl: String

    /// The key rotation interval in days (how often to generate a new attestation key).
    /// Default: 90 days
    public let keyRotationIntervalInDays: Int

    /// Indicates whether all required configuration values are present for attestation.
    public let hasCompleteData: Bool
}

final public class AttestationManager {

    @objc deinit
}

extension AttestationManager : Sendable {
}

/// A device selector that automatically selects the best available device.
/// Selects the first connected device from the devices list, falling back to the first device if none are connected.
final public class AutoDeviceSelector : MWDATCore.DeviceSelector {

    /// The currently active device identifier.
    final public var activeDevice: MWDATCore.DeviceIdentifier? { get }

    /// Creates a stream of active device changes that updates whenever the device list changes.
    final public func activeDeviceStream() -> MWDATCore.AnyAsyncSequence<MWDATCore.DeviceIdentifier?>

    /// Creates an auto device selector that monitors the given wearables interface for device changes.
    /// - Parameters:
    ///   - wearables: The wearables interface to monitor for available devices.
    ///   - filter: An optional closure to apply additional filtering beyond connected and compatible.
    ///     Return `true` to include a device, `false` to exclude it.
    public init(wearables: any MWDATCore.WearablesInterface, filter: MWDATCore.DeviceFilter? = nil)

    @objc deinit
}

public enum BuildInfo {

    public static let version: String

    public static let releaseVersion: Int

    public static let hotfixVersion: Int

    public static let experimentationVersion: Int

    public static let betaVersion: Int

    public static let alphaVersion: Int
}

/// A protocol for capabilities that can be attached to a ``DeviceSession``.
///
/// Capabilities represent device features (e.g., streaming, display) that are managed
/// by a parent ``DeviceSession``. When the parent session stops, it cascades ``stop()``
/// to all attached capabilities.
///
/// `start()` is intentionally not part of this protocol because different capabilities
/// may have different start signatures. The protocol exists for ``DeviceSession``'s
/// cascading stop contract.
public protocol Capability : AnyObject, Sendable {

    /// The current state of this capability.
    var capabilityState: MWDATCore.CapabilityState { get }

    /// Stops the capability, tearing down its resources and detaching from the parent ``DeviceSession``.
    func stop() async
}

/// Represents the state of a capability attached to a ``DeviceSession``.
@frozen public enum CapabilityState : Sendable {

    /// The capability is active and usable.
    case active

    /// The capability has been stopped.
    case stopped

    /// Returns a Boolean value indicating whether two values are equal.
    ///
    /// Equality is the inverse of inequality. For any values `a` and `b`,
    /// `a == b` implies that `a != b` is `false`.
    ///
    /// - Parameters:
    ///   - lhs: A value to compare.
    ///   - rhs: Another value to compare.
    public static func == (a: MWDATCore.CapabilityState, b: MWDATCore.CapabilityState) -> Bool

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

extension CapabilityState : Equatable {
}

extension CapabilityState : Hashable {
}

extension CapabilityState : BitwiseCopyable {
}

/// Indicates the compatibility status between AI glasses and the Wearables Device Access Toolkit.
///
/// This status reflects whether the device version is compatible with the
/// currently installed Wearables Device Access Toolkit version, and whether any updates are required.
public enum Compatibility : CaseIterable, Sendable {

    /// Unknown compatibility status.
    ///
    /// Treat as incompatible. This typically occurs when the device is disconnected
    /// or the version is unavailable.
    case undefined

    /// Device is fully compatible with the current Wearables Device Access Toolkit version.
    ///
    /// All features are available and no updates are required.
    case compatible

    /// Device is outdated and requires an update.
    ///
    /// The device should be updated to the latest version to work properly
    /// with this Wearables Device Access Toolkit. Some features may be unavailable until the update is complete.
    case deviceUpdateRequired

    /// Wearables Device Access Toolkit version is outdated and requires an update.
    ///
    /// The app should be updated to a newer version to work with this device's
    /// version. Some features may be unavailable until the update is complete.
    case sdkUpdateRequired

    /// Provides a description of the compatibility status.
    public var displayString: String { get }

    /// Returns a Boolean value indicating whether two values are equal.
    ///
    /// Equality is the inverse of inequality. For any values `a` and `b`,
    /// `a == b` implies that `a != b` is `false`.
    ///
    /// - Parameters:
    ///   - lhs: A value to compare.
    ///   - rhs: Another value to compare.
    public static func == (a: MWDATCore.Compatibility, b: MWDATCore.Compatibility) -> Bool

    /// A type that can represent a collection of all values of this type.
    public typealias AllCases = [MWDATCore.Compatibility]

    /// A collection of all values of this type.
    nonisolated public static var allCases: [MWDATCore.Compatibility] { get }

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

extension Compatibility : Equatable {
}

extension Compatibility : Hashable {
}

/// Configuration for DAT.
public struct Configuration : Sendable {

    /// The app configuration.
    /// This object contains all the app's top-level configuration values.
    public let appConfiguration: MWDATCore.AppConfiguration

    /// The logging configuration.
    /// This object contains all the logging configuration values.
    public let loggingConfiguration: MWDATCore.LoggingConfiguration

    /// The analytics configuration.
    /// This object contains all the analytics configuration values.
    public let analyticsConfiguration: MWDATCore.AnalyticsConfiguration

    /// The attestation configuration.
    /// This object contains all the attestation configuration values.
    public let attestationConfiguration: MWDATCore.AttestationConfiguration

    /// Whether this app uses DAM (Device Access Manager) via DWA.
    /// Read from Info.plist under `MWDAT.DAMEnabled`. Defaults to `false`.
    public let usesDam: Bool

    /// Creates a new configuration object with the provided bundle.
    ///
    /// - Parameter bundle: The bundle to load configuration from.
    public init(bundle: Bundle) throws(MWDATCore.ConfigurationError)

    /// Creates a new configuration object with the provided info dictionary.
    ///
    /// - Parameter infoDictionary: A dictionary that mimics the structure of the Info.plist, containing configuration under the "MWDAT" key.
    public init(infoDictionary: [String : Any]) throws(MWDATCore.ConfigurationError)
}

public enum ConfigurationError : Error {

    case missingInfoDictionary

    case missingBundleIdentifier

    case missingAppName

    case missingAppVersion

    case missingBuildNumber

    /// Returns a Boolean value indicating whether two values are equal.
    ///
    /// Equality is the inverse of inequality. For any values `a` and `b`,
    /// `a == b` implies that `a != b` is `false`.
    ///
    /// - Parameters:
    ///   - lhs: A value to compare.
    ///   - rhs: Another value to compare.
    public static func == (a: MWDATCore.ConfigurationError, b: MWDATCore.ConfigurationError) -> Bool

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

extension ConfigurationError : Equatable {
}

extension ConfigurationError : Hashable {
}

/// Attestation validation status returned by the server
public enum DATAttestationStatus : String, Sendable {

    case passed

    case failed

    case skipped

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

    /// The raw type that can be used to represent all values of the conforming
    /// type.
    ///
    /// Every distinct value of the conforming type has a corresponding unique
    /// value of the `RawValue` type, but there may be values of the `RawValue`
    /// type that don't have a corresponding value of the conforming type.
    public typealias RawValue = String

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

extension DATAttestationStatus : Equatable {
}

extension DATAttestationStatus : Hashable {
}

extension DATAttestationStatus : RawRepresentable {
}

/// AI glasses accessible through the Wearables Device Access Toolkit.
final public class Device : Sendable {

    /// The unique identifier for this device.
    final public let identifier: MWDATCore.DeviceIdentifier

    /// The human-readable device name, or empty string if unavailable.
    final public var name: String { get }

    /// This UUID is persisted across app launches and used for Airship scope registration.
    /// Note: This differs from `identifier` which comes from the server manifest.
    final public var deviceUUID: UUID { get }

    /// Returns the device name if available, otherwise returns the device identifier.
    /// This provides a fallback for display purposes when the device name is not set.
    /// - Returns: The device name or identifier as a fallback.
    final public func nameOrId() -> String

    /// The current connection state of the device.
    final public var linkState: MWDATCore.LinkState { get }

    /// Adds a listener to receive notifications when the device's link state changes.
    /// - Parameter listener: The callback to execute when the link state changes.
    /// - Returns: A token that can be used to cancel the listener.
    final public func addLinkStateListener(_ listener: @escaping @Sendable (MWDATCore.LinkState) -> Void) -> any MWDATCore.AnyListenerToken

    /// Adds a listener to receive notifications when the device's compatibility changes.
    /// - Parameter listener: The callback to execute when the compatibility changes.
    /// - Returns: A token that can be used to cancel the listener.
    final public func addCompatibilityListener(_ listener: @escaping @Sendable (MWDATCore.Compatibility) -> Void) -> any MWDATCore.AnyListenerToken

    /// Returns the type of this device (e.g., Ray-Ban Meta).
    /// - Returns: The device type identifier.
    final public func deviceType() -> MWDATCore.DeviceType

    /// Returns true if the version of this device is compatible with the Wearables Device Access Toolkit.
    final public func compatibility() -> MWDATCore.Compatibility

    /// Returns whether this device has a built-in display.
    /// - Returns: `true` if the device type supports a display, `false` otherwise.
    final public func supportsDisplay() -> Bool

    @objc deinit
}

/// A closure that filters devices during auto-selection.
/// Return `true` to include the device, `false` to exclude it.
public typealias DeviceFilter = @Sendable (MWDATCore.Device) -> Bool

/// A unique identifier for a Meta Wearables device.
public typealias DeviceIdentifier = String

public protocol DeviceManager : Sendable {

    var devices: [any MWDATCore.DevicePrivate] { get }

    var devicesStream: MWDATCore.AnyAsyncSequence<[any MWDATCore.DevicePrivate]> { get }
}

extension DeviceManager {

    public func findDevice(with identifier: MWDATCore.DeviceIdentifier) -> (any MWDATCore.DevicePrivate)?
}

final public class DeviceManagerImpl : MWDATCore.DeviceManager {

    final public let devicesStream: MWDATCore.AnyAsyncSequence<[any MWDATCore.DevicePrivate]>

    final public var devices: [any MWDATCore.DevicePrivate] { get }

    public init(deviceProvider: any MWDATCore.DeviceProvider)

    @objc deinit

    final public func attachFake(appManager: Any, linkAvailabilityChecker: Any)

    final public func detachFake()
}

public protocol DevicePrivate : Sendable {

    var identifier: MWDATCore.DeviceIdentifier { get }

    var name: String? { get }

    var connection: (any MWDATCore.AnyConnection)? { get }

    var linkState: MWDATCore.LinkState { get }

    var deviceType: MWDATCore.DeviceType { get }

    var compatibility: MWDATCore.Compatibility { get }

    var firmwareInfo: String? { get }

    var deviceUUID: UUID { get }

    func addLinkStateListener(_ listener: @escaping @Sendable (MWDATCore.LinkState) -> Void) -> any MWDATCore.AnyListenerToken

    func addCompatibilityListener(_ listener: @escaping @Sendable (MWDATCore.Compatibility) -> Void) -> any MWDATCore.AnyListenerToken
}

public protocol DeviceProvider : Sendable {

    var deviceEventStream: MWDATCore.AnyAsyncSequence<MWDATCore.DeviceProviderEvent> { get }
}

public enum DeviceProviderEvent : Sendable {

    case discovered(any MWDATCore.DevicePrivate)

    case forgotten(any MWDATCore.DevicePrivate)
}

/// Protocol for selecting which device should be used for operations.
/// Device selectors determine which available device should receive commands or stream data.
public protocol DeviceSelector : Sendable {

    /// The currently active device identifier, if any.
    var activeDevice: MWDATCore.DeviceIdentifier? { get }

    /// Creates a stream of active device changes.
    func activeDeviceStream() -> MWDATCore.AnyAsyncSequence<MWDATCore.DeviceIdentifier?>
}

/// A session representing a connection to a specific wearable device.
///
/// `DeviceSession` manages the lifecycle of a connection to a device and serves as the
/// parent for capabilities (e.g., streaming, display). Create sessions via
/// ``WearablesInterface/createSession(deviceSelector:)``.
///
/// ## Lifecycle
/// 1. Create via `Wearables.shared.createSession(deviceSelector:)`
/// 2. Observe ``statePublisher`` or ``stateStream()`` for state changes
/// 3. Call ``start()`` to connect
/// 4. Attach capabilities (e.g., `addStream()`)
/// 5. Call ``stop()`` to disconnect (cascades to all attached capabilities)
///
/// Sessions are not reusable — after reaching ``DeviceSessionState/stopped``,
/// create a new session via the factory.
final public class DeviceSession : Sendable {

    /// The identifier of the device this session is connected to.
    final public let deviceId: MWDATCore.DeviceIdentifier

    /// An announcer that emits ``DeviceSessionState`` changes.
    final public var statePublisher: any MWDATCore.Announcer<MWDATCore.DeviceSessionState> { get }

    /// An announcer that emits ``DeviceSessionError`` events.
    final public var errorPublisher: any MWDATCore.Announcer<MWDATCore.DeviceSessionError> { get }

    /// The current state of this session.
    final public var state: MWDATCore.DeviceSessionState { get }

    @objc deinit

    /// Starts the session, connecting to the device.
    ///
    /// Validates that the device is available, compatible, and connected before transitioning
    /// to ``DeviceSessionState/starting``. If validation fails, the session stays in
    /// ``DeviceSessionState/idle`` and the error is thrown, allowing the caller to retry later.
    ///
    /// - Throws: ``DeviceSessionError/noEligibleDevice`` if the device is unavailable, incompatible, or disconnected.
    /// - Throws: ``DeviceSessionError/sessionAlreadyStopped`` if the session has already been stopped.
    final public func start() throws(MWDATCore.DeviceSessionError)

    /// Stops the session, disconnecting from the device and cascading stop to all attached capabilities.
    ///
    /// This is a sync fire-and-forget call. Observe ``statePublisher`` or ``stateStream()``
    /// for the transition to ``DeviceSessionState/stopped``. Calling stop on an already
    /// stopped or stopping session is a no-op.
    final public func stop()

    /// Adds a capability to this session.
    ///
    /// Added capabilities will have ``Capability/stop()`` called on them when this
    /// session stops. Only one capability per type is allowed.
    /// The session must be in ``DeviceSessionState/started`` state.
    ///
    /// - Parameter capability: The capability to add.
    /// - Throws: ``DeviceSessionError/sessionIdle`` if the session has not been started yet.
    /// - Throws: ``DeviceSessionError/sessionAlreadyStopped`` if the session is stopped or stopping.
    /// - Throws: ``DeviceSessionError/capabilityAlreadyActive`` if a capability of the same type is already attached.
    final public func addCapability(_ capability: some MWDATCore.Capability) throws(MWDATCore.DeviceSessionError)

    /// Removes a capability from this session by type.
    ///
    /// The session must be in ``DeviceSessionState/started`` state.
    ///
    /// - Parameter type: The type of capability to remove.
    /// - Throws: ``DeviceSessionError/sessionIdle`` if the session has not been started yet.
    /// - Throws: ``DeviceSessionError/sessionAlreadyStopped`` if the session is stopped or stopping.
    /// - Throws: ``DeviceSessionError/capabilityNotFound`` if no capability of the given type is attached.
    final public func removeCapability<T>(_ type: T.Type) throws(MWDATCore.DeviceSessionError) where T : MWDATCore.Capability

    /// Creates an ``AsyncStream`` for observing session state changes.
    ///
    /// Create the stream before calling ``start()`` to avoid missing the initial state transitions.
    final public func stateStream() -> AsyncStream<MWDATCore.DeviceSessionState>

    /// Creates an ``AsyncStream`` for observing session errors.
    final public func errorStream() -> AsyncStream<MWDATCore.DeviceSessionError>
}

/// Errors that can occur during ``DeviceSession`` operations.
@frozen public enum DeviceSessionError : Error, Equatable, Sendable, LocalizedError {

    /// No device is available (not connected, powered off, or incompatible).
    case noEligibleDevice

    /// An operation was attempted on a session that has already stopped.
    case sessionAlreadyStopped

    /// A non-stopped session already exists for this device.
    case sessionAlreadyExists

    /// The operation was called on a session that is still idle (not yet started).
    case sessionIdle

    /// A capability of the same type is already attached to the session.
    case capabilityAlreadyActive

    /// No capability of the given type is attached to the session.
    case capabilityNotFound

    /// An unexpected error occurred.
    case unexpectedError(description: String)

    /// The device thermal state has reached a critical level.
    case thermalCritical

    /// The device thermal state has reached an emergency level and the device is shutting down.
    case thermalEmergency

    /// The device has entered peak power shutdown.
    case peakPowerShutdown

    /// The device battery has reached a critically low level.
    case batteryCritical

    /// The app on the glasses needs an update before the session can start.
    case datAppOnTheGlassesUpdateRequired

    /// The DAT Wearables App on the glasses is not reachable.
    case dwaUnavailable

    /// A localized description of the error, suitable for display in UI or logging.
    public var errorDescription: String? { get }

    /// Returns a Boolean value indicating whether two values are equal.
    ///
    /// Equality is the inverse of inequality. For any values `a` and `b`,
    /// `a == b` implies that `a != b` is `false`.
    ///
    /// - Parameters:
    ///   - lhs: A value to compare.
    ///   - rhs: Another value to compare.
    public static func == (a: MWDATCore.DeviceSessionError, b: MWDATCore.DeviceSessionError) -> Bool
}

/// Represents the current state of a ``DeviceSession``.
@frozen public enum DeviceSessionState : Equatable, Sendable {

    /// The session has been created but ``DeviceSession/start()`` has not been called yet.
    case idle

    /// The session is connecting to the device.
    case starting

    /// The session is connected and active.
    case started

    /// The session is temporarily paused (device-initiated, e.g. cap-touch).
    case paused

    /// The session is stopping and cleaning up resources.
    case stopping

    /// The session has ended. A new session must be created via ``WearablesInterface/createSession(deviceSelector:)``.
    case stopped

    /// Provides a human-readable description of the session state.
    public var description: String { get }

    /// Returns a Boolean value indicating whether two values are equal.
    ///
    /// Equality is the inverse of inequality. For any values `a` and `b`,
    /// `a == b` implies that `a != b` is `false`.
    ///
    /// - Parameters:
    ///   - lhs: A value to compare.
    ///   - rhs: Another value to compare.
    public static func == (a: MWDATCore.DeviceSessionState, b: MWDATCore.DeviceSessionState) -> Bool

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

extension DeviceSessionState : Hashable {
}

extension DeviceSessionState : BitwiseCopyable {
}

/// Represents the current state of a connected device.
///
/// Contains observable device state metrics such as the device's thermal level.
/// Use ``WearablesInterface/deviceStateStream(for:)`` to observe changes.
public struct DeviceState : Sendable, Equatable {

    /// The current thermal level of the device.
    public let thermalLevel: MWDATCore.ThermalLevel

    /// Creates a new device state.
    /// - Parameter thermalLevel: The thermal level of the device. Defaults to ``ThermalLevel/unknown``.
    public init(thermalLevel: MWDATCore.ThermalLevel = .unknown)

    /// Returns a Boolean value indicating whether two values are equal.
    ///
    /// Equality is the inverse of inequality. For any values `a` and `b`,
    /// `a == b` implies that `a != b` is `false`.
    ///
    /// - Parameters:
    ///   - lhs: A value to compare.
    ///   - rhs: Another value to compare.
    public static func == (a: MWDATCore.DeviceState, b: MWDATCore.DeviceState) -> Bool
}

/// Represents the types of Meta Wearables devices supported by the Wearables Device Access Toolkit.
///
/// Each device type corresponds to a specific Meta Wearables hardware variant with distinct
/// capabilities and features.
public enum DeviceType : String, CaseIterable, Sendable {

    /// Unknown or invalid device type
    case unknown

    /// Ray-Ban Meta
    case rayBanMeta

    /// Oakley Meta HSTN
    case oakleyMetaHSTN

    /// Oakley Meta Vanguard
    case oakleyMetaVanguard

    /// Meta Ray-Ban Display
    case metaRayBanDisplay

    /// Ray-Ban Meta Optics
    case rayBanMetaOptics

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
    public typealias AllCases = [MWDATCore.DeviceType]

    /// The raw type that can be used to represent all values of the conforming
    /// type.
    ///
    /// Every distinct value of the conforming type has a corresponding unique
    /// value of the `RawValue` type, but there may be values of the `RawValue`
    /// type that don't have a corresponding value of the conforming type.
    public typealias RawValue = String

    /// A collection of all values of this type.
    nonisolated public static var allCases: [MWDATCore.DeviceType] { get }

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

extension DeviceType {

    /// Returns whether this device type has a built-in display.
    public var supportsDisplay: Bool { get }
}

extension DeviceType : Equatable {
}

extension DeviceType : Hashable {
}

extension DeviceType : RawRepresentable {
}

/// A thread-safe executor that runs async operations exclusively—enqueueing a new operation cancels any pending one.
///
/// When a new operation is enqueued:
/// 1. The previous pending operation is cancelled (cooperative cancellation via `Task.isCancelled`)
/// 2. The new operation waits for the previous one to complete cleanup
/// 3. The new operation executes (if not cancelled while waiting)
///
/// This pattern is useful for state transitions where only the latest request should execute,
/// but previous operations should complete their cleanup before the new one starts.
///
/// Example:
/// ```swift
/// let executor = ExclusiveAsyncExecutor()
///
/// // First operation
/// let task1 = executor.enqueue {
///   await startStreaming()
/// }
///
/// // Second operation cancels first and waits for it
/// let task2 = executor.enqueue {
///   await stopStreaming()
/// }
/// ```
final public class ExclusiveAsyncExecutor : @unchecked Sendable {

    @objc deinit
}

/// Protocol for MockDeviceKit to provide fake registration behavior.
/// CoreKit delegates registration handling methods to this protocol,
/// while keeping internal state monitoring in CoreKit.
public protocol FakeRegistrationHandling : Sendable {

    @MainActor func canOpenURL(_ url: URL) -> Bool

    func open(url: URL)

    func handleUnregister() async throws

    func finishRegistration(authorityKey: String, constellationGroupID: String) throws

    var publicKey: String { get }
}

/// Represents the connection state between a device and the Wearables Device Access Toolkit.
@frozen public enum LinkState : Equatable, Sendable {

    /// The device is not connected to the Wearables Device Access Toolkit.
    case disconnected

    /// The device is currently attempting to establish a connection with the Wearables Device Access Toolkit.
    case connecting

    /// The device is successfully connected and ready for communication.
    case connected

    /// Returns a Boolean value indicating whether two values are equal.
    ///
    /// Equality is the inverse of inequality. For any values `a` and `b`,
    /// `a == b` implies that `a != b` is `false`.
    ///
    /// - Parameters:
    ///   - lhs: A value to compare.
    ///   - rhs: Another value to compare.
    public static func == (a: MWDATCore.LinkState, b: MWDATCore.LinkState) -> Bool

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

extension LinkState : Hashable {
}

extension LinkState : BitwiseCopyable {
}

/// Represents the logging service.
final public class Logging {

    /// Configure the logger with a LoggingConfiguration.
    public static func configure(withConfig config: MWDATCore.LoggingConfiguration)

    public static func error(_ message: @autoclosure () -> String, file: StaticString = #fileID, line: Int32 = #line, function: StaticString = #function)

    public static func warn(_ message: @autoclosure () -> String, file: StaticString = #fileID, line: Int32 = #line, function: StaticString = #function)

    public static func info(_ message: @autoclosure () -> String, file: StaticString = #fileID, line: Int32 = #line, function: StaticString = #function)

    public static func debug(_ message: @autoclosure () -> String, file: StaticString = #fileID, line: Int32 = #line, function: StaticString = #function)

    public static func flush()

    @objc deinit
}

/// Configuration for logging in DAT
public struct LoggingConfiguration : Sendable {

    /// Whether logging is enabled.
    public let enabled: Bool

    /// The directory where log files will be stored. (Always under the app's Caches directory.)
    public let directory: String

    /// The filename for the log file.
    public let filename: String

    /// The log level (e.g., "debug", "info", "error").
    /// Default is "error" if not specified.
    public let level: String

    /// The maximum size of each log file in bytes.
    /// Default is 1MB if not specified.
    public let maxSizeBytes: Int

    /// The maximum number of log files to keep.
    /// Default is 5 if not specified.
    public let maxFiles: Int
}

final public class MockDevicePrivate : MWDATCore.DevicePrivate {

    final public let identifier: MWDATCore.DeviceIdentifier

    final public let name: String?

    final public let connection: (any MWDATCore.AnyConnection)?

    final public let linkState: MWDATCore.LinkState

    final public let deviceType: MWDATCore.DeviceType

    final public let compatibility: MWDATCore.Compatibility

    final public let firmwareInfo: String?

    final public let deviceUUID: UUID

    public init(identifier: MWDATCore.DeviceIdentifier, name: String? = nil, connection: (any MWDATCore.AnyConnection)? = nil, linkState: MWDATCore.LinkState = .disconnected, deviceType: MWDATCore.DeviceType = .unknown, compatibility: MWDATCore.Compatibility = Compatibility.compatible, firmwareInfo: String? = nil, deviceUUID: UUID = UUID())

    final public func addLinkStateListener(_ listener: @escaping (MWDATCore.LinkState) -> Void) -> any MWDATCore.AnyListenerToken

    final public func addCompatibilityListener(_ listener: @escaping (MWDATCore.Compatibility) -> Void) -> any MWDATCore.AnyListenerToken

    final public func createDevice() -> MWDATCore.Device

    @objc deinit
}

public struct Mutex<Value> : ~Copyable where Value : ~Copyable {

    public init(_ initialValue: consuming sending Value)

    @discardableResult
    public borrowing func withLock<Result, E>(_ body: (inout sending Value) throws(E) -> sending Result) throws(E) -> sending Result where E : Error, Result : ~Copyable
}

extension Mutex : @unchecked Sendable where Value : ~Copyable {
}

/// Errors that can occur when navigating to a screen in the Meta AI companion app.
@objc(MWDATNavigationError) @frozen public enum NavigationError : Int, Error {

    /// The Meta AI app is not installed on the device.
    case metaAINotInstalled

    /// The app is not registered with AI glasses.
    case notRegistered

    public var description: String { get }

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

    /// The NSError domain to which this type is bridged.
    public static var _nsErrorDomain: String { get }

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

extension NavigationError : Equatable {
}

extension NavigationError : Hashable {
}

extension NavigationError : RawRepresentable {
}

extension NavigationError : BitwiseCopyable {
}

@objc public class ObjC_AnyListenerToken : NSObject {

    @objc public func cancel()

    @objc deinit
}

/// ObjC-compatible mirror of ``Compatibility``.
@objc(MWDATCompatibility) @frozen public enum ObjC_Compatibility : Int {

    case undefined

    case compatible

    case deviceUpdateRequired

    case sdkUpdateRequired

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

extension ObjC_Compatibility : Equatable {
}

extension ObjC_Compatibility : Hashable {
}

extension ObjC_Compatibility : RawRepresentable {
}

extension ObjC_Compatibility : Sendable {
}

extension ObjC_Compatibility : BitwiseCopyable {
}

@objc(MWDATDevice) public class ObjC_Device : NSObject {

    @objc public var identifier: MWDATCore.DeviceIdentifier { get }

    @objc public var name: String { get }

    @objc public func nameOrId() -> String

    public var linkState: MWDATCore.LinkState { get }

    /// ObjC-accessible mirror of ``linkState``. Visible from ObjC as `linkState`.
    @objc(linkState) public var objcLinkState: MWDATCore.ObjC_LinkState { get }

    public func addLinkStateListener(_ listener: @escaping @Sendable (MWDATCore.LinkState) -> Void) -> MWDATCore.ObjC_AnyListenerToken

    /// ObjC-accessible variant of ``addLinkStateListener(_:)``. Visible from ObjC as `addLinkStateListener:`.
    @objc(addLinkStateListener:) public func objcAddLinkStateListener(_ listener: @escaping @Sendable (MWDATCore.ObjC_LinkState) -> Void) -> MWDATCore.ObjC_AnyListenerToken

    public func compatibility() -> MWDATCore.Compatibility

    /// ObjC-accessible mirror of ``compatibility()``. Visible from ObjC as `compatibility`.
    @objc(compatibility) public var objcCompatibility: MWDATCore.ObjC_Compatibility { get }

    public func addCompatibilityListener(_ listener: @escaping @Sendable (MWDATCore.Compatibility) -> Void) -> MWDATCore.ObjC_AnyListenerToken

    /// ObjC-accessible variant of ``addCompatibilityListener(_:)``. Visible from ObjC as `addCompatibilityListener:`.
    @objc(addCompatibilityListener:) public func objcAddCompatibilityListener(_ listener: @escaping @Sendable (MWDATCore.ObjC_Compatibility) -> Void) -> MWDATCore.ObjC_AnyListenerToken

    public func deviceType() -> MWDATCore.DeviceType

    @objc public static func makeDeviceForTest_DO_NOT_USE(identifier: String, name: String) -> MWDATCore.ObjC_Device

    @objc deinit
}

@objc(MWDATDeviceSession) final public class ObjC_DeviceSession : NSObject, Sendable {

    @objc final public var deviceIdentifier: MWDATCore.DeviceIdentifier { get }

    /// The current state of this session.
    @objc final public var state: MWDATCore.ObjC_DeviceSessionState { get }

    @objc(start:) final public func start(_ error: NSErrorPointer = nil)

    @objc(startAndWaitUntilReadyWithCompletionHandler:) final public func startAndWaitUntilReady(completionHandler: @escaping @Sendable (NSError?) -> Void)

    @objc final public func stop()

    /// Adds a listener for session state changes.
    ///
    /// - Parameter listener: A block called with the new state value.
    /// - Returns: A token that must be retained to keep the listener active.
    @objc final public func addStateListener(_ listener: @escaping @Sendable (MWDATCore.ObjC_DeviceSessionState) -> Void) -> MWDATCore.ObjC_AnyListenerToken

    @objc deinit
}

/// Represents the current state of a device session.
@objc(MWDATDeviceSessionState) @frozen public enum ObjC_DeviceSessionState : Int, Sendable {

    /// The session has been created but not yet started.
    case idle

    /// The session is connecting to the device.
    case starting

    /// The session is connected and active.
    case started

    /// The session is temporarily paused.
    case paused

    /// The session is stopping and cleaning up resources.
    case stopping

    /// The session has ended. Create a new session to reconnect.
    case stopped

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

extension ObjC_DeviceSessionState : Equatable {
}

extension ObjC_DeviceSessionState : Hashable {
}

extension ObjC_DeviceSessionState : RawRepresentable {
}

extension ObjC_DeviceSessionState : BitwiseCopyable {
}

/// ObjC-compatible mirror of ``LinkState``.
@objc(MWDATLinkState) @frozen public enum ObjC_LinkState : Int {

    case disconnected

    case connecting

    case connected

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

extension ObjC_LinkState : Equatable {
}

extension ObjC_LinkState : Hashable {
}

extension ObjC_LinkState : RawRepresentable {
}

extension ObjC_LinkState : Sendable {
}

extension ObjC_LinkState : BitwiseCopyable {
}

@objc(MWDATPermission) @frozen public enum ObjC_Permission : Int {

    case camera

    case microphone

    /// Provides a human-readable description of the permission.
    public var description: String { get }

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

extension ObjC_Permission : Equatable {
}

extension ObjC_Permission : Hashable {
}

extension ObjC_Permission : RawRepresentable {
}

extension ObjC_Permission : Sendable {
}

extension ObjC_Permission : BitwiseCopyable {
}

@objc(MWDATPermissionStatus) @frozen public enum ObjC_PermissionStatus : Int {

    case granted

    case denied

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

extension ObjC_PermissionStatus : Equatable {
}

extension ObjC_PermissionStatus : Hashable {
}

extension ObjC_PermissionStatus : RawRepresentable {
}

extension ObjC_PermissionStatus : Sendable {
}

extension ObjC_PermissionStatus : BitwiseCopyable {
}

@objc(MWDATWearables) final public class ObjC_Wearables : NSObject, Sendable {

    @objc(configure:) public static func configure(_ error: NSErrorPointer = nil)

    /// Reset the shared state, allowing `configure()` to be called again.
    @objc public static func reset()

    @objc public static var sharedInstance: MWDATCore.ObjC_Wearables { get }

    @objc deinit

    @objc final public var registrationState: MWDATCore.RegistrationState { get }

    @objc final public func startRegistration() async throws

    @objc final public func handleUrl(_ url: URL) async throws -> Bool

    @objc final public func startUnregistration() async throws

    @objc final public func openFirmwareUpdate() async throws

    @objc final public func openDATGlassesAppUpdate() async throws

    @objc final public var devices: [MWDATCore.DeviceIdentifier] { get }

    @objc final public func deviceForIdentifier(_ identifier: MWDATCore.DeviceIdentifier) -> MWDATCore.ObjC_Device?

    @objc final public func checkPermissionStatus(_ permission: MWDATCore.ObjC_Permission) async throws -> MWDATCore.ObjC_PermissionStatus

    @objc final public func requestPermission(_ permission: MWDATCore.ObjC_Permission) async throws -> MWDATCore.ObjC_PermissionStatus

    @objc(createSessionForDeviceIdentifier:error:) final public func createSession(forDeviceIdentifier deviceIdentifier: MWDATCore.DeviceIdentifier, error: NSErrorPointer = nil) -> MWDATCore.ObjC_DeviceSession?
}

/// Represents the types of permissions that can be requested from AI glasses.
public enum Permission : Sendable, CaseIterable {

    /// Permission to access camera functionality on the connected wearable device.
    case camera

    /// Permission to access microphone functionality on the connected wearable device.
    case microphone

    /// Returns a Boolean value indicating whether two values are equal.
    ///
    /// Equality is the inverse of inequality. For any values `a` and `b`,
    /// `a == b` implies that `a != b` is `false`.
    ///
    /// - Parameters:
    ///   - lhs: A value to compare.
    ///   - rhs: Another value to compare.
    public static func == (a: MWDATCore.Permission, b: MWDATCore.Permission) -> Bool

    /// A type that can represent a collection of all values of this type.
    public typealias AllCases = [MWDATCore.Permission]

    /// A collection of all values of this type.
    nonisolated public static var allCases: [MWDATCore.Permission] { get }

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

extension Permission : Equatable {
}

extension Permission : Hashable {
}

/// Permission entry representing a single permission for an app.
public struct PermissionEntry : Sendable {

    /// The name of the permission.
    public let permissionName: String

    /// Whether the permission is granted.
    public let isGranted: Bool
}

/// Errors that can occur during permission requests.
@objc(MWDATPermissionError) public enum PermissionError : Int, Error, Sendable {

    /// No wearable devices have been discovered or registered.
    case noDevice

    /// All discovered devices are powered off or disconnected.
    case noDeviceWithConnection

    /// A connection error occurred while communicating with the device.
    case connectionError

    /// The Meta AI companion app is not installed on the device.
    case metaAINotInstalled

    /// A permission request is already in progress.
    case requestInProgress

    /// The permission request exceeded the allowed time limit.
    case requestTimeout

    /// An unexpected internal error occurred.
    case internalError

    public var description: String { get }

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

    /// The NSError domain to which this type is bridged.
    public static var _nsErrorDomain: String { get }

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

extension PermissionError : Equatable {
}

extension PermissionError : Hashable {
}

extension PermissionError : RawRepresentable {
}

/// Represents the status of a permission request.
public enum PermissionStatus : Sendable {

    /// The permission has been granted by the user.
    case granted

    /// The permission has been denied by the user.
    case denied

    /// Returns a Boolean value indicating whether two values are equal.
    ///
    /// Equality is the inverse of inequality. For any values `a` and `b`,
    /// `a == b` implies that `a != b` is `false`.
    ///
    /// - Parameters:
    ///   - lhs: A value to compare.
    ///   - rhs: Another value to compare.
    public static func == (a: MWDATCore.PermissionStatus, b: MWDATCore.PermissionStatus) -> Bool

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

extension PermissionStatus : Equatable {
}

extension PermissionStatus : Hashable {
}

/// Handles URL-based I/O for permission requests — swappable for mock testing.
public protocol PermissionURLOpening : Sendable {

    @MainActor func canOpenURL(_ url: URL) -> Bool

    @MainActor func open(url: URL)
}

/// Manages permissions for Meta Wearables devices.
final public class PermissionsManager : Sendable {

    /// Replaces the URL opener with a fake for mock testing.
    final public func attachFake(urlOpener: any MWDATCore.PermissionURLOpening)

    /// Restores the default URL opener.
    final public func detachFake()

    /// Checks if a specific permission is granted for the current app.
    ///
    /// - Parameter permission: The type of permission to check.
    /// - Returns: ``PermissionStatus`` The status of the permission.
    /// - Throws: PermissionError if the operation fails.
    final public func checkPermissionStatus(_ permission: MWDATCore.Permission) async throws(MWDATCore.PermissionError) -> MWDATCore.PermissionStatus

    /// Requests a specific permission for the current app by opening the permission request URL.
    ///
    /// - Parameter permission: The type of permission to request.
    /// - Returns: ``PermissionStatus`` The status of the permission request.
    /// - Throws: PermissionError if there is an error creating or opening the permission request URL.
    final public func requestPermission(_ permission: MWDATCore.Permission) async throws(MWDATCore.PermissionError) -> MWDATCore.PermissionStatus

    /// Handles a parsed URL response from the FWA app for a permission request
    /// - Parameter params: The parsed URL parameters to handle
    /// - Returns: Boolean indicating if the response was handled
    final public func handlePermission(params: [String : String]) -> Bool

    @objc deinit
}

/// Protocol defining types that can be used as QPL marker annotations
public protocol QPLAnnotatable {

    /// Convert the value to a form that can be used with QPL
    func annotateQPL(using wrapper: MWDATCore.QPLLoggerWrapper, markerId: Int32, instanceKey: Int32, key: String)
}

/// Log level enum matching QPL
public enum QPLLogLevel {

    case debug

    case info

    case warn

    case error

    case fatal

    /// Returns a Boolean value indicating whether two values are equal.
    ///
    /// Equality is the inverse of inequality. For any values `a` and `b`,
    /// `a == b` implies that `a != b` is `false`.
    ///
    /// - Parameters:
    ///   - lhs: A value to compare.
    ///   - rhs: Another value to compare.
    public static func == (a: MWDATCore.QPLLogLevel, b: MWDATCore.QPLLogLevel) -> Bool

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

extension QPLLogLevel : Equatable {
}

extension QPLLogLevel : Hashable {
}

/// A wrapper class for the QPL logger that handles its lifecycle management.
/// This class is not actor-isolated, allowing it to safely clean up resources in its deinit method.
final public class QPLLoggerWrapper : Sendable {

    /// Clean up the QPL logger when this wrapper is deallocated
    @objc deinit
}

/// Error conditions that can occur during the registration process.
@objc(MWDATRegistrationError) @frozen public enum RegistrationError : Int, Error {

    /// User is already registered when attempting to register again.
    case alreadyRegistered

    /// The Wearables Device Access Toolkit configuration is invalid or incomplete.
    case configurationInvalid

    /// The Meta AI app is not installed on the device, which is required for registration.
    case metaAINotInstalled

    /// Network connection is unavailable. Please check your internet connection and try again.
    case networkUnavailable

    /// An unknown error occurred during the registration process.
    case unknown

    /// Provides a human-readable description of the registration error.
    public var description: String { get }

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

    /// The NSError domain to which this type is bridged.
    public static var _nsErrorDomain: String { get }

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

extension RegistrationError : Equatable {
}

extension RegistrationError : Hashable {
}

extension RegistrationError : RawRepresentable {
}

extension RegistrationError : BitwiseCopyable {
}

final public class RegistrationManager : Sendable {

    @objc deinit

    final public func attachFake(fakeAppManager: Any, registrationHandler: (any MWDATCore.FakeRegistrationHandling)? = nil)

    final public func detachFake()

    final public let registrationStateStream: MWDATCore.AnyAsyncSequence<MWDATCore.RegistrationState>

    final public var isDevMode: Bool { get }

    final public var registrationState: MWDATCore.RegistrationState

    final public func startRegistration() async throws(MWDATCore.RegistrationError)

    final public func startRegistrationInternal() async throws(MWDATCore.RegistrationError)

    final public func handleFinishRegistration(params: [String : String]) throws -> Bool

    final public func handleDeleteRegistration() async throws -> Bool

    final public func startUnregistration() async throws(MWDATCore.UnregistrationError)
}

/// Represents the current state of user registration with the Meta Wearables platform.
@objc(MWDATRegistrationState) @frozen public enum RegistrationState : Int {

    /// Registration is not available, typically due to system constraints.
    case unavailable

    /// Registration is available and can be initiated.
    case available

    /// Registration process is in progress.
    case registering

    /// User is successfully registered with the platform.
    case registered

    /// Provides a human-readable description of the registration state.
    public var description: String { get }

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

extension RegistrationState : Equatable {
}

extension RegistrationState : Hashable {
}

extension RegistrationState : RawRepresentable {
}

extension RegistrationState : Sendable {
}

extension RegistrationState : BitwiseCopyable {
}

final public class SessionChannel : Sendable {

    final public func requestStartSession()

    final public func requestStopSession()

    @objc deinit
}

public protocol SessionManager : Sendable {

    func requestSessionHandle(forDeviceId: MWDATCore.DeviceIdentifier, listener: @escaping @Sendable (MWDATCore.SessionState) -> Void) async -> any MWDATCore.AnyListenerToken
}

/// Represents the current state of a device session in the Wearables Device Access Toolkit.
@objc(MWDATSessionState) @frozen public enum SessionState : Int, Sendable {

    /// The session is not active and not attempting to connect.
    case stopped

    /// The session is waiting for a device to become available for connection.
    case waitingForDevice

    /// The session is actively running and processing data from the device.
    case running

    /// The session is temporarily paused but maintains its connection.
    case paused

    /// The session state is not currently determinable.
    case unknown

    /// Provides a human-readable description of the session state.
    public var description: String { get }

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

extension SessionState : Equatable {
}

extension SessionState : Hashable {
}

extension SessionState : RawRepresentable {
}

extension SessionState : BitwiseCopyable {
}

/// A device selector that always selects a specific, predetermined device.
/// Use this when you want to target operations to a particular device by its identifier.
final public class SpecificDeviceSelector : MWDATCore.DeviceSelector {

    /// The currently active device identifier.
    final public var activeDevice: MWDATCore.DeviceIdentifier? { get }

    /// Creates a stream that immediately yields the specific device and then completes.
    final public func activeDeviceStream() -> MWDATCore.AnyAsyncSequence<MWDATCore.DeviceIdentifier?>

    /// Creates a device selector that targets a specific device.
    /// - Parameter device: The identifier of the device to always select.
    public init(device: MWDATCore.DeviceIdentifier)

    @objc deinit
}

/// Represents the thermal level reported by the connected device.
///
/// The thermal level indicates the current temperature state of the glasses.
/// Higher levels indicate progressively more severe thermal conditions, which
/// may affect device performance or trigger protective shutdowns.
@frozen public enum ThermalLevel : Sendable, Equatable {

    /// The thermal level is unknown or has not been reported.
    case unknown

    /// No thermal concern.
    case none

    /// Light thermal activity detected.
    case light

    /// Moderate thermal activity — some features may be throttled.
    case moderate

    /// Severe thermal activity — significant throttling expected.
    case severe

    /// Critical thermal level — device performance is heavily restricted.
    case critical

    /// Emergency thermal level — device is preparing for shutdown.
    case emergency

    /// The device is shutting down due to thermal conditions.
    case shutdown

    /// Returns a Boolean value indicating whether two values are equal.
    ///
    /// Equality is the inverse of inequality. For any values `a` and `b`,
    /// `a == b` implies that `a != b` is `false`.
    ///
    /// - Parameters:
    ///   - lhs: A value to compare.
    ///   - rhs: Another value to compare.
    public static func == (a: MWDATCore.ThermalLevel, b: MWDATCore.ThermalLevel) -> Bool

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

extension ThermalLevel : Hashable {
}

extension ThermalLevel : BitwiseCopyable {
}

/// Error conditions that can occur during the unregistration process.
@objc(MWDATUnregistrationError) @frozen public enum UnregistrationError : Int, Error {

    /// User is already unregistered when attempting to unregister again.
    case alreadyUnregistered

    /// The Wearables Device Access Toolkit configuration is invalid or incomplete.
    case configurationInvalid

    /// The Meta AI app is not installed on the device, which is required for unregistration.
    case metaAINotInstalled

    /// An unknown error occurred during the unregistration process.
    case unknown

    /// Provides a human-readable description of the unregistration error.
    public var description: String { get }

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

    /// The NSError domain to which this type is bridged.
    public static var _nsErrorDomain: String { get }

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

extension UnregistrationError : Equatable {
}

extension UnregistrationError : Hashable {
}

extension UnregistrationError : RawRepresentable {
}

extension UnregistrationError : BitwiseCopyable {
}

public struct VersionData {

    public static let minMWAVersion: Int

    public static let minDWAVersion: String

    public static let FirmwareVersions: [MWDATCore.DeviceType : String]
}

/// The entry point for configuring and accessing the Wearables Device Access Toolkit.
///
/// Provides registration, device management, permissions, and session state functionality for
/// interacting with AI glasses.
public enum Wearables {

    /// Configures the Wearables Device Access Toolkit with settings from the app bundle.
    ///
    /// This method must be called once before accessing ``shared`` or using any other Wearables Device Access Toolkit functionality.
    /// Subsequent calls will throw ``WearablesError/alreadyConfigured``.
    ///
    /// - Throws: ``WearablesError/alreadyConfigured`` if `configure()` has already been called.
    /// - Throws: ``WearablesError/configurationError`` if the app bundle configuration is invalid.
    /// - Throws: ``WearablesError/internalError`` if an unexpected error occurs during configuration.
    public static func configure() throws(MWDATCore.WearablesError)

    /// The shared Device Access Toolkit instance.
    public static var shared: any MWDATCore.WearablesInterface { get }
}

/// Errors that can occur during Device Access Toolkit configuration.
@objc(MWDATWearablesError) @frozen public enum WearablesError : Int, Error {

    /// An unexpected internal error occurred during configuration.
    case internalError

    /// The Device Access Toolkit has already been configured.
    case alreadyConfigured

    /// The configuration provided is invalid or incomplete.
    case configurationError

    public var description: String { get }

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

    /// The NSError domain to which this type is bridged.
    public static var _nsErrorDomain: String { get }

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

extension WearablesError : Equatable {
}

extension WearablesError : Hashable {
}

extension WearablesError : RawRepresentable {
}

extension WearablesError : BitwiseCopyable {
}

/// Errors that can occur during URL handling.
@objc(MWDATWearablesHandleURLError) @frozen public enum WearablesHandleURLError : Int, Error {

    /// An unexpected internal error occurred during registration URL handling.
    case registrationError

    /// An unexpected internal error occurred during unregistration URL handling.
    case unregistrationError

    public var description: String { get }

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

    /// The NSError domain to which this type is bridged.
    public static var _nsErrorDomain: String { get }

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

extension WearablesHandleURLError : Equatable {
}

extension WearablesHandleURLError : Hashable {
}

extension WearablesHandleURLError : RawRepresentable {
}

extension WearablesHandleURLError : BitwiseCopyable {
}

/// The primary interface for Wearables Device Access Toolkit.
public protocol WearablesInterface : Sendable {

    /// The current registration state of the user's devices. See ``RegistrationState`` for options.
    var registrationState: MWDATCore.RegistrationState { get }

    /// Adds a listener to receive callbacks when the registration state changes. The listener is immediately called with the current state.
    /// - Parameter listener: The callback to execute when the registration state changes.
    /// - Returns: A token that can be used to cancel the listener. When the token deinits the listener is also canceled.
    func addRegistrationStateListener(_ listener: @escaping @Sendable (MWDATCore.RegistrationState) -> Void) -> any MWDATCore.AnyListenerToken

    /// Creates an ``AsyncStream`` for observing registration state changes.
    func registrationStateStream() -> AsyncStream<MWDATCore.RegistrationState>

    /// Initiates the registration process with AI glasses.
    ///
    /// This method opens the Meta AI app where the user completes the registration flow.
    /// After the user completes the flow in the Meta AI app, your app will receive a callback
    /// URL that must be passed to ``handleUrl(_:)`` to complete the registration.
    ///
    /// The ``registrationState`` property will be updated throughout the registration process.
    ///
    /// - Throws: ``RegistrationError`` if there is an error starting the registration process.
    func startRegistration() async throws(MWDATCore.RegistrationError)

    /// Handles callback URLs from the Meta AI app during registration and permission flows.
    ///
    /// This method must be called when your app receives a URL callback after the user completes
    /// an action in the Meta AI app. This includes callbacks from ``startRegistration()``,
    /// ``startUnregistration()``, and permission requests.
    ///
    /// The SDK will determine if the URL is relevant to the Wearables Device Access Toolkit.
    /// If not relevant, the method returns `false` without throwing an error.
    ///
    /// ## Platform Flow
    /// On iOS, the Meta AI app returns to your app via a URL scheme callback. You must:
    /// 1. Configure your app's URL schemes in Info.plist
    /// 2. Implement URL handling in your app delegate or scene delegate
    /// 3. Call this method with the received URL
    ///
    /// - Parameter url: The incoming URL to handle.
    /// - Returns: `true` if the URL was handled by the Wearables Device Access Toolkit, `false` if it's not relevant to the Wearables Device Access Toolkit.
    /// - Throws: ``RegistrationError`` if there is an error processing a relevant URL.
    func handleUrl(_ url: URL) async throws(MWDATCore.WearablesHandleURLError) -> Bool

    /// Initiates the unregistration process with AI glasses.
    ///
    /// This method opens the Meta AI app where the user completes the unregistration flow.
    /// After the user completes the flow in the Meta AI app, your app will receive a callback
    /// URL that must be passed to ``handleUrl(_:)`` to complete the unregistration.
    ///
    /// The ``registrationState`` property will be updated throughout the unregistration process.
    ///
    /// - Throws: ``UnregistrationError`` if there is an error starting the unregistration process.
    func startUnregistration() async throws(MWDATCore.UnregistrationError)

    /// Opens the firmware update screen in the Meta AI app for the connected device.
    ///
    /// This method launches the Meta AI app and navigates directly to the firmware update screen.
    /// The user can then check for and install any available firmware updates.
    ///
    /// - Throws: ``NavigationError/notRegistered`` if the app is not registered with AI glasses.
    /// - Throws: ``NavigationError/metaAINotInstalled`` if the Meta AI app is not installed.
    func openFirmwareUpdate() async throws(MWDATCore.NavigationError)

    /// Opens the DAT glasses app update screen in the Meta AI app.
    ///
    /// Developer mode apps are routed to the developer app management surface, while
    /// production apps are routed to the app connections page for the configured Meta app identifier.
    ///
    /// - Throws: ``NavigationError/notRegistered`` if the app is not registered with AI glasses.
    /// - Throws: ``NavigationError/metaAINotInstalled`` if the Meta AI app is not installed.
    func openDATGlassesAppUpdate() async throws(MWDATCore.NavigationError)

    /// The current list of devices available.
    var devices: [MWDATCore.DeviceIdentifier] { get }

    /// Adds a listener to receive callbacks when the device list changes. The listener is immediately called with the current devices.
    /// - Parameter listener: The callback to execute when the device list changes.
    /// - Returns: A token that can be used to cancel the listener. When the token deinits the listener is also canceled.
    func addDevicesListener(_ listener: @escaping @Sendable ([MWDATCore.DeviceIdentifier]) -> Void) -> any MWDATCore.AnyListenerToken

    /// Creates an ``AsyncStream`` for observing device list changes.
    func devicesStream() -> AsyncStream<[MWDATCore.DeviceIdentifier]>

    /// Fetch the underlying ``Device`` object for a given ``DeviceIdentifier``.
    /// - Parameter identifier: The device identifier to fetch.
    /// - Returns: The ``Device`` object for the given device identifier.
    func deviceForIdentifier(_ identifier: MWDATCore.DeviceIdentifier) -> MWDATCore.Device?

    /// Checks if a specific permission is granted for the current application.
    /// - Parameter permission: The type of permission to check.
    /// - Returns: ``PermissionStatus`` The status of the permission.
    /// - Throws: ``PermissionError`` if the operation fails.
    func checkPermissionStatus(_ permission: MWDATCore.Permission) async throws(MWDATCore.PermissionError) -> MWDATCore.PermissionStatus

    /// Requests a specific permission on AI glasses.
    ///
    /// This method opens the Meta AI app where the user completes the permission request flow.
    /// After the user responds in the Meta AI app, your app will receive a callback URL
    /// that must be passed to ``handleUrl(_:)`` to complete the permission request.
    ///
    /// - Parameter permission: The type of permission to request.
    /// - Returns: The ``PermissionStatus`` after the user responds.
    /// - Throws: ``PermissionError`` if there is an error starting the permission request process.
    func requestPermission(_ permission: MWDATCore.Permission) async throws(MWDATCore.PermissionError) -> MWDATCore.PermissionStatus

    /// Creates a new ``DeviceSession`` for the device resolved by the given selector.
    ///
    /// Fails if a non-stopped session already exists for the resolved device.
    /// After the session has stopped or been released, a new one can be created.
    /// Call ``DeviceSession/start()`` to connect, then add capabilities such as
    /// ``DeviceSession/addStream(config:)`` once the session reaches ``DeviceSessionState/started``.
    ///
    /// - Parameter deviceSelector: The selector that determines which device to connect to.
    /// - Returns: A new ``DeviceSession``.
    /// - Throws: ``DeviceSessionError/noEligibleDevice`` if no device is resolved by the selector.
    /// - Throws: ``DeviceSessionError/sessionAlreadyExists`` if an active session already exists for this device.
    func createSession(deviceSelector: any MWDATCore.DeviceSelector) throws(MWDATCore.DeviceSessionError) -> MWDATCore.DeviceSession

    /// Creates an ``AsyncStream`` for observing device state changes on a specific device.
    ///
    /// - Parameter identifier: The device to observe.
    /// - Returns: A stream that yields ``DeviceState`` values when the device state changes (e.g. thermal level).
    func deviceStateStream(for identifier: MWDATCore.DeviceIdentifier) -> AsyncStream<MWDATCore.DeviceState>
}

extension WearablesInterface {

    /// Creates an ``AsyncStream`` for observing registration state changes.
    public func registrationStateStream() -> AsyncStream<MWDATCore.RegistrationState>

    /// Creates an ``AsyncStream`` for observing device list changes.
    public func devicesStream() -> AsyncStream<[MWDATCore.DeviceIdentifier]>
}

public protocol WearablesPrivate : Sendable {

    var configuration: MWDATCore.Configuration { get }

    var deviceManager: any MWDATCore.DeviceManager { get }

    var sessionManager: any MWDATCore.SessionManager { get }

    var registrationManager: MWDATCore.RegistrationManager { get }

    var permissionsManager: MWDATCore.PermissionsManager { get }
}

@objc extension NSNotification {

    @objc public static let wearablesRegistrationStateChanged: Notification.Name

    @objc public static let wearablesDevicesChanged: Notification.Name
}

extension NSNotification.Name {

    /// Posted when a DeviceSession is created via `createSession(deviceSelector:)`.
    /// The `object` is the `DeviceSession` instance.
    public static let mwdatDeviceSessionCreated: Notification.Name
}

extension String : MWDATCore.QPLAnnotatable {

    /// Convert the value to a form that can be used with QPL
    public func annotateQPL(using wrapper: MWDATCore.QPLLoggerWrapper, markerId: Int32, instanceKey: Int32, key: String)
}

extension Int : MWDATCore.QPLAnnotatable {

    /// Convert the value to a form that can be used with QPL
    public func annotateQPL(using wrapper: MWDATCore.QPLLoggerWrapper, markerId: Int32, instanceKey: Int32, key: String)
}

extension Int64 : MWDATCore.QPLAnnotatable {

    /// Convert the value to a form that can be used with QPL
    public func annotateQPL(using wrapper: MWDATCore.QPLLoggerWrapper, markerId: Int32, instanceKey: Int32, key: String)
}

extension Double : MWDATCore.QPLAnnotatable {

    /// Convert the value to a form that can be used with QPL
    public func annotateQPL(using wrapper: MWDATCore.QPLLoggerWrapper, markerId: Int32, instanceKey: Int32, key: String)
}

extension Bool : MWDATCore.QPLAnnotatable {

    /// Convert the value to a form that can be used with QPL
    public func annotateQPL(using wrapper: MWDATCore.QPLLoggerWrapper, markerId: Int32, instanceKey: Int32, key: String)
}

extension AsyncSequence where Self : Sendable {

    public func eraseToAnySequence() -> MWDATCore.AnyAsyncSequence<Self.Element>
}

