import 'dart:async';

import 'package:flutter_meta_wearables_dat_mock_device/flutter_meta_wearables_dat_mock_device_platform_interface.dart';

/// Permissions that can be overridden on a mock device.
///
/// Currently only camera is exposed; the enum is designed to grow as
/// additional permissions are surfaced by the SDK.
enum Permission {
  camera('camera');

  const Permission(this.value);

  /// String value sent over the platform channel.
  final String value;
}

/// The current status of a [Permission].
enum PermissionStatus {
  granted('granted'),
  denied('denied');

  const PermissionStatus(this.value);

  /// String value sent over the platform channel.
  final String value;
}

/// Which phone camera to use when streaming into a mock device.
enum CameraFacing {
  front('front'),
  back('back');

  const CameraFacing(this.value);

  /// String value sent over the platform channel.
  final String value;
}

/// Public façade for the optional MockDeviceKit add-on.
///
/// MockDeviceKit lets you exercise the full registration / pairing / streaming
/// flow without a physical pair of Ray-Ban Meta glasses by simulating a
/// device backed by the phone's camera. Because that linkage pulls in
/// `AVFoundation` (iOS) and `CAMERA` (Android), this package is intentionally
/// optional — depend on it only in builds where you need mock devices
/// (development, CI, internal demos).
class MetaWearablesDatMockDevice {
  /// Configures the mock device subsystem.
  ///
  /// Call before [pairRayBanMeta] to simulate specific registration /
  /// permission states. Calling this after devices have been paired tears
  /// down the existing mock state and re-enables MockDeviceKit with the new
  /// configuration.
  ///
  /// - [initiallyRegistered] — when `false`, the SDK behaves as if the user
  ///   has not yet registered, so `startRegistration` can be exercised.
  /// - [initialPermissionsGranted] — when `false`, all permissions start in
  ///   the `denied` state and must be granted explicitly (via
  ///   [setPermission] or by simulating a `requestPermission` flow).
  static Future<bool> configure({
    bool initiallyRegistered = true,
    bool initialPermissionsGranted = true,
  }) {
    return MetaWearablesDatMockDevicePlatform.instance.configure(
      initiallyRegistered: initiallyRegistered,
      initialPermissionsGranted: initialPermissionsGranted,
    );
  }

  /// Disables the mock device subsystem and unpairs any paired mock devices.
  static Future<bool> disable() {
    return MetaWearablesDatMockDevicePlatform.instance.disable();
  }

  /// Pairs a mock RayBan Meta device. Returns the new device's UUID.
  static Future<String?> pairRayBanMeta() {
    return MetaWearablesDatMockDevicePlatform.instance.pairRayBanMeta();
  }

  /// Unpairs a previously paired mock RayBan Meta device.
  static Future<bool> unpairRayBanMeta(String deviceUUID) {
    return MetaWearablesDatMockDevicePlatform.instance.unpairRayBanMeta(
      deviceUUID,
    );
  }

  /// Overrides the status returned by `checkPermissionStatus` for a given
  /// [permission] on mock devices.
  ///
  /// Use together with [configure] to test permission-gated code paths
  /// (e.g. granted vs denied).
  ///
  /// **iOS only.** The Android mock SDK has no programmatic
  /// permission-injection hook, so this is a no-op there (returns `true`
  /// without changing any state).
  static Future<bool> setPermission(
    Permission permission,
    PermissionStatus status,
  ) {
    return MetaWearablesDatMockDevicePlatform.instance.setPermission(
      permission,
      status,
    );
  }

  /// Configures the result that a subsequent `requestPermission` call will
  /// return for a given [permission] on mock devices.
  ///
  /// **iOS only.** The Android mock SDK has no programmatic
  /// permission-injection hook, so this is a no-op there (returns `true`
  /// without changing any state).
  static Future<bool> setPermissionRequestResult(
    Permission permission,
    PermissionStatus status,
  ) {
    return MetaWearablesDatMockDevicePlatform.instance
        .setPermissionRequestResult(permission, status);
  }

  /// Powers on a mock RayBan Meta device.
  static Future<bool> powerOn(String deviceUUID) {
    return MetaWearablesDatMockDevicePlatform.instance.powerOn(deviceUUID);
  }

  /// Powers off a mock RayBan Meta device.
  static Future<bool> powerOff(String deviceUUID) {
    return MetaWearablesDatMockDevicePlatform.instance.powerOff(deviceUUID);
  }

  /// Simulates putting on (donning) a mock RayBan Meta device.
  static Future<bool> don(String deviceUUID) {
    return MetaWearablesDatMockDevicePlatform.instance.don(deviceUUID);
  }

  /// Simulates taking off (doffing) a mock RayBan Meta device.
  static Future<bool> doff(String deviceUUID) {
    return MetaWearablesDatMockDevicePlatform.instance.doff(deviceUUID);
  }

  /// Streams an HEVC/H.265 video file as the mock device's camera feed.
  /// Pass `null` to clear the source.
  static Future<bool> setCameraFeed(String deviceUUID, String? videoPath) {
    return MetaWearablesDatMockDevicePlatform.instance.setCameraFeed(
      deviceUUID,
      videoPath,
    );
  }

  /// Streams the phone's front or back camera into the mock device.
  ///
  /// Mutually exclusive with [setCameraFeed] — calling either clears
  /// the source configured by the other.
  static Future<bool> setCameraFacing(
    String deviceUUID,
    CameraFacing facing,
  ) {
    return MetaWearablesDatMockDevicePlatform.instance.setCameraFacing(
      deviceUUID,
      facing,
    );
  }

  /// Sets the still image returned by `capturePhoto` on the mock device.
  /// Pass `null` to clear it.
  static Future<bool> setCapturedImage(String deviceUUID, String? imagePath) {
    return MetaWearablesDatMockDevicePlatform.instance.setCapturedImage(
      deviceUUID,
      imagePath,
    );
  }
}
