import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_meta_wearables_dat/flutter_meta_wearables_dat.dart';
import 'package:flutter_meta_wearables_dat_example/providers/device_provider.dart';
import 'package:flutter_meta_wearables_dat_example/providers/mock_device_provider.dart';

/// Provider to manage streaming state and active device monitoring.
/// Depends on DeviceProvider for registration state and permissions.
/// Depends on MockDeviceProvider for mock device UUID.
class StreamSessionProvider extends ChangeNotifier {
  final DeviceProvider deviceProvider;
  final MockDeviceProvider mockDeviceProvider;

  StreamSubscription<bool>? _activeDeviceSubscription;
  StreamSubscription<StreamSessionState>? _sessionStateSubscription;
  StreamSubscription<StreamSessionError>? _sessionErrorSubscription;
  StreamSubscription<VideoStreamSize>? _videoStreamSizeSubscription;
  VideoStreamSize? _videoStreamSize;
  bool _hasActiveDevice = false;
  bool _isStreaming = false;
  double _fps = 24;
  StreamQuality _streamQuality = StreamQuality.low;
  VideoCodec _videoCodec = VideoCodec.raw;
  StreamSessionState? _sessionState;
  StreamSessionError? _lastError;
  String? _selectedVideo;
  String? _selectedImage;
  bool _isLoadingVideo = false;
  bool _isLoadingImage = false;
  int? _textureId;

  StreamSessionProvider(this.deviceProvider, this.mockDeviceProvider) {
    _initializeActiveDeviceMonitoring();
  }

  bool get hasActiveDevice => _hasActiveDevice;
  bool get isStreaming => _isStreaming;
  double get fps => _fps;
  StreamQuality get streamQuality => _streamQuality;
  VideoCodec get videoCodec => _videoCodec;
  StreamSessionState? get sessionState => _sessionState;
  StreamSessionError? get lastError => _lastError;
  String? get selectedVideo => _selectedVideo;
  String? get selectedImage => _selectedImage;
  bool get isLoadingVideo => _isLoadingVideo;
  bool get isLoadingImage => _isLoadingImage;
  int? get textureId => _textureId;
  VideoStreamSize? get videoStreamSize => _videoStreamSize;
  bool get supportsHvc1 => Platform.isIOS;

  void _initializeActiveDeviceMonitoring() {
    _activeDeviceSubscription = MetaWearablesDat.activeDeviceStream().listen(
      (hasActiveDevice) {
        _hasActiveDevice = hasActiveDevice;
        notifyListeners();
      },
      onError: (dynamic error) {
        debugPrint('[MetaWearablesDAT] Error in active device stream: $error');
        _hasActiveDevice = false;
        notifyListeners();
      },
    );
  }

  @override
  void dispose() {
    _activeDeviceSubscription?.cancel();
    _sessionStateSubscription?.cancel();
    _sessionErrorSubscription?.cancel();
    _videoStreamSizeSubscription?.cancel();
    super.dispose();
  }

  void setSelectedVideo(String? path) {
    _selectedVideo = path;
    notifyListeners();
  }

  void setSelectedImage(String? path) {
    _selectedImage = path;
    notifyListeners();
  }

  void setIsLoadingVideo(bool value) {
    _isLoadingVideo = value;
    notifyListeners();
  }

  void setIsLoadingImage(bool value) {
    _isLoadingImage = value;
    notifyListeners();
  }

  void setFps(double fps) {
    HapticFeedback.lightImpact();

    if (_fps != fps) {
      _fps = fps;
      notifyListeners();
    }
  }

  void setStreamQuality(StreamQuality quality) {
    HapticFeedback.lightImpact();

    if (_streamQuality != quality) {
      _streamQuality = quality;
      notifyListeners();
    }
  }

  void setVideoCodec(VideoCodec codec) {
    HapticFeedback.lightImpact();

    if (_videoCodec != codec) {
      _videoCodec = codec;
      notifyListeners();
    }
  }

  void dismissError() {
    _lastError = null;
    notifyListeners();
  }

  Future<void> startStreamSession() async {
    try {
      // Set camera feed if video is selected (only for mock devices)
      if (_selectedVideo != null && mockDeviceProvider.deviceUUID != null) {
        await MetaWearablesDat.setMockCameraFeed(
          mockDeviceProvider.deviceUUID!,
          _selectedVideo,
        );
      }

      // Set captured image if image is selected (only for mock devices)
      if (_selectedImage != null && mockDeviceProvider.deviceUUID != null) {
        await MetaWearablesDat.setMockCapturedImage(
          mockDeviceProvider.deviceUUID!,
          _selectedImage,
        );
      }

      // Subscribe to session state and error streams
      unawaited(_sessionStateSubscription?.cancel());
      _sessionStateSubscription =
          MetaWearablesDat.streamSessionStateStream().listen(
        (state) {
          _sessionState = state;
          if (state == StreamSessionState.stopped) {
            _isStreaming = false;
            _textureId = null;
          }
          notifyListeners();
        },
        onError: (dynamic error) {
          debugPrint('[MetaWearablesDAT] Session state stream error: $error');
        },
      );

      unawaited(_sessionErrorSubscription?.cancel());
      _sessionErrorSubscription =
          MetaWearablesDat.streamSessionErrorStream().listen(
        (error) {
          _lastError = error;
          notifyListeners();
        },
        onError: (dynamic error) {
          debugPrint('[MetaWearablesDAT] Session error stream error: $error');
        },
      );

      unawaited(_videoStreamSizeSubscription?.cancel());
      _videoStreamSize = null;
      _videoStreamSizeSubscription =
          MetaWearablesDat.videoStreamSizeStream().listen(
        (size) {
          _videoStreamSize = size;
          notifyListeners();
        },
        onError: (dynamic error) {
          debugPrint('[MetaWearablesDAT] Video size stream error: $error');
        },
      );

      // Start the stream session - deviceUUID is optional (uses AutoDeviceSelector if null).
      // Returns a texture ID for zero-copy rendering via the Flutter Texture widget.
      _textureId = await MetaWearablesDat.startStreamSession(
        mockDeviceProvider.deviceUUID,
        fps: _fps,
        streamQuality: _streamQuality,
        videoCodec: _videoCodec,
      );
      _isStreaming = true;
      notifyListeners();
    } catch (e) {
      debugPrint('[MetaWearablesDAT] Error starting stream session: $e');
      _isStreaming = false;
      notifyListeners();
    }
  }

  Future<void> stopStreamSession() async {
    unawaited(HapticFeedback.mediumImpact());

    try {
      await MetaWearablesDat.stopStreamSession(mockDeviceProvider.deviceUUID);
      unawaited(_sessionStateSubscription?.cancel());
      _sessionStateSubscription = null;
      unawaited(_sessionErrorSubscription?.cancel());
      _sessionErrorSubscription = null;
      unawaited(_videoStreamSizeSubscription?.cancel());
      _videoStreamSizeSubscription = null;
      _sessionState = null;
      _lastError = null;
      _textureId = null;
      _videoStreamSize = null;
      _isStreaming = false;
      notifyListeners();
    } catch (e) {
      debugPrint('[MetaWearablesDAT] Error stopping stream session: $e');
    }
  }

  Future<CapturedPhoto?> capturePhoto() async {
    try {
      final photo = await MetaWearablesDat.capturePhoto(
        mockDeviceProvider.deviceUUID,
      );
      return photo;
    } catch (e) {
      debugPrint('[MetaWearablesDAT] Error capturing photo: $e');
      return null;
    }
  }
}
