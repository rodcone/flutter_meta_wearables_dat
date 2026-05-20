import AVFoundation
import CoreMedia
import Foundation
import MWDATCore
import UIKit

/// A device selector that automatically selects the best available device.
/// Selects the first connected device from the devices list.
@objc(MWDATAutoDeviceSelector) final public class ObjC_AutoDeviceSelector : NSObject, Sendable {

    /// Creates an auto device selector that monitors the shared Wearables instance for device changes.
    override dynamic public init()

    @objc deinit
}

/// A token that can be used to cancel a listener subscription.
/// Retain this token to keep the listener active; releasing it will cancel the subscription.
@objc(MWDATCameraListenerToken) final public class ObjC_CameraListenerToken : NSObject, Sendable {

    /// Cancels the listener subscription.
    @objc final public func cancel()

    @objc deinit
}

/// Supported formats for capturing photos from Meta Wearables devices.
@objc(MWDATPhotoCaptureFormat) @frozen public enum ObjC_PhotoCaptureFormat : Int, Sendable {

    /// High Efficiency Image Container format (HEIC) - provides better compression than JPEG.
    case heic

    /// Joint Photographic Experts Group format (JPEG) - widely supported image format.
    case jpeg

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

extension ObjC_PhotoCaptureFormat : Equatable {
}

extension ObjC_PhotoCaptureFormat : Hashable {
}

extension ObjC_PhotoCaptureFormat : RawRepresentable {
}

extension ObjC_PhotoCaptureFormat : BitwiseCopyable {
}

/// A photo captured from a Meta Wearables device.
@objc(MWDATPhotoData) final public class ObjC_PhotoData : NSObject, Sendable {

    /// The photo data in the specified format.
    @objc final public var data: Data { get }

    /// The format of the captured photo data.
    @objc final public var format: MWDATCamera.ObjC_PhotoCaptureFormat { get }

    /// Creates a UIImage from the photo data.
    /// - Returns: A UIImage, or nil if the data cannot be converted.
    @objc final public var image: UIImage? { get }

    @objc deinit
}

/// A device selector that always selects a specific, predetermined device.
/// Use this when you want to target operations to a particular device by its identifier.
@objc(MWDATSpecificDeviceSelector) final public class ObjC_SpecificDeviceSelector : NSObject, Sendable {

    /// Creates a device selector that targets a specific device.
    /// - Parameter deviceIdentifier: The identifier of the device to always select.
    @objc public init(deviceIdentifier: MWDATCore.DeviceIdentifier)

    @objc deinit
}

/// A class for managing media streaming sessions with Meta Wearables devices.
/// Handles video streaming, photo capture, and provides real-time state updates.
///
/// In addition to listener-based callbacks, this class also posts the following notifications:
/// - `NSNotification.streamStateChanged` - When session state changes
/// - `NSNotification.streamFrameReceived` - When a video frame is received
/// - `NSNotification.streamPhotoCaptured` - When a photo is captured
/// - `NSNotification.streamErrorOccurred` - When an error occurs
@objc(MWDATStream) final public class ObjC_Stream : NSObject, Sendable {

    /// The configuration used for this streaming session.
    @objc final public let config: MWDATCamera.ObjC_StreamConfiguration

    /// The current state of the streaming session.
    @objc final public var state: MWDATCamera.ObjC_StreamState { get }

    /// Callback invoked when the session state changes.
    ///
    /// - Note: The callback runs on the underlying publisher thread. Dispatch to the main queue
    ///   before updating UI.
    @objc final public var onStateChanged: (@convention(block) (MWDATCamera.ObjC_StreamState) -> Void)?

    /// Callback invoked when a video frame is received.
    ///
    /// - Note: The callback runs on the underlying publisher thread and may fire at high frequency.
    ///   Dispatch to the main queue before updating UI.
    @objc final public var onVideoFrame: (@convention(block) (MWDATCamera.ObjC_VideoFrame) -> Void)?

    /// Callback invoked when a photo is captured.
    ///
    /// - Note: The callback runs on the underlying publisher thread. Dispatch to the main queue
    ///   before updating UI.
    @objc final public var onPhotoData: (@convention(block) (MWDATCamera.ObjC_PhotoData) -> Void)?

    /// Callback invoked when a streaming error occurs.
    ///
    /// - Note: The callback runs on the underlying publisher thread. Dispatch to the main queue
    ///   before updating UI.
    @objc final public var onError: (@convention(block) (MWDATCamera.ObjC_StreamError) -> Void)?

    @objc deinit

    /// Starts video streaming from the device.
    ///
    /// Begins streaming video frames from the currently available device. If no device is currently
    /// available, the session enters `.waitingForDevice` state and automatically connects when a
    /// device becomes available.
    ///
    /// State transitions: `.stopped` -> `.waitingForDevice` (no device) or `.stopped` -> `.starting`
    /// -> `.streaming` (with device).
    @objc final public func start()

    /// Starts video streaming from the device and calls the completion handler when the start
    /// request has been processed.
    ///
    /// The completion handler does not report streaming errors. Subscribe to `onError`,
    /// `addErrorListener(_:)`, or `NSNotification.streamErrorOccurred` to observe failures.
    @objc(startWithCompletion:) final public func start(completion: (@convention(block) () -> Void)?)

    /// Stops video streaming and releases all resources.
    ///
    /// Shuts down the streaming pipeline and transitions to `.stopped` state.
    ///
    /// State transitions: Any state -> `.stopping` -> `.stopped`
    @objc final public func stop()

    /// Stops video streaming and calls the completion handler when the stop transition completes.
    @objc(stopWithCompletion:) final public func stop(completion: (@convention(block) () -> Void)?)

    /// Captures a still photo during streaming.
    ///
    /// Triggers a photo capture while video streaming is active. The captured photo is delivered
    /// through the photo data listener. Video streaming is temporarily paused during capture and
    /// automatically resumes after photo delivery.
    ///
    /// - Parameter format: The desired image format.
    /// - Returns: `true` if the capture request was accepted, `false` if no device session is
    ///   active or a capture is already in progress.
    @discardableResult
    @objc final public func capturePhoto(format: MWDATCamera.ObjC_PhotoCaptureFormat) -> Bool

    /// Adds a listener for state changes.
    ///
    /// The listener will be called on the underlying publisher thread whenever the session state
    /// changes. Dispatch to the main queue before updating UI.
    /// - Parameter listener: A block called with the new state value.
    /// - Returns: A token that must be retained to keep the listener active.
    @objc final public func addStateListener(_ listener: @escaping @Sendable (MWDATCamera.ObjC_StreamState) -> Void) -> MWDATCamera.ObjC_CameraListenerToken

    /// Adds a listener for video frames.
    ///
    /// The listener will be called on the underlying publisher thread for each video frame received.
    /// Dispatch to the main queue before updating UI.
    /// - Parameter listener: A block called with each video frame.
    /// - Returns: A token that must be retained to keep the listener active.
    @objc final public func addVideoFrameListener(_ listener: @escaping @Sendable (MWDATCamera.ObjC_VideoFrame) -> Void) -> MWDATCamera.ObjC_CameraListenerToken

    /// Adds a listener for captured photos.
    ///
    /// The listener will be called on the underlying publisher thread when a photo is captured.
    /// Dispatch to the main queue before updating UI.
    /// - Parameter listener: A block called with the captured photo data.
    /// - Returns: A token that must be retained to keep the listener active.
    @objc final public func addPhotoDataListener(_ listener: @escaping @Sendable (MWDATCamera.ObjC_PhotoData) -> Void) -> MWDATCamera.ObjC_CameraListenerToken

    /// Adds a listener for errors.
    ///
    /// The listener will be called on the underlying publisher thread when an error occurs. Dispatch
    /// to the main queue before updating UI.
    /// - Parameter listener: A block called with the error code.
    /// - Returns: A token that must be retained to keep the listener active.
    @objc final public func addErrorListener(_ listener: @escaping @Sendable (MWDATCamera.ObjC_StreamError) -> Void) -> MWDATCamera.ObjC_CameraListenerToken
}

/// Configuration for a media streaming session with a Meta Wearables device.
@objc(MWDATStreamConfiguration) final public class ObjC_StreamConfiguration : NSObject, Sendable {

    /// The video codec to use for streaming.
    @objc final public var videoCodec: MWDATCamera.ObjC_VideoCodec { get }

    /// The resolution at which to stream video content.
    @objc final public var resolution: MWDATCamera.ObjC_StreamingResolution { get }

    /// The target frame rate for the streaming session.
    @objc final public var frameRate: Int { get }

    /// Creates a new stream session configuration with default settings.
    override dynamic public convenience init()

    /// Creates a new stream session configuration with specified parameters.
    /// - Parameters:
    ///   - videoCodec: The video codec to use for streaming.
    ///   - resolution: The resolution for video streaming.
    ///   - frameRate: The target frame rate for streaming.
    @objc public init(videoCodec: MWDATCamera.ObjC_VideoCodec, resolution: MWDATCamera.ObjC_StreamingResolution, frameRate: Int)

    @objc deinit
}

/// Errors that can occur during streaming sessions.
@objc(MWDATStreamError) @frozen public enum ObjC_StreamError : Int, Sendable {

    /// An internal error occurred.
    case internalError

    /// The specified device could not be found.
    case deviceNotFound

    /// The specified device is not connected.
    case deviceNotConnected

    /// The operation timed out.
    case timeout

    /// Video streaming encountered an error.
    case videoStreamingError

    /// Camera permission was denied.
    case permissionDenied

    /// The device hinges were closed during streaming.
    case hingesClosed

    /// The device thermal state has reached a critical level that may affect streaming performance.
    case thermalCritical

    /// The device thermal state has reached an emergency level and the device is shutting down.
    case thermalEmergency

    /// The device has entered peak power shutdown.
    case peakPowerShutdown

    /// The device battery has reached a critically low level.
    case batteryCritical

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

extension ObjC_StreamError : Equatable {
}

extension ObjC_StreamError : Hashable {
}

extension ObjC_StreamError : RawRepresentable {
}

extension ObjC_StreamError : BitwiseCopyable {
}

/// Represents the current state of a media streaming session.
@objc(MWDATStreamState) @frozen public enum ObjC_StreamState : Int, Sendable {

    /// The session is completely stopped and not attempting to connect.
    case stopped

    /// The session is waiting for a compatible device to become available.
    case waitingForDevice

    /// The session is in the process of starting up.
    case starting

    /// The session is actively streaming media data.
    case streaming

    /// The session is temporarily paused but maintains its connection.
    case paused

    /// The session is in the process of stopping.
    case stopping

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

extension ObjC_StreamState : Equatable {
}

extension ObjC_StreamState : Hashable {
}

extension ObjC_StreamState : RawRepresentable {
}

extension ObjC_StreamState : BitwiseCopyable {
}

/// Valid streaming resolutions for live video from Meta Wearables devices.
@objc(MWDATStreamingResolution) @frozen public enum ObjC_StreamingResolution : Int, Sendable {

    /// High resolution streaming at 720x1280 pixels.
    case high

    /// Medium resolution streaming at 504x896 pixels.
    case medium

    /// Low resolution streaming at 360x640 pixels.
    case low

    /// The video frame width for this resolution.
    public var width: Int { get }

    /// The video frame height for this resolution.
    public var height: Int { get }

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

extension ObjC_StreamingResolution : Equatable {
}

extension ObjC_StreamingResolution : Hashable {
}

extension ObjC_StreamingResolution : RawRepresentable {
}

extension ObjC_StreamingResolution : BitwiseCopyable {
}

/// Specifies the video codec to use for streaming.
@objc(MWDATVideoCodec) @frozen public enum ObjC_VideoCodec : Int, Sendable {

    /// Raw decompressed video frames (420v YUV pixel buffers).
    /// Video frames are only delivered while the app is in the foreground.
    case raw

    /// Compressed HEVC video frames (hvc1).
    /// Frames are delivered in both foreground and background.
    case hvc1

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

extension ObjC_VideoCodec : Equatable {
}

extension ObjC_VideoCodec : Hashable {
}

extension ObjC_VideoCodec : RawRepresentable {
}

extension ObjC_VideoCodec : BitwiseCopyable {
}

/// Represents a single frame of video data from a Meta Wearables device.
@objc(MWDATVideoFrame) final public class ObjC_VideoFrame : NSObject, Sendable {

    /// Provides access to the underlying video sample buffer.
    ///
    /// **Important**: Callers must treat this buffer as read-only. The buffer
    /// is only valid for the duration of the listener callback.
    @objc final public var sampleBuffer: CMSampleBuffer { get }

    /// Converts the video frame to a UIImage for display or processing.
    /// - Returns: A UIImage representation of the video frame, or nil if conversion fails.
    @objc final public var image: UIImage? { get }

    @objc deinit
}

/// Supported formats for capturing photos from Meta Wearables devices.
public enum PhotoCaptureFormat : Sendable {

    /// High Efficiency Image Container format (HEIC) - provides better compression than JPEG.
    case heic

    /// Joint Photographic Experts Group format (JPEG) - widely supported image format.
    case jpeg

    /// Returns a Boolean value indicating whether two values are equal.
    ///
    /// Equality is the inverse of inequality. For any values `a` and `b`,
    /// `a == b` implies that `a != b` is `false`.
    ///
    /// - Parameters:
    ///   - lhs: A value to compare.
    ///   - rhs: Another value to compare.
    public static func == (a: MWDATCamera.PhotoCaptureFormat, b: MWDATCamera.PhotoCaptureFormat) -> Bool

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

extension PhotoCaptureFormat : Equatable {
}

extension PhotoCaptureFormat : Hashable {
}

/// A photo captured from a Meta Wearables device.
public struct PhotoData : Sendable {

    /// The photo data in the specified format.
    public let data: Data

    /// The format of the captured photo data.
    public let format: MWDATCamera.PhotoCaptureFormat

    public init(data: Data, format: MWDATCamera.PhotoCaptureFormat)
}

/// A class for managing media streaming capabilities with Meta Wearables devices.
/// Handles video streaming, photo capture, and provides real-time state updates.
///
/// In Swift, create a ``Stream`` by first creating and starting a ``DeviceSession``,
/// then calling ``DeviceSession/addStream(config:)``. The returned stream is attached to that
/// device session and stops automatically when the parent device session stops.
final public class Stream : Sendable {

    /// The configuration used for this streaming session.
    final public let streamConfiguration: MWDATCamera.StreamConfiguration

    /// The current state of the streaming session.
    final public var state: MWDATCamera.StreamState { get }

    /// Publisher for streaming session state changes.
    final public var statePublisher: any MWDATCore.Announcer<MWDATCamera.StreamState> { get }

    /// Publisher for video frames received from the streaming session.
    final public var videoFramePublisher: any MWDATCore.Announcer<MWDATCamera.VideoFrame> { get }

    /// Publisher for photo data captured during the streaming session.
    final public var photoDataPublisher: any MWDATCore.Announcer<MWDATCamera.PhotoData> { get }

    /// Publisher for errors that occur during the streaming session.
    final public var errorPublisher: any MWDATCore.Announcer<MWDATCamera.StreamError> { get }

    @objc deinit

    /// Starts video streaming from the device.
    ///
    /// Begins streaming video frames from the currently available device. If no device is currently
    /// available, the session enters `.waitingForDevice` state and automatically connects when a
    /// device becomes available. Video frames are delivered through ``videoFramePublisher``.
    ///
    /// State transitions: `.stopped` -> `.waitingForDevice` (no device) or `.stopped` -> `.starting`
    /// -> `.streaming` (with device).
    ///
    /// The session monitors for device availability and automatically connects when a device becomes
    /// available and publishes errors if the device is invalid. The session automatically stops when
    /// an error occurs or when the device session ends externally (e.g., device powered off).
    ///
    /// Errors published to ``errorPublisher``:
    /// - ``StreamError/deviceNotFound(_:)``
    /// - ``StreamError/deviceNotConnected(_:)``
    /// - ``StreamError/timeout``
    /// - ``StreamError/permissionDenied``
    /// - ``StreamError/hingesClosed``
    /// - ``StreamError/internalError``
    final public func start() async

    /// Stops video streaming and releases all resources.
    ///
    /// Shuts down the streaming pipeline and transitions to `.stopped` state.
    ///
    /// State transitions: Any state -> `.stopping` -> `.stopped`
    final public func stop() async

    /// Captures a still photo during streaming.
    ///
    /// Triggers a photo capture while video streaming is active. The captured photo is delivered
    /// through ``photoDataPublisher``. Video streaming is temporarily paused during capture and
    /// automatically resumes after photo delivery.
    ///
    /// - Parameter format: The desired image format.
    /// - Returns: `true` if the capture request was accepted, `false` if no device session is
    ///   active, a capture is already in progress, or the underlying capture request fails.
    @discardableResult
    final public func capturePhoto(format: MWDATCamera.PhotoCaptureFormat) -> Bool
}

extension Stream : MWDATCore.Capability {

    /// The current state of this capability.
    final public var capabilityState: MWDATCore.CapabilityState { get }
}

/// Configuration for a media streaming session with a Meta Wearables device.
/// Defines video codec, resolution, frame delivery strategy, and target frame rate.
public struct StreamConfiguration : Sendable {

    /// The video codec to use for streaming.
    public let videoCodec: MWDATCamera.VideoCodec

    /// The resolution at which to stream video content.
    public let resolution: MWDATCamera.StreamingResolution

    /// The target frame rate for the streaming session.
    public let frameRate: UInt

    /// Creates a new stream session configuration with specified parameters.
    /// - Parameters:
    ///   - videoCodec: The video codec to use for streaming.
    ///   - resolution: The resolution for video streaming.
    ///   - frameRate: The target frame rate for streaming.
    public init(videoCodec: MWDATCamera.VideoCodec, resolution: MWDATCamera.StreamingResolution, frameRate: UInt)

    /// Creates a new stream session configuration with default settings.
    /// Uses raw video codec, medium resolution, deliver-all frame strategy, and 30 FPS.
    public init()
}

/// Errors that can occur during streaming sessions.
public enum StreamError : Error, Equatable, LocalizedError {

    /// An internal error occurred.
    case internalError

    /// The specified device could not be found.
    case deviceNotFound(MWDATCore.DeviceIdentifier)

    /// The specified device is not connected.
    case deviceNotConnected(MWDATCore.DeviceIdentifier)

    /// The operation timed out.
    case timeout

    /// Video streaming encountered an error.
    case videoStreamingError

    /// Camera permission was denied.
    case permissionDenied

    /// The device hinges were closed during streaming.
    case hingesClosed

    /// The device thermal state has reached a critical level that may affect streaming performance.
    case thermalCritical

    /// The device thermal state has reached an emergency level and the device is shutting down.
    case thermalEmergency

    /// The device has entered peak power shutdown.
    case peakPowerShutdown

    /// The device battery has reached a critically low level.
    case batteryCritical

    /// A description of the error
    public var errorDescription: String? { get }

    /// Returns a Boolean value indicating whether two values are equal.
    ///
    /// Equality is the inverse of inequality. For any values `a` and `b`,
    /// `a == b` implies that `a != b` is `false`.
    ///
    /// - Parameters:
    ///   - lhs: A value to compare.
    ///   - rhs: Another value to compare.
    public static func == (a: MWDATCamera.StreamError, b: MWDATCamera.StreamError) -> Bool
}

/// Represents the current state of a media streaming session with a Meta Wearables device.
@frozen public enum StreamState : Sendable {

    /// The session is in the process of stopping.
    case stopping

    /// The session is completely stopped and not attempting to connect.
    case stopped

    /// The session is waiting for a compatible device to become available.
    case waitingForDevice

    /// The session is in the process of starting up.
    case starting

    /// The session is actively streaming media data.
    case streaming

    /// The session is temporarily paused but maintains its connection.
    case paused

    /// Returns a Boolean value indicating whether two values are equal.
    ///
    /// Equality is the inverse of inequality. For any values `a` and `b`,
    /// `a == b` implies that `a != b` is `false`.
    ///
    /// - Parameters:
    ///   - lhs: A value to compare.
    ///   - rhs: Another value to compare.
    public static func == (a: MWDATCamera.StreamState, b: MWDATCamera.StreamState) -> Bool

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

extension StreamState : Equatable {
}

extension StreamState : Hashable {
}

extension StreamState : BitwiseCopyable {
}

/// Valid Live Streaming resolutions. We are using 9:16 aspect ratio.
public enum StreamingResolution : Sendable, CaseIterable {

    /// High resolution streaming at 720x1280 pixels.
    case high

    /// Medium resolution streaming at 504x896 pixels.
    case medium

    /// Low resolution streaming at 360x640 pixels.
    case low

    /// The video frame dimensions for this resolution.
    public var videoFrameSize: MWDATCamera.VideoFrameSize { get }

    /// Returns a Boolean value indicating whether two values are equal.
    ///
    /// Equality is the inverse of inequality. For any values `a` and `b`,
    /// `a == b` implies that `a != b` is `false`.
    ///
    /// - Parameters:
    ///   - lhs: A value to compare.
    ///   - rhs: Another value to compare.
    public static func == (a: MWDATCamera.StreamingResolution, b: MWDATCamera.StreamingResolution) -> Bool

    /// A type that can represent a collection of all values of this type.
    public typealias AllCases = [MWDATCamera.StreamingResolution]

    /// A collection of all values of this type.
    nonisolated public static var allCases: [MWDATCamera.StreamingResolution] { get }

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

extension StreamingResolution : Equatable {
}

extension StreamingResolution : Hashable {
}

/// Specifies the video codec to use for streaming.
public enum VideoCodec : Sendable {

    /// Raw decompressed video frames (420v YUV pixel buffers).
    /// - Note: Video frames are only delivered while the app is in the foreground.
    ///   When the app enters background, frame delivery stops. Use ``hvc1`` if you
    ///   need to receive frames while backgrounded.
    case raw

    /// Compressed HEVC video frames (hvc1).
    /// Frames are delivered as compressed `CMSampleBuffer`s without decoding,
    /// in both foreground and background.
    case hvc1

    /// Returns a Boolean value indicating whether two values are equal.
    ///
    /// Equality is the inverse of inequality. For any values `a` and `b`,
    /// `a == b` implies that `a != b` is `false`.
    ///
    /// - Parameters:
    ///   - lhs: A value to compare.
    ///   - rhs: Another value to compare.
    public static func == (a: MWDATCamera.VideoCodec, b: MWDATCamera.VideoCodec) -> Bool

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

extension VideoCodec : Equatable {
}

extension VideoCodec : Hashable {
}

/// Represents a single frame of video data from a Meta Wearables device.
/// Contains the raw video sample buffer and provides utilities for converting to UIImage.
public struct VideoFrame : Sendable {

    /// Provides access to the underlying video sample buffer.
    ///
    /// **Important**: While this property exposes the raw ``CoreMedia/CMSampleBuffer`` for advanced use cases,
    /// callers must treat it as read-only. Mutating the sample buffer's attachments, timing information, or
    /// underlying pixel buffer may lead to undefined behavior, crashes, or data corruption since the buffer
    /// is shared across multiple contexts without synchronization.
    ///
    /// For safe image conversion, use ``makeUIImage()`` instead.
    public var sampleBuffer: CMSampleBuffer { get }

    /// Converts the video frame to a UIImage for display or processing.
    /// This method handles the conversion from the underlying CoreMedia sample buffer to a UIImage.
    /// - Returns: A UIImage representation of the video frame, or nil if conversion fails.
    public func makeUIImage() -> sending UIImage?
}

/// Represents the width and height of a video frame in pixels.
public struct VideoFrameSize : Sendable {

    /// The width of the video frame in pixels.
    public let width: UInt

    /// The height of the video frame in pixels.
    public let height: UInt

    /// Creates a new video frame size with the specified dimensions.
    /// - Parameters:
    ///   - width: The width of the video frame in pixels.
    ///   - height: The height of the video frame in pixels.
    public init(width: UInt, height: UInt)
}

extension DeviceSession {

    /// Creates and adds a ``Stream`` to this device session.
    ///
    /// This is the supported Swift entry point for camera streaming.
    ///
    /// The device session must be in ``DeviceSessionState/started`` state. The returned
    /// stream session is automatically added as a capability and will be stopped when
    /// this device session stops.
    ///
    /// - Parameter config: Configuration for the streaming session. Defaults to ``StreamConfiguration()``.
    /// - Returns: A configured ``Stream`` added to this device session, or `nil`
    ///   if the session is not in the started state.
    /// - Throws: ``DeviceSessionError/capabilityAlreadyActive`` if a Stream is already attached.
    final public func addStream(config: MWDATCamera.StreamConfiguration = StreamConfiguration()) throws(MWDATCore.DeviceSessionError) -> MWDATCamera.Stream?
}

extension NSNotification.Name {

    /// Posted when a Stream is created via `addStream(config:)`.
    /// The `object` is the `Stream` instance.
    public static let mwdatStreamSessionCreated: Notification.Name
}

extension ObjC_DeviceSession {

    /// Creates a stream capability with the default configuration.
    ///
    /// Returns `nil` without setting `error` when the device session is not started yet.
    @objc(addStreamWithError:) final public func addStream(_ error: NSErrorPointer = nil) -> MWDATCamera.ObjC_Stream?

    /// Creates a stream capability with the provided configuration.
    ///
    /// Returns `nil` without setting `error` when the device session is not started yet.
    @objc(addStreamWithConfig:error:) final public func addStream(config: MWDATCamera.ObjC_StreamConfiguration, error: NSErrorPointer = nil) -> MWDATCamera.ObjC_Stream?
}

/// Notification names for stream session events.
///
/// - Important: Notifications are delivered on a background thread. If your observer updates UI,
///   dispatch to the main queue:
///   ```objc
///   - (void)onStateChanged:(NSNotification *)notification {
///     dispatch_async(dispatch_get_main_queue(), ^{
///       // UI updates here
///     });
///   }
///   ```
@objc extension NSNotification {

    /// Posted when stream session state changes.
    /// - Note: Delivered on a background thread. Dispatch to main queue for UI updates.
    /// - object: The `MWDATStream` instance that changed state.
    /// - userInfo: `["state": NSNumber]` containing a `MWDATStreamState` raw value.
    @objc public static let streamStateChanged: Notification.Name

    /// Posted when a video frame is received.
    /// - Note: Delivered on a background thread at up to 30-60 fps. Dispatch to main queue for UI updates.
    /// - object: The `MWDATStream` instance that received the frame.
    /// - userInfo: `["frame": MWDATVideoFrame]`
    @objc public static let streamFrameReceived: Notification.Name

    /// Posted when a photo is captured.
    /// - Note: Delivered on a background thread. Dispatch to main queue for UI updates.
    /// - object: The `MWDATStream` instance that captured the photo.
    /// - userInfo: `["photo": MWDATPhotoData]`
    @objc public static let streamPhotoCaptured: Notification.Name

    /// Posted when an error occurs during streaming.
    /// - Note: Delivered on a background thread. Dispatch to main queue for UI updates.
    /// - object: The `MWDATStream` instance where the error occurred.
    /// - userInfo: `["error": NSError]` with a `localizedDescription` suitable for display.
    @objc public static let streamErrorOccurred: Notification.Name
}

