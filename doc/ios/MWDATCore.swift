import CoreBluetooth
import CryptoKit
import Foundation
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

    final public func markerStart(markerId: Int32, instanceKey: Int32)

    final public func markerAnnotate<T>(markerId: Int32, instanceKey: Int32, key: String, value: T) where T : MWDATCore.QPLAnnotatable

    final public func markerEnd(markerId: Int32, instanceKey: Int32, actionId: Int16)

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

    public init(wearables: any MWDATCore.WearablesInterface)

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

    @objc deinit
}

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
}

public protocol DevicePrivate : Sendable {

    var identifier: MWDATCore.DeviceIdentifier { get }

    var name: String? { get }

    var connection: (any MWDATCore.AnyConnection)? { get }

    var linkState: MWDATCore.LinkState { get }

    var deviceType: MWDATCore.DeviceType { get }

    var compatibility: MWDATCore.Compatibility { get }

    var firmwareVersion: String? { get }

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

final public class DeviceStateSession : Sendable {

    final public var state: MWDATCore.SessionState { get }

    final public func start() async throws

    final public func stop() async throws

    public convenience init(deviceSelector: any MWDATCore.DeviceSelector)

    @objc deinit
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

extension DeviceType : Equatable {
}

extension DeviceType : Hashable {
}

extension DeviceType : RawRepresentable {
}

public enum IntentURLAction {

    case finishRegistration

    case deleteRegistration

    case permissionResponse

    public static func from(url: URL) -> MWDATCore.IntentURLAction?

    /// Returns a Boolean value indicating whether two values are equal.
    ///
    /// Equality is the inverse of inequality. For any values `a` and `b`,
    /// `a == b` implies that `a != b` is `false`.
    ///
    /// - Parameters:
    ///   - lhs: A value to compare.
    ///   - rhs: Another value to compare.
    public static func == (a: MWDATCore.IntentURLAction, b: MWDATCore.IntentURLAction) -> Bool

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

extension IntentURLAction : Equatable {
}

extension IntentURLAction : Hashable {
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

final public class ListenerStore<T> : MWDATCore.Announcer, @unchecked Sendable {

    public init()

    /// Registers a listener for events of type T.
    /// - Parameter listener: The callback to execute when an event occurs.
    /// - Returns: A token that can be used to cancel the listener.
    final public func listen(_ listener: @escaping @Sendable (T) -> Void) -> any MWDATCore.AnyListenerToken

    final public func addListener(_ listener: @escaping @Sendable (T) -> Void) -> any MWDATCore.AnyListenerToken

    final public func callListeners(_ value: T)

    @objc deinit
}

/// Represents the logging service.
final public class Logging {

    /// Configure the logger with a LoggingConfiguration.
    public static func configure(withConfig config: MWDATCore.LoggingConfiguration)

    public static func error(_ message: @autoclosure () -> String, file: StaticString = #fileID, line: Int32 = #line, function: StaticString = #function)

    public static func warn(_ message: @autoclosure () -> String, file: StaticString = #fileID, line: Int32 = #line, function: StaticString = #function)

    public static func info(_ message: @autoclosure () -> String, file: StaticString = #fileID, line: Int32 = #line, function: StaticString = #function)

    public static func debug(_ message: @autoclosure () -> String, file: StaticString = #fileID, line: Int32 = #line, function: StaticString = #function)

    public static func verbose(_ message: @autoclosure () -> String, file: StaticString = #fileID, line: Int32 = #line, function: StaticString = #function)

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

    final public let firmwareVersion: String?

    final public let deviceUUID: UUID

    public init(identifier: MWDATCore.DeviceIdentifier, name: String? = nil, connection: (any MWDATCore.AnyConnection)? = nil, linkState: MWDATCore.LinkState = .disconnected, deviceType: MWDATCore.DeviceType = .unknown, compatibility: MWDATCore.Compatibility = Compatibility.compatible, firmwareVersion: String? = nil, deviceUUID: UUID = UUID())

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

@objc public class ObjC_AnyListenerToken : NSObject {

    @objc public func cancel()

    @objc deinit
}

@objc(MWDATDevice) public class ObjC_Device : NSObject {

    @objc public var identifier: MWDATCore.DeviceIdentifier { get }

    @objc public var name: String { get }

    @objc public func nameOrId() -> String

    public var linkState: MWDATCore.LinkState { get }

    public func addLinkStateListener(_ listener: @escaping @Sendable (MWDATCore.LinkState) -> Void) -> MWDATCore.ObjC_AnyListenerToken

    public func deviceType() -> MWDATCore.DeviceType

    @objc public static func makeDeviceForTest_DO_NOT_USE(identifier: String, name: String) -> MWDATCore.ObjC_Device

    @objc deinit
}

@objc(MWDATPermission) @frozen public enum ObjC_Permission : Int {

    case camera

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

    @objc public static func resetForTesting()

    @objc public static var sharedInstance: MWDATCore.ObjC_Wearables { get }

    @objc deinit

    @objc final public var registrationState: MWDATCore.RegistrationState

    @objc final public func startRegistration() async throws

    @objc final public func handleUrl(_ url: URL) async throws -> Bool

    @objc final public func startUnregistration() async throws

    @objc final public var devices: [MWDATCore.DeviceIdentifier]

    @objc final public func deviceForIdentifier(_ identifier: MWDATCore.DeviceIdentifier) -> MWDATCore.ObjC_Device?

    @objc final public func checkPermissionStatus(_ permission: MWDATCore.ObjC_Permission) async throws -> MWDATCore.ObjC_PermissionStatus

    @objc final public func requestPermission(_ permission: MWDATCore.ObjC_Permission) async throws -> MWDATCore.ObjC_PermissionStatus

    @objc final public func addDeviceSessionStateListener(forDeviceId deviceId: MWDATCore.DeviceIdentifier, listener: @escaping @Sendable (MWDATCore.SessionState) -> Void) async -> MWDATCore.ObjC_AnyListenerToken
}

/// Represents the types of permissions that can be requested from AI glasses.
public enum Permission : Sendable {

    /// Permission to access camera functionality on the connected wearable device.
    case camera

    /// Returns a Boolean value indicating whether two values are equal.
    ///
    /// Equality is the inverse of inequality. For any values `a` and `b`,
    /// `a == b` implies that `a != b` is `false`.
    ///
    /// - Parameters:
    ///   - lhs: A value to compare.
    ///   - rhs: Another value to compare.
    public static func == (a: MWDATCore.Permission, b: MWDATCore.Permission) -> Bool

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

public struct PermissionRequestResponse {

    public let isGranted: Bool

    public init(isGranted: Bool)
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

/// Manages permissions for Meta Wearables devices.
final public class PermissionsManager : Sendable {

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

    final public func handlePermissionUrl(_ url: URL) -> Bool

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

    final public let registrationStateStream: MWDATCore.AnyAsyncSequence<MWDATCore.RegistrationState>

    final public var registrationState: MWDATCore.RegistrationState

    final public func startRegistration() async throws(MWDATCore.RegistrationError)

    final public func startRegistrationInternal() async throws(MWDATCore.RegistrationError)

    final public func handleFinishRegistrationUrl(_ url: URL) throws -> Bool

    final public func handleDeleteRegistrationUrl(_ url: URL) async throws -> Bool

    final public func startUnregistration() async throws(MWDATCore.UnregistrationError)
}

public struct RegistrationRequestResponse {

    public let authorityKey: String

    public let constellationGroupID: String

    public let attestationValidated: MWDATCore.DATAttestationStatus?

    public init(authorityKey: String, constellationGroupID: String, attestationValidated: MWDATCore.DATAttestationStatus?)
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

final public class SafeContinuation<T, E> : @unchecked Sendable where T : Sendable, E : Error {

    public init(_ continuation: UnsafeContinuation<T, E>)

    @objc deinit

    final public func resume(with result: Result<T, E>)

    final public func resume(returning value: T)

    final public func resume(throwing error: E)

    final public func resume() where T == ()

    final public func cancelAfter(timeout: TimeInterval?) where E == any Error
}

public class SerialAsyncChannel<Element> : AsyncSequence, @unchecked Sendable where Element : Sendable {

    /// The type of asynchronous iterator that produces elements of this
    /// asynchronous sequence.
    public typealias AsyncIterator = MWDATCore.SerialAsyncChannel<Element>.Iterator

    /// The type of element produced by this asynchronous sequence.
    public typealias Element = Element

    public init()

    public func send(_ element: Element)

    public func sendAsync(_ element: Element) async

    /// Creates the asynchronous iterator that produces elements of this
    /// asynchronous sequence.
    ///
    /// - Returns: An instance of the `AsyncIterator` type used to produce
    /// elements of the asynchronous sequence.
    public func makeAsyncIterator() -> MWDATCore.SerialAsyncChannel<Element>.Iterator

    public struct Iterator : AsyncIteratorProtocol {

        /// Asynchronously advances to the next element and returns it, or ends the
        /// sequence if there is no next element.
        ///
        /// - Returns: The next element, if it exists, or `nil` to signal the end of
        ///   the sequence.
        public mutating func next() async -> Element?

        /// The type of failure produced by iteration.
        @available(iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, macOS 15.0, *)
        public typealias __AsyncIteratorProtocol_Failure = Never
    }

    /// The type of errors produced when iteration over the sequence fails.
    @available(iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, macOS 15.0, *)
    public typealias __AsyncSequence_Failure = Never

    @objc deinit
}

final public class SessionChannel : Sendable {

    final public func requestStartSession()

    final public func requestStopSession()

    @objc deinit
}

public protocol SessionManager : Sendable {

    func requestSessionHandle(forDeviceId: MWDATCore.DeviceIdentifier, listener: @escaping @Sendable (MWDATCore.SessionState) -> Void) async -> any MWDATCore.AnyListenerToken

    func addDeviceSessionStateListener(forDeviceId: MWDATCore.DeviceIdentifier, listener: @escaping @Sendable (MWDATCore.SessionState) -> Void) async -> any MWDATCore.AnyListenerToken
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

public enum SharedURLParamKeys : String {

    case metaWearablesAction

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

extension SharedURLParamKeys : Equatable {
}

extension SharedURLParamKeys : Hashable {
}

extension SharedURLParamKeys : RawRepresentable {
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

    public static let FirmwareVersions: [MWDATCore.DeviceType : String]
}

public struct WeakBox<T> where T : AnyObject {

    weak public var value: T?

    public init(_ value: T)
}

extension WeakBox : Sendable where T : Sendable {
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

    func addDeviceSessionStateListener(forDeviceId: MWDATCore.DeviceIdentifier, listener: @escaping @Sendable (MWDATCore.SessionState) -> Void) async -> any MWDATCore.AnyListenerToken
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
}

public struct WearablesSDKAttestationEvent : MWDATCore.AnalyticsEvent {

    public init()

    public init(attestationSessionId: String? = nil, errorType: String? = nil, eventType: MWDATCore.WearablesSDKAttestationEventType? = nil)

    /// The name of the event.
    public var name: String { get }

    /// The data associated with the event.
    public var data: [String : Any] { get }

    public func toMap() -> [String : Any]

    @discardableResult
    public mutating func setAttestationSessionId(_ attestationSessionId: String?) -> MWDATCore.WearablesSDKAttestationEvent

    @discardableResult
    public mutating func setErrorType(_ errorType: String?) -> MWDATCore.WearablesSDKAttestationEvent

    @discardableResult
    public mutating func setEventType(_ eventType: MWDATCore.WearablesSDKAttestationEventType?) -> MWDATCore.WearablesSDKAttestationEvent

    public static func create(attestationSessionId: String? = nil, errorType: String? = nil, eventType: MWDATCore.WearablesSDKAttestationEventType? = nil) -> MWDATCore.WearablesSDKAttestationEvent
}

public enum WearablesSDKAttestationEventType : String, Codable, Sendable {

    case started_attestation

    case completed_attestation

    case failed_attestation

    case challenge_requested

    case key_generated

    case attestation_object_created

    case assertion_object_created

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

extension WearablesSDKAttestationEventType : Equatable {
}

extension WearablesSDKAttestationEventType : Hashable {
}

extension WearablesSDKAttestationEventType : RawRepresentable {
}

public struct WearablesSDKCheckPermissionEvent : MWDATCore.AnalyticsEvent {

    public init()

    public init(error: String? = nil, fwBuildNumber: String? = nil, hasPermission: Bool? = nil, permission: String? = nil, success: Bool? = nil)

    /// The name of the event.
    public var name: String { get }

    /// The data associated with the event.
    public var data: [String : Any] { get }

    public func toMap() -> [String : Any]

    @discardableResult
    public mutating func setError(_ error: String?) -> MWDATCore.WearablesSDKCheckPermissionEvent

    @discardableResult
    public mutating func setFwBuildNumber(_ fwBuildNumber: String?) -> MWDATCore.WearablesSDKCheckPermissionEvent

    @discardableResult
    public mutating func setHasPermission(_ hasPermission: Bool?) -> MWDATCore.WearablesSDKCheckPermissionEvent

    @discardableResult
    public mutating func setPermission(_ permission: String?) -> MWDATCore.WearablesSDKCheckPermissionEvent

    @discardableResult
    public mutating func setSuccess(_ success: Bool?) -> MWDATCore.WearablesSDKCheckPermissionEvent

    public static func create(error: String? = nil, fwBuildNumber: String? = nil, hasPermission: Bool? = nil, permission: String? = nil, success: Bool? = nil) -> MWDATCore.WearablesSDKCheckPermissionEvent
}

public struct WearablesSDKDeviceAnalyticsEvent : MWDATCore.AnalyticsEvent {

    public init()

    public init(deviceIdentifier: String? = nil, error: String? = nil, eventType: MWDATCore.WearablesSDKDeviceAnalyticsEventType? = nil, fwBuildNumber: String? = nil)

    /// The name of the event.
    public var name: String { get }

    /// The data associated with the event.
    public var data: [String : Any] { get }

    public func toMap() -> [String : Any]

    @discardableResult
    public mutating func setDeviceIdentifier(_ deviceIdentifier: String?) -> MWDATCore.WearablesSDKDeviceAnalyticsEvent

    @discardableResult
    public mutating func setError(_ error: String?) -> MWDATCore.WearablesSDKDeviceAnalyticsEvent

    @discardableResult
    public mutating func setEventType(_ eventType: MWDATCore.WearablesSDKDeviceAnalyticsEventType?) -> MWDATCore.WearablesSDKDeviceAnalyticsEvent

    @discardableResult
    public mutating func setFwBuildNumber(_ fwBuildNumber: String?) -> MWDATCore.WearablesSDKDeviceAnalyticsEvent

    public static func create(deviceIdentifier: String? = nil, error: String? = nil, eventType: MWDATCore.WearablesSDKDeviceAnalyticsEventType? = nil, fwBuildNumber: String? = nil) -> MWDATCore.WearablesSDKDeviceAnalyticsEvent
}

public enum WearablesSDKDeviceAnalyticsEventType : String, Codable, Sendable {

    case device_discovered

    case device_forgotten

    case error

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

extension WearablesSDKDeviceAnalyticsEventType : Equatable {
}

extension WearablesSDKDeviceAnalyticsEventType : Hashable {
}

extension WearablesSDKDeviceAnalyticsEventType : RawRepresentable {
}

public struct WearablesSDKGetPermissionsEvent : MWDATCore.AnalyticsEvent {

    public init()

    public init(error: String? = nil, fwBuildNumber: String? = nil, permissions: [String : String]? = nil, success: Bool? = nil)

    /// The name of the event.
    public var name: String { get }

    /// The data associated with the event.
    public var data: [String : Any] { get }

    public func toMap() -> [String : Any]

    @discardableResult
    public mutating func setError(_ error: String?) -> MWDATCore.WearablesSDKGetPermissionsEvent

    @discardableResult
    public mutating func setFwBuildNumber(_ fwBuildNumber: String?) -> MWDATCore.WearablesSDKGetPermissionsEvent

    @discardableResult
    public mutating func setPermissions(_ permissions: [String : String]?) -> MWDATCore.WearablesSDKGetPermissionsEvent

    @discardableResult
    public mutating func setSuccess(_ success: Bool?) -> MWDATCore.WearablesSDKGetPermissionsEvent

    public static func create(error: String? = nil, fwBuildNumber: String? = nil, permissions: [String : String]? = nil, success: Bool? = nil) -> MWDATCore.WearablesSDKGetPermissionsEvent
}

public struct WearablesSDKMockDeviceEvent : MWDATCore.AnalyticsEvent {

    public init()

    public init(deviceIdentifier: String? = nil, deviceType: Int64? = nil, eventType: MWDATCore.WearablesSDKMockDeviceEventType? = nil, fwBuildNumber: String? = nil)

    /// The name of the event.
    public var name: String { get }

    /// The data associated with the event.
    public var data: [String : Any] { get }

    public func toMap() -> [String : Any]

    @discardableResult
    public mutating func setDeviceIdentifier(_ deviceIdentifier: String?) -> MWDATCore.WearablesSDKMockDeviceEvent

    @discardableResult
    public mutating func setDeviceType(_ deviceType: Int64?) -> MWDATCore.WearablesSDKMockDeviceEvent

    @discardableResult
    public mutating func setEventType(_ eventType: MWDATCore.WearablesSDKMockDeviceEventType?) -> MWDATCore.WearablesSDKMockDeviceEvent

    @discardableResult
    public mutating func setFwBuildNumber(_ fwBuildNumber: String?) -> MWDATCore.WearablesSDKMockDeviceEvent

    public static func create(deviceIdentifier: String? = nil, deviceType: Int64? = nil, eventType: MWDATCore.WearablesSDKMockDeviceEventType? = nil, fwBuildNumber: String? = nil) -> MWDATCore.WearablesSDKMockDeviceEvent
}

public enum WearablesSDKMockDeviceEventType : String, Codable, Sendable {

    case doff

    case don

    case fold

    case pair

    case power_off

    case power_on

    case set_camera_feed

    case set_captured_image

    case unfold

    case unpair

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

extension WearablesSDKMockDeviceEventType : Equatable {
}

extension WearablesSDKMockDeviceEventType : Hashable {
}

extension WearablesSDKMockDeviceEventType : RawRepresentable {
}

public struct WearablesSDKMockServiceEvent : MWDATCore.AnalyticsEvent {

    public init()

    public init(error: String? = nil, eventType: MWDATCore.WearablesSDKMockServiceEventType? = nil, fwBuildNumber: String? = nil, serviceId: Int64? = nil, success: Bool? = nil)

    /// The name of the event.
    public var name: String { get }

    /// The data associated with the event.
    public var data: [String : Any] { get }

    public func toMap() -> [String : Any]

    @discardableResult
    public mutating func setError(_ error: String?) -> MWDATCore.WearablesSDKMockServiceEvent

    @discardableResult
    public mutating func setEventType(_ eventType: MWDATCore.WearablesSDKMockServiceEventType?) -> MWDATCore.WearablesSDKMockServiceEvent

    @discardableResult
    public mutating func setFwBuildNumber(_ fwBuildNumber: String?) -> MWDATCore.WearablesSDKMockServiceEvent

    @discardableResult
    public mutating func setServiceId(_ serviceId: Int64?) -> MWDATCore.WearablesSDKMockServiceEvent

    @discardableResult
    public mutating func setSuccess(_ success: Bool?) -> MWDATCore.WearablesSDKMockServiceEvent

    public static func create(error: String? = nil, eventType: MWDATCore.WearablesSDKMockServiceEventType? = nil, fwBuildNumber: String? = nil, serviceId: Int64? = nil, success: Bool? = nil) -> MWDATCore.WearablesSDKMockServiceEvent
}

public enum WearablesSDKMockServiceEventType : String, Codable, Sendable {

    case capture

    case handle_message

    case service_connect

    case service_disconnect

    case stream_start

    case stream_stop

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

extension WearablesSDKMockServiceEventType : Equatable {
}

extension WearablesSDKMockServiceEventType : Hashable {
}

extension WearablesSDKMockServiceEventType : RawRepresentable {
}

public struct WearablesSDKRegisterEvent : MWDATCore.AnalyticsEvent {

    public init()

    public init(registrationStep: MWDATCore.WearablesSDKRegisterEventType? = nil)

    /// The name of the event.
    public var name: String { get }

    /// The data associated with the event.
    public var data: [String : Any] { get }

    public func toMap() -> [String : Any]

    @discardableResult
    public mutating func setRegistrationStep(_ registrationStep: MWDATCore.WearablesSDKRegisterEventType?) -> MWDATCore.WearablesSDKRegisterEvent

    public static func create(registrationStep: MWDATCore.WearablesSDKRegisterEventType? = nil) -> MWDATCore.WearablesSDKRegisterEvent
}

public enum WearablesSDKRegisterEventType : String, Codable, Sendable {

    case started_registration

    case started_unregistration

    case completed_registration

    case completed_unregistration

    case failed_registration

    case failed_unregistration

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

extension WearablesSDKRegisterEventType : Equatable {
}

extension WearablesSDKRegisterEventType : Hashable {
}

extension WearablesSDKRegisterEventType : RawRepresentable {
}

public struct WearablesSDKSessionEvent : MWDATCore.AnalyticsEvent {

    public init(deviceIdentifier: String, sessionState: MWDATCore.WearablesSDKSessionState)

    public init(deviceIdentifier: String, sessionState: MWDATCore.WearablesSDKSessionState, error: String? = nil, fwBuildNumber: String? = nil, previousSessionState: MWDATCore.WearablesSDKSessionState? = nil)

    /// The name of the event.
    public var name: String { get }

    /// The data associated with the event.
    public var data: [String : Any] { get }

    public func toMap() -> [String : Any]

    @discardableResult
    public mutating func setError(_ error: String?) -> MWDATCore.WearablesSDKSessionEvent

    @discardableResult
    public mutating func setFwBuildNumber(_ fwBuildNumber: String?) -> MWDATCore.WearablesSDKSessionEvent

    @discardableResult
    public mutating func setPreviousSessionState(_ previousSessionState: MWDATCore.WearablesSDKSessionState?) -> MWDATCore.WearablesSDKSessionEvent
}

public enum WearablesSDKSessionState : String, Codable, Sendable {

    case stopped

    case waiting_for_device

    case running

    case paused

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

extension WearablesSDKSessionState : Equatable {
}

extension WearablesSDKSessionState : Hashable {
}

extension WearablesSDKSessionState : RawRepresentable {
}

public struct WearablesSDKStreamSessionEvent : MWDATCore.AnalyticsEvent {

    public init()

    public init(audioCodec: String? = nil, deviceIdentifier: String? = nil, durationSeconds: Int64? = nil, errorType: String? = nil, eventType: MWDATCore.WearablesSDKStreamSessionEventType? = nil, frameDelivery: String? = nil, fwBuildNumber: String? = nil, resolution: String? = nil, sessionId: String? = nil, videoCodec: String? = nil)

    /// The name of the event.
    public var name: String { get }

    /// The data associated with the event.
    public var data: [String : Any] { get }

    public func toMap() -> [String : Any]

    @discardableResult
    public mutating func setAudioCodec(_ audioCodec: String?) -> MWDATCore.WearablesSDKStreamSessionEvent

    @discardableResult
    public mutating func setDeviceIdentifier(_ deviceIdentifier: String?) -> MWDATCore.WearablesSDKStreamSessionEvent

    @discardableResult
    public mutating func setDurationSeconds(_ durationSeconds: Int64?) -> MWDATCore.WearablesSDKStreamSessionEvent

    @discardableResult
    public mutating func setErrorType(_ errorType: String?) -> MWDATCore.WearablesSDKStreamSessionEvent

    @discardableResult
    public mutating func setEventType(_ eventType: MWDATCore.WearablesSDKStreamSessionEventType?) -> MWDATCore.WearablesSDKStreamSessionEvent

    @discardableResult
    public mutating func setFrameDelivery(_ frameDelivery: String?) -> MWDATCore.WearablesSDKStreamSessionEvent

    @discardableResult
    public mutating func setFwBuildNumber(_ fwBuildNumber: String?) -> MWDATCore.WearablesSDKStreamSessionEvent

    @discardableResult
    public mutating func setResolution(_ resolution: String?) -> MWDATCore.WearablesSDKStreamSessionEvent

    @discardableResult
    public mutating func setSessionId(_ sessionId: String?) -> MWDATCore.WearablesSDKStreamSessionEvent

    @discardableResult
    public mutating func setVideoCodec(_ videoCodec: String?) -> MWDATCore.WearablesSDKStreamSessionEvent

    public static func create(audioCodec: String? = nil, deviceIdentifier: String? = nil, durationSeconds: Int64? = nil, errorType: String? = nil, eventType: MWDATCore.WearablesSDKStreamSessionEventType? = nil, frameDelivery: String? = nil, fwBuildNumber: String? = nil, resolution: String? = nil, sessionId: String? = nil, videoCodec: String? = nil) -> MWDATCore.WearablesSDKStreamSessionEvent
}

public enum WearablesSDKStreamSessionEventType : String, Codable, Sendable {

    case stream_session_duration

    case stream_session_error

    case stream_session_prepare_completed

    case stream_session_prepare_started

    case stream_session_start_completed

    case stream_session_start_started

    case stream_session_stop_completed

    case stream_session_stop_started

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

extension WearablesSDKStreamSessionEventType : Equatable {
}

extension WearablesSDKStreamSessionEventType : Hashable {
}

extension WearablesSDKStreamSessionEventType : RawRepresentable {
}

@inlinable public func withSafeContinuation<T>(isolation: isolated (any Actor)? = #isolation, _ body: (MWDATCore.SafeContinuation<T, Never>) -> Void) async -> sending T where T : Sendable

@inlinable public func withSafeThrowingContinuation<T>(isolation: isolated (any Actor)? = #isolation, timeout: TimeInterval? = nil, _ body: (MWDATCore.SafeContinuation<T, any Error>) -> Void) async throws -> sending T where T : Sendable

@objc extension NSNotification {

    @objc public static let wearablesRegistrationStateChanged: Notification.Name

    @objc public static let wearablesDevicesChanged: Notification.Name
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

extension Data {

    public func toDeviceIdentifier() -> MWDATCore.DeviceIdentifier
}

