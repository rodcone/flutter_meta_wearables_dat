import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_meta_wearables_dat/meta_wearables_dat_platform_interface.dart';

/// Represents the current state of user registration with the Meta Wearables platform.
enum RegistrationState {
  /// Registration is not available, typically due to system constraints.
  unavailable(0),

  /// Registration is available and can be initiated.
  available(1),

  /// Registration process is in progress.
  registering(2),

  /// User is successfully registered with the platform.
  registered(3);

  const RegistrationState(this.value);

  /// The value of the registration state.
  final int value;

  /// Converts an integer value to a registration state.
  static RegistrationState fromInt(int value) {
    return RegistrationState.values.firstWhere(
      (state) => state.value == value,
      orElse: () => RegistrationState.unavailable,
    );
  }
}

/// Video codec to use for streaming.
enum VideoCodec {
  /// Raw decompressed video frames.
  /// iOS delivers BGRA via `CMSampleBufferGetImageBuffer`; Android delivers
  /// I420 converted to ARGB. The only codec supported on Android.
  raw('raw'),

  /// Compressed HEVC video frames (hvc1). iOS only.
  /// Decoded to BGRA via `VTDecompressionSession` (hardware). The decoder is
  /// invalidated on background entry (iOS forbids GPU access from backgrounded
  /// apps) and lazily recreated on the first frame after foreground — there's
  /// a brief keyframe-wait stall on resume. Raw hvc1 NAL bytes continue to
  /// flow on [MetaWearablesDat.videoFramesStream] while backgrounded if
  /// [MetaWearablesDat.enableBackgroundStreaming] was called.
  hvc1('hvc1');

  const VideoCodec(this.value);

  /// String value sent over the platform channel.
  final String value;
}

/// Supported streaming quality levels.
enum StreamQuality {
  /// High quality stream (best image quality, highest bandwidth/CPU).
  high('high'),

  /// Medium quality stream (balanced quality/performance).
  medium('medium'),

  /// Low quality stream (lowest bandwidth/CPU usage).
  low('low');

  const StreamQuality(this.value);

  /// String value sent over the platform channel.
  final String value;
}

/// Represents the current state of a stream session.
enum StreamSessionState {
  /// The session is in the process of stopping.
  stopping(0),

  /// The session is completely stopped.
  stopped(1),

  /// The session is waiting for a device to become available.
  waitingForDevice(2),

  /// The session is in the process of starting.
  starting(3),

  /// The session is actively streaming.
  streaming(4),

  /// The session is temporarily paused.
  paused(5);

  const StreamSessionState(this.value);

  /// The integer value of the state.
  final int value;

  /// Converts an integer value to a stream session state.
  static StreamSessionState fromInt(int value) {
    return StreamSessionState.values.firstWhere(
      (state) => state.value == value,
      orElse: () => StreamSessionState.stopped,
    );
  }
}

/// Represents an error that occurred during a stream session.
class StreamSessionError {
  /// The error code identifying the type of error.
  ///
  /// **Stream-level codes** (originate from the DAT SDK's `StreamError`):
  /// `internalError`, `deviceNotFound`, `deviceNotConnected`, `timeout`,
  /// `videoStreamingError`, `permissionDenied`, `hingesClosed`,
  /// `thermalCritical`, `thermalEmergency`, `peakPowerShutdown`,
  /// `batteryCritical`.
  ///
  /// **Device-session codes** (originate from the SDK's `DeviceSessionError`,
  /// surfaced on the same channel so consumers don't need a second
  /// subscription): `noEligibleDevice`, `sessionAlreadyStopped`,
  /// `sessionAlreadyExists`, `sessionIdle`, `capabilityAlreadyActive`,
  /// `capabilityNotFound`, `unexpectedError`, `deviceThermalCritical`,
  /// `deviceThermalEmergency`, `devicePeakPowerShutdown`,
  /// `deviceBatteryCritical`, `datAppOnTheGlassesUpdateRequired`,
  /// `dwaUnavailable`.
  ///
  /// When this is `datAppOnTheGlassesUpdateRequired`, call
  /// [MetaWearablesDat.openDATGlassesAppUpdate] to prompt the user to update
  /// the DAT app on the glasses — streaming won't work until they do.
  final String code;

  /// A human-readable description of the error.
  final String message;

  const StreamSessionError({required this.code, required this.message});

  /// Returns true if the device's thermal state has reached a critical level.
  bool get isThermalCritical => code == 'thermalCritical';

  /// Returns true if the device hinges were closed.
  bool get isHingesClosed => code == 'hingesClosed';

  /// Returns true if camera permission was denied.
  bool get isPermissionDenied => code == 'permissionDenied';

  @override
  String toString() => 'StreamSessionError($code): $message';
}

/// Per-device thermal state reported by the DAT SDK.
///
/// Values escalate from [none] (cool) up to [shutdown] (the device is forced
/// off). Streaming-affecting transitions also surface as
/// [StreamSessionError]s (`thermalCritical` / `thermalEmergency` / etc.) on
/// [MetaWearablesDat.streamSessionErrorStream] — use this stream when you
/// want to react *before* streaming has to stop (e.g. show a "device is
/// getting hot" hint at [moderate] or [severe]).
enum ThermalLevel {
  /// State not yet known (no reading from the device).
  unknown(0),

  /// Cool — no thermal concerns.
  none(1),

  /// Slightly warm. Safe.
  light(2),

  /// Warming up. Still safe but worth surfacing in UI.
  moderate(3),

  /// Hot. Streaming may degrade soon.
  severe(4),

  /// Critical — DAT will pause streaming shortly.
  critical(5),

  /// Emergency — streaming has already been stopped to protect the device.
  emergency(6),

  /// Device has shut down due to thermal overload.
  shutdown(7);

  const ThermalLevel(this.value);

  /// Integer value sent over the platform channel.
  final int value;

  /// Converts an integer value to a thermal level.
  static ThermalLevel fromInt(int value) {
    return ThermalLevel.values.firstWhere(
      (level) => level.value == value,
      orElse: () => ThermalLevel.unknown,
    );
  }
}

/// Snapshot of per-device state emitted by
/// [MetaWearablesDat.deviceStateStream].
///
/// Currently carries only [thermalLevel]; this is a value type rather than a
/// raw `ThermalLevel` so additional state fields can be added later without
/// breaking the public API.
@immutable
class DeviceState {
  const DeviceState({required this.thermalLevel});

  /// Current thermal level of the active device.
  final ThermalLevel thermalLevel;

  @override
  String toString() => 'DeviceState(thermalLevel: $thermalLevel)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeviceState && other.thermalLevel == thermalLevel;

  @override
  int get hashCode => thermalLevel.hashCode;
}

/// Dimensions of the active video stream, reported from the native layer
/// when a new stream starts or the underlying frame size changes.
///
/// Use [aspectRatio] when sizing the `Texture` widget so landscape or
/// portrait frames aren't stretched into a hardcoded container.
class VideoStreamSize {
  const VideoStreamSize({required this.width, required this.height});

  final int width;
  final int height;

  double get aspectRatio => height == 0 ? 1 : width / height;

  @override
  String toString() => 'VideoStreamSize(${width}x$height)';
}

/// Supported photo capture formats.
enum PhotoCaptureFormat {
  /// HEIC format — better compression than JPEG.
  heic('heic'),

  /// JPEG format — widely supported.
  jpeg('jpeg');

  const PhotoCaptureFormat(this.value);

  /// String value sent over the platform channel.
  final String value;
}

/// Supported pixel formats for captured stream frames.
///
/// These map to Flutter's [ui.ImageByteFormat] values internally.
enum FrameFormat {
  /// Raw RGBA pixel data (4 bytes per pixel, pre-multiplied alpha).
  /// Best for ML inference and image processing pipelines.
  rawRgba,

  /// Raw RGBA pixel data with straight (non-pre-multiplied) alpha.
  rawStraightRgba,

  /// PNG-encoded image data.
  /// Larger than raw formats but widely compatible.
  png,
}

/// Exception thrown when a camera permission request fails.
class CameraPermissionException implements Exception {
  /// The error code from the native SDK.
  final String code;

  /// The error message describing what went wrong.
  final String message;

  /// Additional error details (e.g., errorType).
  final Map<String, dynamic>? details;

  const CameraPermissionException({
    required this.code,
    required this.message,
    this.details,
  });

  /// Returns true when the request failed because no Ray-Ban Meta device was
  /// reachable (powered off, out of Bluetooth range, or the Meta AI app
  /// reports no connection).
  bool get isDeviceDisconnected => code == 'DEVICE_DISCONNECTED';

  /// Reserved for cases where the SDK surfaces a denial as an exception.
  /// In the current SDK a user denying the prompt is *not* an error — it
  /// returns `false` from [MetaWearablesDat.requestCameraPermission].
  /// Treat a `false` return as denial; this predicate stays for forward
  /// compatibility.
  bool get isPermissionDenied => code == 'PERMISSION_DENIED';

  /// Returns true for any other SDK-side failure (request already in
  /// progress, timeout, Meta AI app not installed, generic internal error,
  /// or an unrecognized error type).
  bool get isInternalError => code == 'INTERNAL_ERROR';

  @override
  String toString() => 'CameraPermissionException($code): $message';
}

/// Represents a photo captured from a Meta Wearables device.
class CapturedPhoto {
  /// The bytes of the captured photo.
  final Uint8List bytes;

  /// The format of the captured photo.
  final String format;

  const CapturedPhoto({required this.bytes, required this.format});

  String get fileExtension => format == 'heic' ? 'heic' : 'jpg';

  String get mimeType => format == 'heic' ? 'image/heic' : 'image/jpeg';
}

/// A single video frame captured from an active stream session's Flutter
/// texture.
///
/// [CapturedFrame] is captured silently on the Dart side by rasterizing the
/// Flutter texture. The pixel data is suitable for OCR, ML inference, or any
/// image processing that needs raw frame access.
class CapturedFrame {
  /// The raw pixel data of the captured frame.
  ///
  /// The encoding depends on the [format] used during capture:
  /// - [FrameFormat.rawRgba] / [FrameFormat.rawStraightRgba]: 4 bytes per
  ///   pixel (R, G, B, A), total size = [width] * [height] * 4.
  /// - [FrameFormat.png]: PNG-encoded image data.
  final Uint8List bytes;

  /// The width of the captured frame in pixels.
  final int width;

  /// The height of the captured frame in pixels.
  final int height;

  /// The pixel format of [bytes].
  final FrameFormat format;

  const CapturedFrame({
    required this.bytes,
    required this.width,
    required this.height,
    required this.format,
  });
}

/// Notification shown by the Android foreground service that keeps the
/// stream alive while the app is backgrounded. Required on Android; ignored
/// on iOS.
class BackgroundNotification {
  const BackgroundNotification({
    required this.title,
    required this.text,
    required this.channelId,
    required this.channelName,
    this.iconResourceName,
  });

  /// Notification title (bold line).
  final String title;

  /// Notification body.
  final String text;

  /// Unique notification channel id. Reuse the same value across calls to
  /// avoid re-creating the channel.
  final String channelId;

  /// User-visible channel name shown in Android settings.
  final String channelName;

  /// Drawable resource name for the small icon, e.g. `"ic_stat_recording"`.
  /// When null, the app's launcher icon is used.
  final String? iconResourceName;

  Map<String, dynamic> toMap() => <String, dynamic>{
    'title': title,
    'text': text,
    'channelId': channelId,
    'channelName': channelName,
    if (iconResourceName != null) 'iconResourceName': iconResourceName,
  };
}

/// A single video frame delivered over the platform channel.
///
/// Emitted by [MetaWearablesDat.videoFramesStream] in both foreground and
/// background once [MetaWearablesDat.enableBackgroundStreaming] has been
/// called. For preview rendering you still want the zero-copy `Texture`
/// returned by [MetaWearablesDat.startStreamSession] — this stream is meant
/// for recording or custom processing.
class VideoFrame {
  const VideoFrame({
    required this.codec,
    required this.bytes,
    required this.width,
    required this.height,
    required this.presentationTimestampUs,
    required this.isKeyframe,
    this.bytesPerRow,
  });

  /// The codec the bytes are in.
  ///
  /// - [VideoCodec.raw] — platform-specific decoded pixel layout:
  ///   - **iOS**: 32-bit BGRA, length `bytesPerRow * height` (may contain
  ///     row padding — use [bytesPerRow] when iterating rows).
  ///   - **Android**: I420 planar YUV (3 planes: Y, U, V) at
  ///     `width * height * 3 / 2` bytes. This is the SDK's native frame
  ///     format — forwarded as-is for zero-overhead recording. Convert
  ///     on the Dart side or feed directly into an encoder that accepts
  ///     YUV (FFmpeg, MediaCodec, etc.).
  /// - [VideoCodec.hvc1] — HEVC (`hvc1`) compressed sample. Parameter sets
  ///   (VPS/SPS/PPS) are carried on keyframes (`isKeyframe == true`).
  ///   Ready to be written into an `mp4` track as-is, or decoded by
  ///   VideoToolbox / MediaCodec. iOS only.
  final VideoCodec codec;

  /// The frame bytes. Ownership transfers to the listener; the plugin
  /// does not retain the buffer after emission.
  final Uint8List bytes;
  final int width;
  final int height;

  /// Monotonic presentation timestamp in microseconds. Stable across the
  /// lifetime of a single stream session.
  final int presentationTimestampUs;

  /// Always `true` for [VideoCodec.raw]. For [VideoCodec.hvc1] indicates
  /// whether this frame carries parameter sets and can be decoded without
  /// prior frames.
  final bool isKeyframe;

  /// Number of bytes per row for [VideoCodec.raw] frames on iOS — may be
  /// larger than `width * 4` due to row alignment. `null` on Android and
  /// for [VideoCodec.hvc1].
  final int? bytesPerRow;
}

/// The main class for the Meta Wearables DAT.
class MetaWearablesDat {
  /// Requests the Android runtime permissions required by the DAT SDK
  /// (Bluetooth, Internet). Returns true if all permissions are granted.
  /// No-op on iOS.
  static Future<bool> requestAndroidPermissions() {
    return MetaWearablesDatPlatform.instance.requestAndroidPermissions();
  }

  /// Requests camera permission.
  static Future<bool> requestCameraPermission() {
    return MetaWearablesDatPlatform.instance.requestCameraPermission();
  }

  /// Returns whether camera permission is currently granted.
  static Future<bool> getCameraPermissionStatus() {
    return MetaWearablesDatPlatform.instance.getCameraPermissionStatus();
  }

  /// Starts the registration process.
  static Future<bool> startRegistration() {
    return MetaWearablesDatPlatform.instance.startRegistration();
  }

  /// Handles a URL.
  static Future<bool> handleUrl(String url) {
    return MetaWearablesDatPlatform.instance.handleUrl(url);
  }

  /// Starts the unregistration (disconnect) process.
  /// Opens the Meta AI app where the user completes the flow; the callback
  /// URL must be passed to [handleUrl] to complete unregistration.
  static Future<bool> disconnect() {
    return MetaWearablesDatPlatform.instance.disconnect();
  }

  /// Starts a stream session with the given device UUID, FPS, and stream quality.
  ///
  /// Returns a texture ID for rendering via the Flutter `Texture` widget.
  /// Video frames are pushed directly from native to the GPU — no encoding,
  /// no byte copying, no Dart-side decoding.
  static Future<int> startStreamSession(
    String? deviceUUID, {
    double fps = 30.0,
    StreamQuality streamQuality = StreamQuality.high,
    VideoCodec videoCodec = VideoCodec.raw,
  }) {
    debugPrint(
      '[MetaWearablesDAT] Starting stream session with device UUID: $deviceUUID, FPS: $fps, Stream quality: $streamQuality, Video codec: $videoCodec',
    );
    return MetaWearablesDatPlatform.instance.startStreamSession(
      deviceUUID,
      fps: fps,
      streamQuality: streamQuality,
      videoCodec: videoCodec,
    );
  }

  /// Stops a stream session with the given device UUID.
  static Future<bool> stopStreamSession(String? deviceUUID) {
    return MetaWearablesDatPlatform.instance.stopStreamSession(deviceUUID);
  }

  /// Captures a photo from the active stream session.
  static Future<CapturedPhoto> capturePhoto(
    String? deviceUUID, {
    PhotoCaptureFormat format = PhotoCaptureFormat.jpeg,
  }) {
    debugPrint(
      '[MetaWearablesDAT] Capturing photo with device UUID: $deviceUUID, format: $format',
    );
    return MetaWearablesDatPlatform.instance.capturePhoto(
      deviceUUID,
      format: format,
    );
  }

  /// Captures a single frame from an active stream session's Flutter texture.
  ///
  /// This is a **Dart-side** operation that rasterizes the texture identified
  /// by [textureId] (returned by [startStreamSession]) into pixel data.
  /// No native code is invoked and the capture is near-instantaneous.
  ///
  /// Use this when you need raw frame bytes for OCR, ML inference, computer
  /// vision, or any processing that requires direct pixel access.
  ///
  /// **Note:** Raw RGBA at the default 720x1280 resolution is ~3.7 MB per
  /// frame. This method is intended for on-demand captures (e.g., every
  /// 200-500 ms), not continuous per-frame processing.
  ///
  /// Returns a [CapturedFrame] containing the pixel data, or `null` if the
  /// capture failed (e.g., texture not available).
  static Future<CapturedFrame?> captureStreamFrame(
    int textureId, {
    int width = 720,
    int height = 1280,
    FrameFormat format = FrameFormat.rawRgba,
  }) async {
    final builder = ui.SceneBuilder()
      ..addTexture(
        textureId,
        width: width.toDouble(),
        height: height.toDouble(),
        freeze: true,
        filterQuality: ui.FilterQuality.high,
      );
    final scene = builder.build();
    try {
      final image = await scene.toImage(width, height);
      try {
        final imageByteFormat = switch (format) {
          FrameFormat.rawRgba => ui.ImageByteFormat.rawRgba,
          FrameFormat.rawStraightRgba => ui.ImageByteFormat.rawStraightRgba,
          FrameFormat.png => ui.ImageByteFormat.png,
        };
        final byteData = await image.toByteData(
          format: imageByteFormat,
        );
        if (byteData == null) return null;
        return CapturedFrame(
          bytes: byteData.buffer.asUint8List(),
          width: width,
          height: height,
          format: format,
        );
      } finally {
        image.dispose();
      }
    } finally {
      scene.dispose();
    }
  }

  /// Stream of stream session state changes.
  ///
  /// Emits state transitions such as `stopped`, `waitingForDevice`,
  /// `streaming`, `paused`, etc. Subscribe to this stream to update your
  /// UI based on the current session state.
  static Stream<StreamSessionState> streamSessionStateStream() {
    return MetaWearablesDatPlatform.instance.streamSessionStateStream();
  }

  /// Stream of stream session errors.
  ///
  /// Emits errors such as `thermalCritical` (device overheating),
  /// `hingesClosed`, `permissionDenied`, etc. Subscribe to this stream
  /// to handle errors during an active stream session.
  static Stream<StreamSessionError> streamSessionErrorStream() {
    return MetaWearablesDatPlatform.instance.streamSessionErrorStream();
  }

  /// Gets the current registration state.
  static Future<RegistrationState> getRegistrationState() async {
    final registrationState = await MetaWearablesDatPlatform.instance
        .getRegistrationState();
    debugPrint('[MetaWearablesDAT] Registration state: $registrationState');
    return registrationState;
  }

  /// Stream of registration state changes.
  static Stream<RegistrationState> registrationStateStream() {
    final registrationStateStream = MetaWearablesDatPlatform.instance
        .registrationStateStream();
    return registrationStateStream;
  }

  /// Stream of active device availability changes.
  /// Returns true when an active device is available, false otherwise.
  static Stream<bool> activeDeviceStream() {
    return MetaWearablesDatPlatform.instance.activeDeviceStream();
  }

  /// Stream of video frame dimensions for the active stream session.
  ///
  /// Emits once shortly after `startStreamSession` and again if the
  /// underlying source changes resolution. Use [VideoStreamSize.aspectRatio]
  /// with an `AspectRatio` widget wrapping the `Texture` so landscape
  /// footage isn't crammed into a portrait box (or vice versa).
  static Stream<VideoStreamSize> videoStreamSizeStream() {
    return MetaWearablesDatPlatform.instance.videoStreamSizeStream();
  }

  /// Restarts active device monitoring on Android.
  /// Call after registration completes so the plugin re-subscribes
  /// to the device flow and picks up newly available devices.
  /// No-op on iOS.
  static Future<bool> restartActiveDeviceMonitoring() {
    return MetaWearablesDatPlatform.instance.restartActiveDeviceMonitoring();
  }

  /// Enables background streaming.
  ///
  /// Call this BEFORE [startStreamSession] if you want the stream to survive
  /// the host app being backgrounded, the screen being locked, or the user
  /// switching apps. Safe to call again to reconfigure the Android
  /// notification; safe to call after [startStreamSession] too — the
  /// keep-alive mechanism engages immediately.
  ///
  /// **iOS** — activates an `AVAudioSession` in `.playAndRecord` /
  /// `.videoRecording` mode and switches the HEVC decoder to software so it
  /// survives background/foreground transitions. The host app's `Info.plist`
  /// must declare these `UIBackgroundModes`: `audio`, `bluetooth-central`,
  /// `bluetooth-peripheral`, `external-accessory`.
  ///
  /// **Android** — starts a foreground service with the given
  /// [androidNotification] and acquires a `PARTIAL_WAKE_LOCK`. The plugin
  /// manifest merges `FOREGROUND_SERVICE`,
  /// `FOREGROUND_SERVICE_CONNECTED_DEVICE`, and `WAKE_LOCK` into your
  /// `AndroidManifest.xml`. [androidNotification] must be provided on
  /// Android; passing `null` on Android throws.
  static Future<void> enableBackgroundStreaming({
    BackgroundNotification? androidNotification,
  }) {
    return MetaWearablesDatPlatform.instance.enableBackgroundStreaming(
      androidNotification: androidNotification,
    );
  }

  /// Disables background streaming.
  ///
  /// Deactivates the `AVAudioSession` on iOS and stops the foreground
  /// service / releases the wake lock on Android. Safe to call multiple
  /// times. Does NOT stop the active stream session; use
  /// [stopStreamSession] for that.
  static Future<void> disableBackgroundStreaming() {
    return MetaWearablesDatPlatform.instance.disableBackgroundStreaming();
  }

  /// Stream of per-frame [VideoFrame] events. Emitted whenever a Dart
  /// subscriber is attached — the native side short-circuits serialization
  /// when no listener is present, so there is zero per-frame cost for apps
  /// that don't need the feed.
  ///
  /// Use this when you want to record the stream to disk or run custom
  /// per-frame processing. For preview rendering, the zero-copy `Texture`
  /// returned by [startStreamSession] is always the right choice — it
  /// bypasses the platform channel.
  ///
  /// On iOS, frames keep flowing while the app is backgrounded only if
  /// [enableBackgroundStreaming] has been called (iOS otherwise suspends
  /// the underlying capture). On Android, [enableBackgroundStreaming] is
  /// what keeps the OS from killing the streaming process once the app
  /// leaves the foreground.
  static Stream<VideoFrame> videoFramesStream() {
    return MetaWearablesDatPlatform.instance.videoFramesStream();
  }

  /// Opens the Meta AI app to the DAT-app-update screen on the connected
  /// glasses. Call this in response to a
  /// `datAppOnTheGlassesUpdateRequired` error code on
  /// [streamSessionErrorStream] — streaming won't work until the user
  /// updates the on-device DAT app.
  ///
  /// Returns `true` if the navigation succeeded. Throws a `PlatformException`
  /// with code `metaAINotInstalled` if the Meta AI app isn't installed, or
  /// `notRegistered` if the app hasn't completed registration.
  static Future<bool> openDATGlassesAppUpdate() {
    return MetaWearablesDatPlatform.instance.openDATGlassesAppUpdate();
  }

  /// Stream of [DeviceState] snapshots for the active device.
  ///
  /// Currently emits whenever the device's [ThermalLevel] changes. Subscribe
  /// to drive thermal warnings in your UI — by the time a critical-level
  /// thermal error reaches [streamSessionErrorStream] the stream has already
  /// stopped, so reacting to [ThermalLevel.moderate] / [ThermalLevel.severe]
  /// gives you a chance to warn the user before that happens.
  ///
  /// The stream switches its underlying subscription automatically when the
  /// active device changes.
  static Stream<DeviceState> deviceStateStream() {
    return MetaWearablesDatPlatform.instance.deviceStateStream();
  }
}
