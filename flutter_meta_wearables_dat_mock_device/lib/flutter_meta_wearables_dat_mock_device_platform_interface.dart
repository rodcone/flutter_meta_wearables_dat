// ignore_for_file: public_member_api_docs

import 'dart:async';

import 'package:flutter_meta_wearables_dat_mock_device/flutter_meta_wearables_dat_mock_device.dart';
import 'package:flutter_meta_wearables_dat_mock_device/flutter_meta_wearables_dat_mock_device_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

abstract class MetaWearablesDatMockDevicePlatform extends PlatformInterface {
  /// Constructs a MetaWearablesDatMockDevicePlatform.
  MetaWearablesDatMockDevicePlatform() : super(token: _token);

  static final Object _token = Object();

  static MetaWearablesDatMockDevicePlatform _instance =
      MethodChannelMetaWearablesDatMockDevice();

  /// The default instance of [MetaWearablesDatMockDevicePlatform] to use.
  ///
  /// Defaults to [MethodChannelMetaWearablesDatMockDevice].
  static MetaWearablesDatMockDevicePlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [MetaWearablesDatMockDevicePlatform]
  /// when they register themselves.
  static set instance(MetaWearablesDatMockDevicePlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<bool> configure({
    bool initiallyRegistered = true,
    bool initialPermissionsGranted = true,
  }) {
    throw UnimplementedError('configure() has not been implemented.');
  }

  Future<bool> disable() {
    throw UnimplementedError('disable() has not been implemented.');
  }

  Future<String?> pairGlasses({GlassesModel model = GlassesModel.rayBanMeta}) {
    throw UnimplementedError('pairGlasses() has not been implemented.');
  }

  Future<bool> unpairGlasses(String deviceUUID) {
    throw UnimplementedError('unpairGlasses() has not been implemented.');
  }

  Future<bool> setPermission(Permission permission, PermissionStatus status) {
    throw UnimplementedError('setPermission() has not been implemented.');
  }

  Future<bool> setPermissionRequestResult(
    Permission permission,
    PermissionStatus status,
  ) {
    throw UnimplementedError(
      'setPermissionRequestResult() has not been implemented.',
    );
  }

  Future<bool> powerOn(String deviceUUID) {
    throw UnimplementedError('powerOn() has not been implemented.');
  }

  Future<bool> powerOff(String deviceUUID) {
    throw UnimplementedError('powerOff() has not been implemented.');
  }

  Future<bool> don(String deviceUUID) {
    throw UnimplementedError('don() has not been implemented.');
  }

  Future<bool> doff(String deviceUUID) {
    throw UnimplementedError('doff() has not been implemented.');
  }

  Future<bool> setCameraFeed(String deviceUUID, String? videoPath) {
    throw UnimplementedError('setCameraFeed() has not been implemented.');
  }

  Future<bool> setCameraFacing(String deviceUUID, CameraFacing facing) {
    throw UnimplementedError('setCameraFacing() has not been implemented.');
  }

  Future<bool> setCapturedImage(String deviceUUID, String? imagePath) {
    throw UnimplementedError('setCapturedImage() has not been implemented.');
  }
}
