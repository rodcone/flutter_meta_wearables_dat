import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/rendering.dart';
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
  /// Raw decompressed video frames (foreground only).
  /// When the app enters background, frame delivery stops.
  raw('raw'),

  /// Compressed HEVC video frames (hvc1).
  /// Frames are delivered in both foreground and background.
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
  /// Known codes: `internalError`, `deviceNotFound`, `deviceNotConnected`,
  /// `timeout`, `videoStreamingError`, `permissionDenied`, `hingesClosed`,
  /// `thermalCritical`.
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

  /// Returns true if the device is disconnected or powered off.
  bool get isDeviceDisconnected => code == 'DEVICE_DISCONNECTED';

  /// Returns true if the permission was denied by the user.
  bool get isPermissionDenied => code == 'PERMISSION_DENIED';

  /// Returns true if there was an internal SDK error.
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

/// The main class for the Meta Wearables DAT.
class MetaWearablesDat {
  /// Pairs a mock RayBan Meta device.
  static Future<String?> pairMockRayBanMeta() {
    return MetaWearablesDatPlatform.instance.pairMockRayBanMeta();
  }

  /// Unpairs a mock RayBan Meta device.
  static Future<bool> unpairMockRayBanMeta(String deviceUUID) {
    return MetaWearablesDatPlatform.instance.unpairMockRayBanMeta(deviceUUID);
  }

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

  /// Powers on a mock RayBan Meta device.
  static Future<bool> mockDevicePowerOn(String deviceUUID) {
    return MetaWearablesDatPlatform.instance.mockDevicePowerOn(deviceUUID);
  }

  /// Powers off a mock RayBan Meta device.
  static Future<bool> mockDevicePowerOff(String deviceUUID) {
    return MetaWearablesDatPlatform.instance.mockDevicePowerOff(deviceUUID);
  }

  /// Simulates putting on (donning) a mock RayBan Meta device.
  static Future<bool> mockDeviceDon(String deviceUUID) {
    return MetaWearablesDatPlatform.instance.mockDeviceDon(deviceUUID);
  }

  /// Simulates taking off (doffing) a mock RayBan Meta device.
  static Future<bool> mockDeviceDoff(String deviceUUID) {
    return MetaWearablesDatPlatform.instance.mockDeviceDoff(deviceUUID);
  }

  /// Sets the camera feed for the mock device.
  static Future<bool> setMockCameraFeed(String deviceUUID, String? videoPath) {
    return MetaWearablesDatPlatform.instance.setMockCameraFeed(
      deviceUUID,
      videoPath,
    );
  }

  /// Sets the captured image for the mock device.
  static Future<bool> setMockCapturedImage(
    String deviceUUID,
    String? imagePath,
  ) {
    return MetaWearablesDatPlatform.instance.setMockCapturedImage(
      deviceUUID,
      imagePath,
    );
  }

  /// Starts a stream session with the given device UUID, FPS, and stream quality.
  ///
  /// Returns a texture ID for rendering via the Flutter `Texture` widget.
  /// Video frames are pushed directly from native to the GPU — no encoding,
  /// no byte copying, no Dart-side decoding.
  ///
  /// Note: These frames do not update when your app is backgrounded.
  /// Use [captureStreamFrame] to get JPEG-encoded frame data that works
  /// in both foreground and background.
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

  /// Captures a single JPEG-encoded frame from the active stream session.
  ///
  /// Reads the latest pixel buffer directly from native memory and encodes
  /// it as JPEG. Unlike the Flutter `Texture` widget, the native pixel
  /// buffer remains accessible across background/foreground transitions.
  ///
  /// [quality] controls JPEG compression (1–100). Lower values produce
  /// smaller files at the cost of image fidelity. Defaults to 70.
  ///
  /// Returns a `Uint8List` containing JPEG image data suitable for network
  /// transmission, on-device ML inference, or display via `Image.memory()`.
  ///
  /// Returns `null` if no stream session is active or no frame is available.
  ///
  /// Throws [ArgumentError] if [quality] is outside the 1–100 range.
  static Future<Uint8List?> captureStreamFrame({int quality = 70}) {
    if (quality < 1 || quality > 100) {
      throw ArgumentError.value(
        quality,
        'quality',
        'Must be between 1 and 100',
      );
    }
    return MetaWearablesDatPlatform.instance.captureStreamFrame(
      quality: quality,
    );
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
    final registrationState =
        await MetaWearablesDatPlatform.instance.getRegistrationState();
    debugPrint('[MetaWearablesDAT] Registration state: $registrationState');
    return registrationState;
  }

  /// Stream of registration state changes.
  static Stream<RegistrationState> registrationStateStream() {
    final registrationStateStream =
        MetaWearablesDatPlatform.instance.registrationStateStream();
    return registrationStateStream;
  }

  /// Stream of active device availability changes.
  /// Returns true when an active device is available, false otherwise.
  static Stream<bool> activeDeviceStream() {
    return MetaWearablesDatPlatform.instance.activeDeviceStream();
  }

  /// Restarts active device monitoring on Android.
  /// Call after registration completes so the plugin re-subscribes
  /// to the device flow and picks up newly available devices.
  /// No-op on iOS.
  static Future<bool> restartActiveDeviceMonitoring() {
    return MetaWearablesDatPlatform.instance.restartActiveDeviceMonitoring();
  }
}
