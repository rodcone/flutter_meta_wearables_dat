import 'dart:async';
import 'package:flutter/foundation.dart';
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
  bool _hasActiveDevice = false;
  bool _isStreaming = false;
  String? _selectedVideo;
  String? _selectedImage;
  bool _isLoadingVideo = false;
  bool _isLoadingImage = false;

  StreamSessionProvider(this.deviceProvider, this.mockDeviceProvider) {
    _initializeActiveDeviceMonitoring();
  }

  bool get hasActiveDevice => _hasActiveDevice;
  bool get isStreaming => _isStreaming;
  String? get selectedVideo => _selectedVideo;
  String? get selectedImage => _selectedImage;
  bool get isLoadingVideo => _isLoadingVideo;
  bool get isLoadingImage => _isLoadingImage;

  void _initializeActiveDeviceMonitoring() {
    _activeDeviceSubscription = MetaWearablesDat.activeDeviceStream().listen(
      (hasActiveDevice) {
        debugPrint(
          '[MetaWearablesDAT] StreamSessionProvider: Active device status changed: $hasActiveDevice',
        );
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

  Future<void> startStreamSession({double fps = 30.0}) async {
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

      // Start the stream session - deviceUUID is optional (uses AutoDeviceSelector if null)
      final success = await MetaWearablesDat.startStreamSession(
        mockDeviceProvider.deviceUUID,
        fps: fps,
      );
      if (success) {
        // Add a small delay to ensure the stream session is fully initialized
        // before the EventChannel listener starts
        await Future.delayed(const Duration(milliseconds: 100));
        _isStreaming = true;
        notifyListeners();
      } else {
        debugPrint('[MetaWearablesDAT] Failed to start stream session');
      }
    } catch (e) {
      debugPrint('[MetaWearablesDAT] Error starting stream session: $e');
      _isStreaming = false;
      notifyListeners();
    }
  }

  Future<void> stopStreamSession() async {
    try {
      // deviceUUID is optional - uses "auto" if null
      await MetaWearablesDat.stopStreamSession(mockDeviceProvider.deviceUUID);
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
