import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_meta_wearables_dat/flutter_meta_wearables_dat.dart';
import 'package:flutter_meta_wearables_dat/meta_wearables_dat_platform_interface.dart';

/// An implementation of [MetaWearablesDatPlatform] that uses method channels.
class MethodChannelMetaWearablesDat extends MetaWearablesDatPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('flutter_meta_wearables_dat');

  /// The event channel used to receive registration state updates.
  @visibleForTesting
  final eventChannel = const EventChannel(
    'flutter_meta_wearables_dat/registration_state',
  );

  /// The event channel used to receive active device availability updates.
  @visibleForTesting
  final activeDeviceEventChannel = const EventChannel(
    'flutter_meta_wearables_dat/active_device',
  );

  /// The event channel used to receive stream session state updates.
  @visibleForTesting
  final streamSessionStateEventChannel = const EventChannel(
    'flutter_meta_wearables_dat/stream_session_state',
  );

  /// The event channel used to receive stream session errors.
  @visibleForTesting
  final streamSessionErrorEventChannel = const EventChannel(
    'flutter_meta_wearables_dat/stream_session_errors',
  );

  /// The event channel used to receive video frame dimensions for the
  /// active stream session.
  @visibleForTesting
  final videoStreamSizeEventChannel = const EventChannel(
    'flutter_meta_wearables_dat/video_stream_size',
  );

  /// The event channel used to receive per-frame video samples when
  /// background streaming is enabled.
  @visibleForTesting
  final videoFramesEventChannel = const EventChannel(
    'flutter_meta_wearables_dat/video_frames',
  );

  @override
  Future<bool> configureMockDevices({
    bool initiallyRegistered = true,
    bool initialPermissionsGranted = true,
  }) async {
    final ok = await methodChannel.invokeMethod<bool>('configureMockDevices', {
      'initiallyRegistered': initiallyRegistered,
      'initialPermissionsGranted': initialPermissionsGranted,
    });
    return ok ?? false;
  }

  @override
  Future<bool> disableMockDevices() async {
    final ok = await methodChannel.invokeMethod<bool>('disableMockDevices');
    return ok ?? false;
  }

  @override
  Future<String?> pairMockRayBanMeta() async {
    final deviceUUID = await methodChannel.invokeMethod<String>(
      'pairMockRayBanMeta',
    );
    return deviceUUID;
  }

  @override
  Future<bool> unpairMockRayBanMeta(String deviceUUID) async {
    final ok = await methodChannel.invokeMethod<bool>('unpairMockRayBanMeta', {
      'deviceUUID': deviceUUID,
    });
    return ok ?? false;
  }

  @override
  Future<bool> setMockPermission(
    Permission permission,
    PermissionStatus status,
  ) async {
    final ok = await methodChannel.invokeMethod<bool>('setMockPermission', {
      'permission': permission.value,
      'status': status.value,
    });
    return ok ?? false;
  }

  @override
  Future<bool> setMockPermissionRequestResult(
    Permission permission,
    PermissionStatus status,
  ) async {
    final ok = await methodChannel.invokeMethod<bool>(
      'setMockPermissionRequestResult',
      {'permission': permission.value, 'status': status.value},
    );
    return ok ?? false;
  }

  @override
  Future<bool> mockDevicePowerOn(String deviceUUID) async {
    final ok = await methodChannel.invokeMethod<bool>('mockDevicePowerOn', {
      'deviceUUID': deviceUUID,
    });
    return ok ?? false;
  }

  @override
  Future<bool> mockDevicePowerOff(String deviceUUID) async {
    final ok = await methodChannel.invokeMethod<bool>('mockDevicePowerOff', {
      'deviceUUID': deviceUUID,
    });
    return ok ?? false;
  }

  @override
  Future<bool> mockDeviceDon(String deviceUUID) async {
    final ok = await methodChannel.invokeMethod<bool>('mockDeviceDon', {
      'deviceUUID': deviceUUID,
    });
    return ok ?? false;
  }

  @override
  Future<bool> mockDeviceDoff(String deviceUUID) async {
    final ok = await methodChannel.invokeMethod<bool>('mockDeviceDoff', {
      'deviceUUID': deviceUUID,
    });
    return ok ?? false;
  }

  @override
  Future<bool> requestAndroidPermissions() async {
    final ok = await methodChannel.invokeMethod<bool>(
      'requestAndroidPermissions',
    );
    return ok ?? false;
  }

  @override
  Future<bool> requestCameraPermission() async {
    try {
      final ok = await methodChannel.invokeMethod<bool>(
        'requestCameraPermission',
      );
      return ok ?? false;
    } on PlatformException catch (e) {
      throw CameraPermissionException(
        code: e.code,
        message: e.message ?? 'Unknown permission error',
        details: e.details is Map<Object?, Object?>
            ? Map<String, dynamic>.from(e.details as Map<Object?, Object?>)
            : null,
      );
    }
  }

  @override
  Future<bool> getCameraPermissionStatus() async {
    try {
      final ok = await methodChannel.invokeMethod<bool>(
        'getCameraPermissionStatus',
      );
      return ok ?? false;
    } on PlatformException catch (e) {
      throw CameraPermissionException(
        code: e.code,
        message: e.message ?? 'Unknown permission status error',
        details: e.details is Map<Object?, Object?>
            ? Map<String, dynamic>.from(e.details as Map<Object?, Object?>)
            : null,
      );
    }
  }

  @override
  Future<bool> startRegistration() async {
    try {
      final ok = await methodChannel.invokeMethod<bool>('startRegistration');
      return ok ?? false;
    } on PlatformException catch (e) {
      if (e.code == 'REGISTRATION_ERROR') {
        // Re-throw with more context if needed, or handle specific error codes
        throw PlatformException(
          code: e.code,
          message: e.message,
          details: e.details,
        );
      }
      rethrow;
    }
  }

  @override
  Future<bool> handleUrl(String url) async {
    final ok = await methodChannel.invokeMethod<bool>('handleUrl', {
      'url': url,
    });
    return ok ?? false;
  }

  @override
  Future<bool> disconnect() async {
    final ok = await methodChannel.invokeMethod<bool>('disconnect');
    return ok ?? false;
  }

  @override
  Future<bool> setMockCameraFeed(String deviceUUID, String? videoPath) async {
    final ok = await methodChannel.invokeMethod<bool>('setMockCameraFeed', {
      'deviceUUID': deviceUUID,
      'videoPath': videoPath,
    });
    return ok ?? false;
  }

  @override
  Future<bool> setMockCameraFacing(
    String deviceUUID,
    CameraFacing facing,
  ) async {
    final ok = await methodChannel.invokeMethod<bool>('setMockCameraFacing', {
      'deviceUUID': deviceUUID,
      'cameraFacing': facing.value,
    });
    return ok ?? false;
  }

  @override
  Future<bool> setMockCapturedImage(
    String deviceUUID,
    String? imagePath,
  ) async {
    final ok = await methodChannel.invokeMethod<bool>('setMockCapturedImage', {
      'deviceUUID': deviceUUID,
      'imagePath': imagePath,
    });
    return ok ?? false;
  }

  @override
  Future<int> startStreamSession(
    String? deviceUUID, {
    double fps = 30.0,
    StreamQuality streamQuality = StreamQuality.high,
    VideoCodec videoCodec = VideoCodec.raw,
  }) async {
    final args = <String, dynamic>{
      'fps': fps,
      'streamQuality': streamQuality.value,
      'videoCodec': videoCodec.value,
    };
    if (deviceUUID != null) {
      args['deviceUUID'] = deviceUUID;
    }
    final textureId = await methodChannel.invokeMethod<int>(
      'startStreamSession',
      args,
    );
    if (textureId == null) {
      throw PlatformException(
        code: 'TEXTURE_REGISTRATION_FAILED',
        message: 'Failed to register a Flutter texture for video streaming.',
      );
    }
    return textureId;
  }

  @override
  Future<bool> stopStreamSession(String? deviceUUID) async {
    final args = <String, dynamic>{};
    if (deviceUUID != null) {
      args['deviceUUID'] = deviceUUID;
    }
    final ok = await methodChannel.invokeMethod<bool>(
      'stopStreamSession',
      args,
    );
    return ok ?? false;
  }

  @override
  Future<CapturedPhoto> capturePhoto(
    String? deviceUUID, {
    PhotoCaptureFormat format = PhotoCaptureFormat.jpeg,
  }) async {
    final args = <String, dynamic>{
      'format': format.value,
    };
    if (deviceUUID != null) {
      args['deviceUUID'] = deviceUUID;
    }
    final result = await methodChannel.invokeMapMethod<String, dynamic>(
      'capturePhoto',
      args,
    );
    if (result == null) {
      throw PlatformException(
        code: 'CAPTURE_PHOTO_FAILED',
        message: 'No photo data returned from platform.',
      );
    }
    final bytes = result['bytes'] as Uint8List?;
    final resultFormat = result['format'] as String?;
    if (bytes == null || resultFormat == null) {
      throw PlatformException(
        code: 'CAPTURE_PHOTO_FAILED',
        message: 'Invalid photo data returned from platform.',
      );
    }
    return CapturedPhoto(bytes: bytes, format: resultFormat);
  }

  @override
  Future<RegistrationState> getRegistrationState() async {
    final value = await methodChannel.invokeMethod<int>('getRegistrationState');
    return RegistrationState.fromInt(value ?? 0);
  }

  @override
  Stream<RegistrationState> registrationStateStream() {
    return eventChannel.receiveBroadcastStream().map(
      (dynamic event) => RegistrationState.fromInt(event as int),
    );
  }

  @override
  Stream<StreamSessionState> streamSessionStateStream() {
    return streamSessionStateEventChannel.receiveBroadcastStream().map(
      (dynamic event) => StreamSessionState.fromInt(event as int),
    );
  }

  @override
  Stream<StreamSessionError> streamSessionErrorStream() {
    return streamSessionErrorEventChannel.receiveBroadcastStream().map(
      (dynamic event) {
        final map = Map<String, dynamic>.from(event as Map);
        return StreamSessionError(
          code: map['code'] as String,
          message: map['message'] as String,
        );
      },
    );
  }

  @override
  Stream<bool> activeDeviceStream() {
    return activeDeviceEventChannel.receiveBroadcastStream().map(
      (dynamic event) => event as bool,
    );
  }

  @override
  Stream<VideoStreamSize> videoStreamSizeStream() {
    return videoStreamSizeEventChannel.receiveBroadcastStream().map(
      (dynamic event) {
        final map = Map<String, dynamic>.from(event as Map);
        return VideoStreamSize(
          width: (map['width'] as num).toInt(),
          height: (map['height'] as num).toInt(),
        );
      },
    );
  }

  @override
  Future<bool> restartActiveDeviceMonitoring() async {
    final ok = await methodChannel.invokeMethod<bool>(
      'restartActiveDeviceMonitoring',
    );
    return ok ?? false;
  }

  @override
  Future<void> enableBackgroundStreaming({
    BackgroundNotification? androidNotification,
  }) async {
    final args = <String, dynamic>{};
    if (androidNotification != null) {
      args['androidNotification'] = androidNotification.toMap();
    }
    await methodChannel.invokeMethod<void>('enableBackgroundStreaming', args);
  }

  @override
  Future<void> disableBackgroundStreaming() async {
    await methodChannel.invokeMethod<void>('disableBackgroundStreaming');
  }

  @override
  Stream<VideoFrame> videoFramesStream() {
    return videoFramesEventChannel.receiveBroadcastStream().map(
      (dynamic event) {
        final map = Map<String, dynamic>.from(event as Map);
        final codecStr = map['codec'] as String? ?? 'raw';
        final codec = codecStr == 'hvc1' ? VideoCodec.hvc1 : VideoCodec.raw;
        final bytes = map['bytes'] as Uint8List;
        final bytesPerRow = (map['bytesPerRow'] as num?)?.toInt();
        return VideoFrame(
          codec: codec,
          bytes: bytes,
          width: (map['width'] as num).toInt(),
          height: (map['height'] as num).toInt(),
          presentationTimestampUs: (map['ptsUs'] as num).toInt(),
          isKeyframe: (map['isKeyframe'] as bool?) ?? true,
          bytesPerRow: bytesPerRow,
        );
      },
    );
  }
}
