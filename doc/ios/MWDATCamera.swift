// ⚠️ Reference snapshot of the DAT public API — may lag the vendored binaries.
// Authoritative source: the vendored `.swiftinterface` under
// ios/flutter_meta_wearables_dat/Frameworks/MWDATCamera.xcframework/.../*.swiftinterface
import AVFoundation
import CoreMedia
import Foundation
import ImageIO
import MWDATCore
import UIKit

/// Specifies how decoded audio is delivered with a camera streaming session.
///
/// @Unpublishable
public enum AudioCodec : Sendable {

    /// Apple Standard PCM (Float32 native-endian) with specified sample rate and number of channels.
    case pcm(sampleRate: MWDATCamera.AudioSampleRate, numberOfChannels: UInt32)
}

/// Represents a single frame of audio data from a Meta Wearables device.
/// Contains a PCM buffer with audio samples and timing information.
///
/// @Unpublishable
public struct AudioFrame : @unchecked Sendable {

    /// The PCM buffer containing the audio sample data.
    public let pcmBuffer: AVAudioPCMBuffer

    /// The presentation timestamp for synchronizing audio with video.
    public let presentationTimeStamp: CMTime
}

/// Supported audio sample rates for streaming from Meta Wearables devices.
///
/// The available sample rates are constrained to values supported by the device hardware.
///
/// @Unpublishable
@frozen public enum AudioSampleRate : UInt, Sendable, CaseIterable {

    /// 16,000 Hz — suitable for speech/voice applications.
    case rate16000

    /// 44,100 Hz — CD-quality audio.
    case rate44100

    /// 48,000 Hz — professional audio quality.
    case rate48000

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
    public init?(rawValue: UInt)

    /// A type that can represent a collection of all values of this type.
    public typealias AllCases = [MWDATCamera.AudioSampleRate]

    /// The raw type that can be used to represent all values of the conforming
    /// type.
    ///
    /// Every distinct value of the conforming type has a corresponding unique
    /// value of the `RawValue` type, but there may be values of the `RawValue`
    /// type that don't have a corresponding value of the conforming type.
    public typealias RawValue = UInt

    /// A collection of all values of this type.
    nonisolated public static var allCases: [MWDATCamera.AudioSampleRate] { get }

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
    public var rawValue: UInt { get }
}

extension AudioSampleRate : Equatable {
}

extension AudioSampleRate : Hashable {
}

extension AudioSampleRate : RawRepresentable {
}

extension AudioSampleRate : BitwiseCopyable {
}

/// Consolidated camera capability for a Meta Wearables device.
///
/// A ``Camera`` owns the camera hardware resource and exposes its child features. It is attached
/// to a ``DeviceSession`` via ``DeviceSession/addCamera(config:)`` and is automatically stopped
/// when the parent session stops (cascading stop); it can also be stopped individually via
/// ``stop()``.
///
/// The child features are owned by the camera and share its lifecycle:
/// - ``stream`` — video streaming (and in-stream photo capture).
/// - ``photo`` — standalone high-quality photo capture for development and beta release channels.
///
/// Stream and Photo compete for the camera hardware and cannot capture simultaneously; the
/// developer is responsible for stopping one before starting the other.
///
/// In Swift, create a ``Camera`` by first creating and starting a ``DeviceSession``, then calling
/// ``DeviceSession/addCamera(config:)``. The returned camera is attached to that device session
/// and stops automatically when the parent device session stops or its stream fails terminally.
/// A terminal stream failure also detaches the camera so a replacement can be added to the same
/// device session.
final public class Camera : Sendable {

    /// The video streaming child feature, owned by this camera.
    ///
    /// Use it to receive real-time camera frames. Its lifecycle is bound to this camera: stopping
    /// the camera stops the stream. Stopping only the stream does not stop or detach the camera.
    final public let stream: MWDATCamera.Stream

    /// The high-quality photo capture child feature, owned by this camera.
    ///
    /// Its lifecycle is bound to this camera: stopping the camera stops photo capture. Photo and
    /// Stream compete for the camera hardware and cannot capture simultaneously — stop one before
    /// starting the other. This API is available in development and beta release channels.
    ///
    /// @Unpublishable
    final public let photo: MWDATCamera.Photo

    /// The current lifecycle state of this camera.
    final public var state: MWDATCamera.CameraState { get }

    /// Publisher for camera lifecycle state changes.
    final public var statePublisher: any MWDATCore.Announcer<MWDATCamera.CameraState> { get }

    /// Stops this camera and its child features, releasing resources and detaching from the parent
    /// session.
    ///
    /// After calling ``stop()``, the camera is invalidated and cannot be reused. Calling ``stop()``
    /// on an already-stopped camera is a no-op.
    final public func stop()

    @objc deinit
}

/// Represents the current lifecycle state of a ``Camera`` capability.
///
/// Modeled on ``StreamState`` so the parent camera capability reports its lifecycle with the
/// same vocabulary as its child features. A camera becomes ``started`` once it is attached to a
/// started session, and transitions through ``stopping`` to ``stopped`` when it (or the owning
/// session) is stopped. Child features are only usable while the camera is ``started``.
@frozen public enum CameraState : Sendable {

    /// The camera is in the process of starting up.
    ///
    /// Reserved for parity with ``StreamState`` and future asynchronous start paths. A camera is
    /// currently created already-attached to a started session (see ``DeviceSession/addCamera(config:)``),
    /// so it enters ``started`` directly and this case is not emitted today.
    case starting

    /// The camera is attached to a started session; its child features can be used.
    case started

    /// The camera is in the process of stopping.
    case stopping

    /// The camera is stopped and detached from its session.
    case stopped

    /// Returns a Boolean value indicating whether two values are equal.
    ///
    /// Equality is the inverse of inequality. For any values `a` and `b`,
    /// `a == b` implies that `a != b` is `false`.
    ///
    /// - Parameters:
    ///   - lhs: A value to compare.
    ///   - rhs: Another value to compare.
    public static func == (a: MWDATCamera.CameraState, b: MWDATCamera.CameraState) -> Bool

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

extension CameraState : Equatable {
}

extension CameraState : Hashable {
}

extension CameraState : BitwiseCopyable {
}

/// Audio codec configuration for streaming sessions.
///
/// @Unpublishable
@objc(MWDATAudioCodec) final public class ObjC_AudioCodec : NSObject, Sendable {

    /// The sample rate in Hz.
    @objc final public var sampleRate: UInt { get }

    /// The number of audio channels.
    @objc final public var numberOfChannels: UInt32 { get }

    /// Creates a PCM audio codec configuration.
    /// - Parameters:
    ///   - sampleRate: The sample rate in Hz (e.g., 44100).
    ///   - numberOfChannels: The number of audio channels (e.g., 2 for stereo).
    @objc public init(sampleRate: UInt, numberOfChannels: UInt32)

    @objc deinit
}

/// Objective-C wrapper for the consolidated ``Camera`` capability.
///
/// Obtain one via `-[MWDATDeviceSession addCameraWithError:]` /
/// `-[MWDATDeviceSession addCameraWithConfig:error:]`. The camera owns its child features; use
/// ``stream`` for video streaming, and ``stop()`` to tear the camera down (cascading to its
/// children and detaching from the session).
@objc(MWDATCamera) final public class ObjC_Camera : NSObject, Sendable {

    /// The video streaming child, owned by this camera.
    @objc final public let stream: MWDATCamera.ObjC_Stream

    /// Stops this camera and its child features, releasing resources and detaching from the parent
    /// session. Calling ``stop()`` on an already-stopped camera is a no-op.
    @objc final public func stop()

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

    /// Stops video streaming and releases all resources.
    ///
    /// Shuts down the streaming pipeline and transitions to `.stopped` state.
    ///
    /// State transitions: Any state -> `.stopping` -> `.stopped`
    @objc final public func stop()

    /// Captures a still photo during streaming.
    ///
    /// Triggers a photo capture while video streaming is active. The captured photo is delivered
    /// through the photo data listener. Video streaming is temporarily paused during capture and
    /// automatically resumes after photo delivery.
    ///
    /// - Parameter format: The desired image format.
    /// - Returns: `true` if the capture request was accepted, `false` if no device session is
    ///   active, no high-bandwidth link lease (BTC or WiFi) is held, or a capture is already in
    ///   progress.
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

    /// Creates a new stream session configuration with specified parameters including audio.
    /// - Parameters:
    ///   - videoCodec: The video codec to use for streaming.
    ///   - resolution: The resolution for video streaming.
    ///   - frameRate: The target frame rate for streaming.
    ///   - audioCodec: The audio codec to use for streaming. Pass nil to disable audio.
    ///
    /// @Unpublishable
    @objc public init(videoCodec: MWDATCamera.ObjC_VideoCodec, resolution: MWDATCamera.ObjC_StreamingResolution, frameRate: Int, audioCodec: MWDATCamera.ObjC_AudioCodec?)

    @objc deinit
}

/// Errors that can occur during streaming sessions.
@objc(MWDATStreamError) public enum ObjC_StreamError : Int, Sendable {

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

    /// Audio streaming encountered an error.
    ///
    /// @Unpublishable
    case audioStreamingError

    /// Camera permission was denied.
    case permissionDenied

    /// The device hinges were closed during streaming.
    case hingesClosed

    /// Device thermal level is too high for streaming.
    case thermalHot

    /// Device battery is too low for streaming.
    case batteryLow

    /// Device peak power limit reached.
    case peakPowerLimit

    /// A photo capture did not complete — no image was returned in time (e.g. low device storage).
    case photoCaptureFailed

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

/// Captures high-quality still photos from a connected wearable device.
///
/// `Photo` is the entry point for photo capture. It provides ``start()`` and ``stop()`` to control
/// the capability lifecycle, ``capturePhoto(resolution:quality:)`` to trigger a photo capture on
/// the device, and publishers for observing state transitions, incoming photo data, transfer
/// progress, and errors.
///
/// > Important: Calling ``stop()`` while the capability is in the ``PhotoState/starting``
/// > state records the request and tears it down as soon as startup resolves, so a stop
/// > issued mid-startup is honored rather than dropped.
///
/// This class is `Sendable` and safe to use from any thread or task.
///
/// @Unpublishable
final public class Photo : Sendable {

    /// Publishes session lifecycle state changes, delivered asynchronously and in order. Retain the
    /// session until you observe the terminal ``PhotoState/stopped`` transition; a
    /// transition queued just before deallocation may not be delivered.
    final public var statePublisher: any MWDATCore.Announcer<MWDATCamera.PhotoState> { get }

    /// Publishes captured photo data received from the device.
    final public var photoDataPublisher: any MWDATCore.Announcer<MWDATCamera.PhotoCaptureData> { get }

    /// Publishes errors encountered during the session lifecycle or photo capture.
    final public var errorPublisher: any MWDATCore.Announcer<MWDATCamera.PhotoError> { get }

    /// Publishes file transfer progress for incoming captured photos.
    final public var transferProgressPublisher: any MWDATCore.Announcer<MWDATCamera.PhotoTransferProgress> { get }

    @objc deinit

    final public func start()

    /// Stops photo capture and tears down internal transports.
    ///
    /// When the session is ``PhotoState/started``, this tears down immediately.
    /// When it is still ``PhotoState/starting`` (the device has not yet confirmed
    /// capability activation), the stop is recorded and honored as soon as startup resolves — the
    /// session then transitions to ``PhotoState/stopped`` instead of
    /// ``PhotoState/started``, rather than the stop being dropped. Calling `stop()`
    /// while already ``PhotoState/stopping`` or ``PhotoState/stopped``
    /// is a no-op.
    final public func stop()

    /// Triggers a photo capture on the connected device.
    ///
    /// The session must be in the ``PhotoState/started`` state. If it is not,
    /// a ``PhotoError/notReady`` error is published.
    ///
    /// Both `resolution` and `quality` default to ``PhotoResolution/medium`` and
    /// ``PhotoQuality/medium`` respectively, which provides a good balance between
    /// image quality and battery consumption on the glasses. Higher settings increase
    /// processing time, file size, and battery drain.
    ///
    /// - Parameters:
    ///   - resolution: The capture resolution (size). Defaults to ``PhotoResolution/medium`` (720p).
    ///   - quality: The compression quality. Defaults to ``PhotoQuality/medium``.
    final public func capturePhoto(resolution: MWDATCamera.PhotoResolution = .medium, quality: MWDATCamera.PhotoQuality = .medium)
}

/// A photo captured from the connected wearable device.
///
/// @Unpublishable
public struct PhotoCaptureData : Sendable {

    /// The raw image bytes (e.g. JPEG or HEIC).
    public let imageData: Data

    /// Optional metadata associated with the capture (e.g. camera settings, orientation).
    public let metadata: Data?

    /// The time the photo was received.
    public let timestamp: Date

    public init(imageData: Data, metadata: Data?, timestamp: Date)
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

/// Errors that can occur during the lifecycle of a ``Photo``.
///
/// @Unpublishable
public enum PhotoError : MWDATCore.DatError {

    /// The session is not in a valid state to perform the requested operation.
    case notReady

    /// A photo capture attempt failed. The `underlying` error contains transport-level details, if available.
    case captureFailure(underlying: (any Error)?)

    /// The session could not be started due to a transport setup failure.
    case sessionSetupFailed(underlying: (any Error)?)

    /// The device rejected the request because a capture is already in progress.
    case busy

    /// The device reported that its capture service is unavailable.
    case serviceUnavailable

    /// The device denied the capture because camera permission was not granted.
    case permissionDenied

    /// The device refused the capture because its thermal, power, or battery state is critical.
    case deviceHealthCritical

    /// The device disconnected.
    ///
    /// - Note: Not emitted yet. The case exists so the published API matches Android, which reports
    ///   this from its disconnect handler; the iOS emission path is tracked separately. Until then a
    ///   disconnect surfaces as ``captureFailure(underlying:)`` once the capture watchdog expires.
    case deviceDisconnected

    /// A human-readable description of the error suitable for logging, debugging,
    /// and display to developers. This should return the English version of the error.
    public var description: String { get }

    /// A localized message describing what error occurred.
    public var errorDescription: String? { get }
}

/// The compression quality to use when capturing a photo from the glasses camera.
///
/// - ``low``: Highest compression, smallest file size.
/// - ``medium``: Balanced compression and image quality.
/// - ``high``: Lowest compression, best image quality.
///
/// @Unpublishable
public enum PhotoQuality : String, CaseIterable, Sendable {

    case low

    case medium

    case high

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
    public typealias AllCases = [MWDATCamera.PhotoQuality]

    /// The raw type that can be used to represent all values of the conforming
    /// type.
    ///
    /// Every distinct value of the conforming type has a corresponding unique
    /// value of the `RawValue` type, but there may be values of the `RawValue`
    /// type that don't have a corresponding value of the conforming type.
    public typealias RawValue = String

    /// A collection of all values of this type.
    nonisolated public static var allCases: [MWDATCamera.PhotoQuality] { get }

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

extension PhotoQuality : Equatable {
}

extension PhotoQuality : Hashable {
}

extension PhotoQuality : RawRepresentable {
}

/// The resolution (size) to use when capturing a photo from the glasses camera.
///
/// - ``small``: 480p — smallest file size, fastest transfer.
/// - ``medium``: 720p — balanced size and transfer speed.
/// - ``large``: 1080p — high resolution capture.
/// - ``full``: Native sensor resolution (4032×3024) — highest resolution available.
///
/// @Unpublishable
public enum PhotoResolution : String, CaseIterable, Sendable {

    case small

    case medium

    case large

    case full

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
    public typealias AllCases = [MWDATCamera.PhotoResolution]

    /// The raw type that can be used to represent all values of the conforming
    /// type.
    ///
    /// Every distinct value of the conforming type has a corresponding unique
    /// value of the `RawValue` type, but there may be values of the `RawValue`
    /// type that don't have a corresponding value of the conforming type.
    public typealias RawValue = String

    /// A collection of all values of this type.
    nonisolated public static var allCases: [MWDATCamera.PhotoResolution] { get }

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

extension PhotoResolution : Equatable {
}

extension PhotoResolution : Hashable {
}

extension PhotoResolution : RawRepresentable {
}

/// The lifecycle state of a ``Photo``.
///
/// @Unpublishable
public enum PhotoState : Sendable {

    /// The capability is idle and not connected to the device.
    case stopped

    /// The capability is setting up internal transports.
    case starting

    /// The capability is active and ready to receive photos or accept capture commands.
    case started

    /// The capability is tearing down internal transports.
    case stopping

    /// Returns a Boolean value indicating whether two values are equal.
    ///
    /// Equality is the inverse of inequality. For any values `a` and `b`,
    /// `a == b` implies that `a != b` is `false`.
    ///
    /// - Parameters:
    ///   - lhs: A value to compare.
    ///   - rhs: Another value to compare.
    public static func == (a: MWDATCamera.PhotoState, b: MWDATCamera.PhotoState) -> Bool

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

extension PhotoState : Equatable {
}

extension PhotoState : Hashable {
}

/// Progress of a file transfer for a captured photo.
///
/// @Unpublishable
public struct PhotoTransferProgress : Sendable {

    public let bytesReceived: UInt64

    public let totalBytes: UInt64

    /// Transfer progress as a fraction between 0.0 and 1.0.
    public var fraction: Double { get }
}

/// A class for managing media streaming capabilities with Meta Wearables devices.
/// Handles video streaming and photo capture, and provides real-time state updates.
///
/// In Swift, create a ``Stream`` by first creating and starting a ``DeviceSession``,
/// then calling ``DeviceSession/addCamera(config:)`` and using ``Camera/stream``. The stream is attached to that
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

    /// Publisher for audio frames received from the streaming session.
    ///
    /// @Unpublishable
    final public var audioFramePublisher: any MWDATCore.Announcer<MWDATCamera.AudioFrame> { get }

    /// Publisher for photo data captured during the streaming session.
    final public var photoDataPublisher: any MWDATCore.Announcer<MWDATCamera.PhotoData> { get }

    /// Publisher for errors that occur during the streaming session.
    final public var errorPublisher: any MWDATCore.Announcer<MWDATCamera.StreamError> { get }

    @objc deinit

    /// Starts video streaming from the session's device.
    ///
    /// Begins streaming video frames from the device the parent ``DeviceSession`` was created for.
    /// Video frames are delivered through ``videoFramePublisher``.
    ///
    /// State transitions: `.stopped` -> `.waitingForDevice` (transient) -> `.starting` ->
    /// `.streaming`. If the device is unknown to the device manager or has no active connection
    /// when `start()` runs, the session emits ``StreamError/deviceNotFound(_:)`` or
    /// ``StreamError/deviceNotConnected(_:)`` and returns to `.stopped`.
    ///
    /// The session automatically stops when an error occurs or when the parent session ends
    /// externally (e.g., device powered off).
    ///
    /// Errors published to ``errorPublisher``:
    /// - ``StreamError/deviceNotFound(_:)``
    /// - ``StreamError/deviceNotConnected(_:)``
    /// - ``StreamError/timeout``
    /// - ``StreamError/permissionDenied``
    /// - ``StreamError/hingesClosed``
    /// - ``StreamError/internalError``
    final public func start()

    /// Stops video streaming and releases all resources.
    ///
    /// Shuts down the streaming pipeline and transitions to the `.stopped` state.
    ///
    /// State transitions: Any state -> `.stopping` -> `.stopped`
    final public func stop()

    /// Captures a still photo during streaming.
    ///
    /// Triggers a photo capture while video streaming is active. The captured photo is delivered
    /// through ``photoDataPublisher``. Video streaming is temporarily paused during capture and
    /// automatically resumes after photo delivery.
    ///
    /// - Parameter format: The desired image format.
    /// - Returns: `true` if the capture request was accepted, `false` if no device session is
    ///   active, no high-bandwidth link lease (BTC or WiFi) is held, a capture is already in
    ///   progress, or the underlying capture request fails.
    @discardableResult
    final public func capturePhoto(format: MWDATCamera.PhotoCaptureFormat) -> Bool
}

/// Configuration for a media streaming session with a Meta Wearables device.
/// Defines video codec, resolution, frame delivery strategy, and target frame rate.
public struct StreamConfiguration : Sendable {

    /// The video codec to use for streaming.
    public let videoCodec: MWDATCamera.VideoCodec

    /// The audio codec (optional) to use for streaming.
    ///
    /// @Unpublishable
    public let audioCodec: MWDATCamera.AudioCodec?

    /// The resolution at which to stream video content.
    public let resolution: MWDATCamera.StreamingResolution

    /// The target frame rate for the streaming session.
    public let frameRate: UInt

    /// Creates a new stream session configuration with specified parameters including audio.
    /// - Parameters:
    ///   - videoCodec: The video codec to use for streaming.
    ///   - audioCodec: The audio codec to use for streaming.
    ///   - resolution: The resolution for video streaming.
    ///   - frameRate: The target frame rate for streaming.
    ///
    /// @Unpublishable
    public init(videoCodec: MWDATCamera.VideoCodec, audioCodec: MWDATCamera.AudioCodec?, resolution: MWDATCamera.StreamingResolution, frameRate: UInt)

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
public enum StreamError : MWDATCore.DatError, Equatable {

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

    /// Audio streaming encountered an error.
    ///
    /// @Unpublishable
    case audioStreamingError

    /// Camera permission was denied.
    case permissionDenied

    /// The device hinges were closed during streaming.
    case hingesClosed

    /// Device thermal level is too high for streaming.
    case thermalHot

    /// Device battery is too low for streaming.
    case batteryLow

    /// Device peak power limit reached.
    case peakPowerLimit

    /// A photo capture did not complete — no image was returned in time. This commonly indicates low
    /// device storage or another capture already in progress; the stream itself continues.
    case photoCaptureFailed

    /// A description of the error
    public var description: String { get }

    /// A localized message describing what error occurred.
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

/// Valid Live Streaming resolutions. We are using a 9:16 aspect ratio.
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
    ///   When the app enters the background, frame delivery stops. Use ``hvc1`` if you
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

    /// Creates and adds a consolidated ``Camera`` to this device session.
    ///
    /// The returned ``Camera`` owns the camera hardware resource and exposes its child features
    /// (``Camera/stream`` and the `@Unpublishable` ``Camera/photo``). The camera is registered as a
    /// capability of this session and is automatically stopped when the session stops. A terminal
    /// child-stream failure stops and detaches the camera, allowing a subsequent call to add a
    /// replacement.
    ///
    /// The device session must be in ``DeviceSessionState/started`` state; adding a camera to a
    /// session that has not started yet returns `nil`.
    ///
    /// - Parameter config: Configuration applied to the camera's child stream (video codec,
    ///   resolution, frame rate). Defaults to ``StreamConfiguration()``.
    /// - Returns: A ``Camera`` added to this device session, or `nil` if the session is not in the
    ///   started state.
    /// - Throws: ``DeviceSessionError/capabilityAlreadyActive`` if a camera is already attached.
    final public func addCamera(config: MWDATCamera.StreamConfiguration = StreamConfiguration()) throws(MWDATCore.DeviceSessionError) -> MWDATCamera.Camera?
}

extension NSNotification.Name {

    /// Posted when a ``Stream`` is created — now via ``DeviceSession/addCamera(config:)`` (the object
    /// is the camera's ``Camera/stream``). Stream observers (e.g. MWDATDebugServer) use this to
    /// auto-discover streams.
    public static let mwdatStreamSessionCreated: Notification.Name
}

extension ObjC_DeviceSession {

    /// Creates a consolidated camera capability with the default configuration.
    ///
    /// Returns `nil` without setting `error` when the device session is not started yet.
    @objc(addCameraWithError:) final public func addCamera(_ error: NSErrorPointer = nil) -> MWDATCamera.ObjC_Camera?

    /// Creates a consolidated camera capability with the provided stream configuration.
    ///
    /// Returns `nil` without setting `error` when the device session is not started yet.
    @objc(addCameraWithConfig:error:) final public func addCamera(config: MWDATCamera.ObjC_StreamConfiguration, error: NSErrorPointer = nil) -> MWDATCamera.ObjC_Camera?
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

