// ignore_for_file: public_member_api_docs

import 'dart:async';

import 'package:flutter_meta_wearables_dat/flutter_meta_wearables_dat.dart';
import 'package:flutter_meta_wearables_dat/meta_wearables_dat_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

abstract class MetaWearablesDatPlatform extends PlatformInterface {
  /// Constructs a MetaWearablesDatPlatform.
  MetaWearablesDatPlatform() : super(token: _token);

  static final Object _token = Object();

  static MetaWearablesDatPlatform _instance = MethodChannelMetaWearablesDat();

  /// The default instance of [MetaWearablesDatPlatform] to use.
  ///
  /// Defaults to [MethodChannelMetaWearablesDat].
  static MetaWearablesDatPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [MetaWearablesDatPlatform] when
  /// they register themselves.
  static set instance(MetaWearablesDatPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<bool> requestAndroidPermissions() {
    throw UnimplementedError(
      'requestAndroidPermissions() has not been implemented.',
    );
  }

  Future<bool> requestCameraPermission() {
    throw UnimplementedError(
      'requestCameraPermission() has not been implemented.',
    );
  }

  Future<bool> getCameraPermissionStatus() {
    throw UnimplementedError(
      'getCameraPermissionStatus() has not been implemented.',
    );
  }

  Future<bool> startRegistration() {
    throw UnimplementedError('startRegistration() has not been implemented.');
  }

  Future<bool> handleUrl(String url) {
    throw UnimplementedError('handleUrl() has not been implemented.');
  }

  Future<bool> disconnect() {
    throw UnimplementedError('disconnect() has not been implemented.');
  }

  /// Starts a stream session. Returns a texture ID (int) for rendering
  /// via the Flutter `Texture` widget (zero-copy path).
  Future<int> startStreamSession(
    String? deviceUUID, {
    double fps = 30.0,
    StreamQuality streamQuality = StreamQuality.high,
    VideoCodec videoCodec = VideoCodec.raw,
  }) {
    throw UnimplementedError('startStreamSession() has not been implemented.');
  }

  Future<bool> stopStreamSession(String? deviceUUID) {
    throw UnimplementedError('stopStreamSession() has not been implemented.');
  }

  Future<CapturedPhoto> capturePhoto(
    String? deviceUUID, {
    PhotoCaptureFormat format = PhotoCaptureFormat.jpeg,
  }) {
    throw UnimplementedError('capturePhoto() has not been implemented.');
  }

  Future<RegistrationState> getRegistrationState() {
    throw UnimplementedError(
      'getRegistrationState() has not been implemented.',
    );
  }

  Stream<RegistrationState> registrationStateStream() {
    throw UnimplementedError(
      'registrationStateStream() has not been implemented.',
    );
  }

  Stream<StreamSessionState> streamSessionStateStream() {
    throw UnimplementedError(
      'streamSessionStateStream() has not been implemented.',
    );
  }

  Stream<StreamSessionError> streamSessionErrorStream() {
    throw UnimplementedError(
      'streamSessionErrorStream() has not been implemented.',
    );
  }

  Stream<bool> activeDeviceStream() {
    throw UnimplementedError(
      'activeDeviceStream() has not been implemented.',
    );
  }

  Stream<VideoStreamSize> videoStreamSizeStream() {
    throw UnimplementedError(
      'videoStreamSizeStream() has not been implemented.',
    );
  }

  Future<bool> restartActiveDeviceMonitoring() {
    throw UnimplementedError(
      'restartActiveDeviceMonitoring() has not been implemented.',
    );
  }

  Future<void> enableBackgroundStreaming({
    BackgroundNotification? androidNotification,
  }) {
    throw UnimplementedError(
      'enableBackgroundStreaming() has not been implemented.',
    );
  }

  Future<void> disableBackgroundStreaming() {
    throw UnimplementedError(
      'disableBackgroundStreaming() has not been implemented.',
    );
  }

  Stream<VideoFrame> videoFramesStream() {
    throw UnimplementedError('videoFramesStream() has not been implemented.');
  }

  Future<bool> openDATGlassesAppUpdate() {
    throw UnimplementedError(
      'openDATGlassesAppUpdate() has not been implemented.',
    );
  }

  Stream<DeviceState> deviceStateStream() {
    throw UnimplementedError('deviceStateStream() has not been implemented.');
  }
}
