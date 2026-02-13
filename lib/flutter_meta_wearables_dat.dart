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
  static Future<int> startStreamSession(
    String? deviceUUID, {
    double fps = 30.0,
    StreamQuality streamQuality = StreamQuality.high,
  }) {
    debugPrint(
      '[MetaWearablesDAT] Starting stream session with device UUID: $deviceUUID, FPS: $fps, Stream quality: $streamQuality',
    );
    return MetaWearablesDatPlatform.instance.startStreamSession(
      deviceUUID,
      fps: fps,
      streamQuality: streamQuality,
    );
  }

  /// Stops a stream session with the given device UUID.
  static Future<bool> stopStreamSession(String? deviceUUID) {
    return MetaWearablesDatPlatform.instance.stopStreamSession(deviceUUID);
  }

  /// Captures a photo from the active stream session.
  static Future<CapturedPhoto> capturePhoto(String? deviceUUID) {
    debugPrint(
      '[MetaWearablesDAT] Capturing photo with device UUID: $deviceUUID',
    );
    return MetaWearablesDatPlatform.instance.capturePhoto(deviceUUID);
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

  /// Restarts active device monitoring on Android.
  /// Call after registration completes so the plugin re-subscribes
  /// to the device flow and picks up newly available devices.
  /// No-op on iOS.
  static Future<bool> restartActiveDeviceMonitoring() {
    return MetaWearablesDatPlatform.instance.restartActiveDeviceMonitoring();
  }
}
