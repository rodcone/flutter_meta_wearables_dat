import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_meta_wearables_dat/flutter_meta_wearables_dat.dart';
import 'package:flutter_meta_wearables_dat_example/providers/device_provider.dart';
import 'package:flutter_meta_wearables_dat_example/providers/mock_device_provider.dart';
import 'package:flutter_meta_wearables_dat_mock_device/flutter_meta_wearables_dat_mock_device.dart';

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
  StreamSubscription<DeviceState>? _deviceStateSubscription;
  VideoStreamSize? _videoStreamSize;
  bool _hasActiveDevice = false;
  bool _isStreaming = false;
  double _fps = 15;
  StreamQuality _streamQuality = StreamQuality.medium;
  VideoCodec _videoCodec = VideoCodec.raw;
  StreamSessionState? _sessionState;
  StreamSessionError? _lastError;
  ThermalLevel? _thermalLevel;
  String? _selectedVideo;
  String? _selectedImage;
  bool _isLoadingVideo = false;
  bool _isLoadingImage = false;
  int? _textureId;
  bool _backgroundStreamingEnabled = false;

  StreamSessionProvider(this.deviceProvider, this.mockDeviceProvider) {
    _initializeActiveDeviceMonitoring();
    _initializeDeviceStateMonitoring();
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
  bool get backgroundStreamingEnabled => _backgroundStreamingEnabled;

  /// Current thermal level of the active device, or `null` if no device is
  /// active or the SDK hasn't reported a level yet. Updated live via
  /// [MetaWearablesDat.deviceStateStream].
  ThermalLevel? get thermalLevel => _thermalLevel;

  void _initializeActiveDeviceMonitoring() {
    _activeDeviceSubscription = MetaWearablesDat.activeDeviceStream().listen(
      (hasActiveDevice) {
        _hasActiveDevice = hasActiveDevice;
        // Reset thermal readout when device goes away so the UI doesn't show
        // stale data; the next active device will repopulate it.
        if (!hasActiveDevice) {
          _thermalLevel = null;
        }
        notifyListeners();
      },
      onError: (dynamic error) {
        debugPrint('[MetaWearablesDAT] Error in active device stream: $error');
        _hasActiveDevice = false;
        _thermalLevel = null;
        notifyListeners();
      },
    );
  }

  void _initializeDeviceStateMonitoring() {
    _deviceStateSubscription = MetaWearablesDat.deviceStateStream().listen(
      (state) {
        if (_thermalLevel != state.thermalLevel) {
          _thermalLevel = state.thermalLevel;
          notifyListeners();
        }
      },
      onError: (dynamic error) {
        debugPrint('[MetaWearablesDAT] Device state stream error: $error');
      },
    );
  }

  /// Opens the Meta AI app to the DAT-app-update screen on the connected
  /// glasses when the SDK reports `datAppOnTheGlassesUpdateRequired`.
  Future<bool> openDATGlassesAppUpdate() async {
    unawaited(HapticFeedback.mediumImpact());
    try {
      return await MetaWearablesDat.openDATGlassesAppUpdate();
    } catch (e) {
      debugPrint('[MetaWearablesDAT] openDATGlassesAppUpdate failed: $e');
      return false;
    }
  }

  @override
  void dispose() {
    _activeDeviceSubscription?.cancel();
    _sessionStateSubscription?.cancel();
    _sessionErrorSubscription?.cancel();
    _videoStreamSizeSubscription?.cancel();
    _deviceStateSubscription?.cancel();
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

  /// Clears the pending error after the UI has shown it (e.g. via SnackBar).
  void clearError() {
    if (_lastError == null) return;
    _lastError = null;
    notifyListeners();
  }

  void _setError(StreamSessionError error) {
    _lastError = error;
    notifyListeners();
  }

  Future<void> startStreamSession() async {
    try {
      // Set camera feed if video is selected (only for mock devices)
      if (_selectedVideo != null && mockDeviceProvider.deviceUUID != null) {
        await MetaWearablesDatMockDevice.setCameraFeed(
          mockDeviceProvider.deviceUUID!,
          _selectedVideo,
        );
      }

      // Set captured image if image is selected (only for mock devices)
      if (_selectedImage != null && mockDeviceProvider.deviceUUID != null) {
        await MetaWearablesDatMockDevice.setCapturedImage(
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
        _setError,
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

  Future<void> setBackgroundStreamingEnabled(bool enabled) async {
    if (_backgroundStreamingEnabled == enabled) return;
    try {
      if (enabled) {
        await MetaWearablesDat.enableBackgroundStreaming(
          androidNotification: const BackgroundNotification(
            title: 'Streaming from your glasses',
            text: 'Keeps the camera stream alive in the background.',
            channelId: 'mwdat_example.streaming',
            channelName: 'Stream Session',
          ),
        );
      } else {
        await MetaWearablesDat.disableBackgroundStreaming();
      }
      _backgroundStreamingEnabled = enabled;
      notifyListeners();
    } catch (e) {
      debugPrint('[MetaWearablesDAT] Background streaming toggle failed: $e');
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
