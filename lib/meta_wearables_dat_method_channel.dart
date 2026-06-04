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

  /// The event channel used to receive per-device state updates
  /// (thermal level). Tracks the active device on the native side.
  @visibleForTesting
  final deviceStateEventChannel = const EventChannel(
    'flutter_meta_wearables_dat/device_state',
  );

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
    return eventChannel.receiveBroadcastStream().map((dynamic event) {
      final state = RegistrationState.fromInt(event as int);
      if (kDebugMode) {
        debugPrint('[MetaWearablesDAT] registrationState → $state');
      }
      return state;
    });
  }

  @override
  Stream<StreamSessionState> streamSessionStateStream() {
    return streamSessionStateEventChannel.receiveBroadcastStream().map((
      dynamic event,
    ) {
      final state = StreamSessionState.fromInt(event as int);
      if (kDebugMode) {
        debugPrint('[MetaWearablesDAT] streamSessionState → $state');
      }
      return state;
    });
  }

  @override
  Stream<StreamSessionError> streamSessionErrorStream() {
    return streamSessionErrorEventChannel.receiveBroadcastStream().map((
      dynamic event,
    ) {
      final map = Map<String, dynamic>.from(event as Map);
      final err = StreamSessionError(
        code: map['code'] as String,
        message: map['message'] as String,
      );
      if (kDebugMode) {
        debugPrint(
          '[MetaWearablesDAT] streamSessionError → ${err.code}: ${err.message}',
        );
      }
      return err;
    });
  }

  @override
  Stream<bool> activeDeviceStream() {
    return activeDeviceEventChannel.receiveBroadcastStream().map((
      dynamic event,
    ) {
      final available = event as bool;
      if (kDebugMode) {
        debugPrint('[MetaWearablesDAT] activeDevice → $available');
      }
      return available;
    });
  }

  @override
  Stream<VideoStreamSize> videoStreamSizeStream() {
    return videoStreamSizeEventChannel.receiveBroadcastStream().map((
      dynamic event,
    ) {
      final map = Map<String, dynamic>.from(event as Map);
      final size = VideoStreamSize(
        width: (map['width'] as num).toInt(),
        height: (map['height'] as num).toInt(),
      );
      if (kDebugMode) {
        debugPrint(
          '[MetaWearablesDAT] videoStreamSize → ${size.width}x${size.height}',
        );
      }
      return size;
    });
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

  @override
  Future<bool> openDATGlassesAppUpdate() async {
    final ok = await methodChannel.invokeMethod<bool>(
      'openDATGlassesAppUpdate',
    );
    return ok ?? false;
  }

  @override
  Stream<DeviceState> deviceStateStream() {
    return deviceStateEventChannel.receiveBroadcastStream().map((
      dynamic event,
    ) {
      final map = Map<String, dynamic>.from(event as Map);
      final state = DeviceState(
        thermalLevel: ThermalLevel.fromInt(
          (map['thermalLevel'] as num).toInt(),
        ),
      );
      if (kDebugMode) {
        debugPrint(
          '[MetaWearablesDAT] deviceState → thermalLevel=${state.thermalLevel}',
        );
      }
      return state;
    });
  }
}
