import AVFoundation
import CoreMedia
import Foundation
import MWDATCore
import UIKit

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

/// A class for managing media streaming sessions with Meta Wearables devices.
/// Handles video streaming, photo capture, and provides real-time state updates.
final public class StreamSession : Sendable {

    /// The configuration used for this streaming session.
    final public let streamSessionConfig: MWDATCamera.StreamSessionConfig

    /// The current state of the streaming session.
    final public var state: MWDATCamera.StreamSessionState { get }

    /// Publisher for streaming session state changes.
    final public var statePublisher: any MWDATCore.Announcer<MWDATCamera.StreamSessionState> { get }

    /// Publisher for video frames received from the streaming session.
    final public var videoFramePublisher: any MWDATCore.Announcer<MWDATCamera.VideoFrame> { get }

    /// Publisher for photo data captured during the streaming session.
    final public var photoDataPublisher: any MWDATCore.Announcer<MWDATCamera.PhotoData> { get }

    /// Publisher for errors that occur during the streaming session.
    final public var errorPublisher: any MWDATCore.Announcer<MWDATCamera.StreamSessionError> { get }

    @objc deinit

    /// Creates a streaming session using the specified device selector.
    ///
    /// The session is created in `.stopped` state. Call ``start()`` to begin streaming.
    /// Uses the default ``StreamSessionConfig`` configuration.
    /// - Parameter deviceSelector: The device selector that determines which device to stream from. The selector's `activeDevice` can be nil initially.
    public convenience init(deviceSelector: any MWDATCore.DeviceSelector)

    /// Creates a streaming session with custom configuration.
    ///
    /// The session is created in `.stopped` state. Call ``start()`` to begin streaming.
    /// - Parameters:
    ///   - streamSessionConfig: Configuration specifying resolution, frame rate, and codec settings.
    ///   - deviceSelector: The device selector that determines which device to stream from.
    public convenience init(streamSessionConfig: MWDATCamera.StreamSessionConfig, deviceSelector: any MWDATCore.DeviceSelector)

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
    /// - ``StreamSessionError/deviceNotFound(_:)``
    /// - ``StreamSessionError/deviceNotConnected(_:)``
    /// - ``StreamSessionError/timeout``
    /// - ``StreamSessionError/permissionDenied``
    /// - ``StreamSessionError/hingesClosed``
    /// - ``StreamSessionError/internalError``
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

/// Configuration for a media streaming session with a Meta Wearables device.
/// Defines video codec, resolution, frame delivery strategy, and target frame rate.
public struct StreamSessionConfig : Sendable {

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
public enum StreamSessionError : Error, Equatable {

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

    /// Returns a Boolean value indicating whether two values are equal.
    ///
    /// Equality is the inverse of inequality. For any values `a` and `b`,
    /// `a == b` implies that `a != b` is `false`.
    ///
    /// - Parameters:
    ///   - lhs: A value to compare.
    ///   - rhs: Another value to compare.
    public static func == (a: MWDATCamera.StreamSessionError, b: MWDATCamera.StreamSessionError) -> Bool
}

/// Represents the current state of a media streaming session with a Meta Wearables device.
@frozen public enum StreamSessionState : Sendable {

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
    public static func == (a: MWDATCamera.StreamSessionState, b: MWDATCamera.StreamSessionState) -> Bool

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

extension StreamSessionState : Equatable {
}

extension StreamSessionState : Hashable {
}

extension StreamSessionState : BitwiseCopyable {
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

