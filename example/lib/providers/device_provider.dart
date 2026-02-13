import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_meta_wearables_dat/flutter_meta_wearables_dat.dart';

/// Provider to manage registration state and camera permissions.
class DeviceProvider extends ChangeNotifier {
  bool? _hasCameraPermissionGranted;
  RegistrationState? _registrationState;
  RegistrationState? _previousRegistrationState;
  StreamSubscription<RegistrationState>? _registrationStateSubscription;

  bool? get hasCameraPermissionGranted => _hasCameraPermissionGranted;
  RegistrationState? get registrationState => _registrationState;
  bool get isRegistered => _registrationState == RegistrationState.registered;

  DeviceProvider() {
    _initializeRegistrationState();
  }

  Future<void> _initializeRegistrationState() async {
    try {
      // Request Android runtime permissions (Bluetooth, Internet) required
      // by the DAT SDK. No-op on iOS.
      await MetaWearablesDat.requestAndroidPermissions();

      await refreshRegistrationState(notify: false);
      notifyListeners();

      // Listen to state changes
      _registrationStateSubscription =
          MetaWearablesDat.registrationStateStream().listen(
            (state) {
              _previousRegistrationState = _registrationState;
              _registrationState = state;

              // After registration completes, restart active device monitoring
              // so the plugin re-subscribes to the device flow and picks up
              // newly available devices.
              if (state == RegistrationState.registered &&
                  _previousRegistrationState != RegistrationState.registered) {
                MetaWearablesDat.restartActiveDeviceMonitoring();
              }

              notifyListeners();
            },
            onError: (dynamic error) {
              debugPrint(
                '[MetaWearablesDAT]Error in registration state stream: $error',
              );
            },
          );
    } catch (e) {
      debugPrint(
        '[MetaWearablesDAT] Error initializing registration state: $e',
      );
      _registrationState = RegistrationState.unavailable;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _registrationStateSubscription?.cancel();
    super.dispose();
  }

  Future<void> disconnect() async {
    try {
      await MetaWearablesDat.disconnect();
    } on PlatformException catch (e) {
      if (e.code == 'UNREGISTRATION_ERROR') {
        debugPrint(
          '[MetaWearablesDAT] Unregistration error: ${e.message}',
        );
      } else {
        debugPrint('[MetaWearablesDAT] Error during disconnect: $e');
      }
      notifyListeners();
    } catch (e) {
      debugPrint('[MetaWearablesDAT] Error disconnecting: $e');
      notifyListeners();
    }
  }

  Future<void> startRegistration() async {
    try {
      await MetaWearablesDat.startRegistration();
    } on PlatformException catch (e) {
      if (e.code == 'REGISTRATION_ERROR') {
        if (e.details is int) {
          final errorCode = e.details as int;
          if (errorCode == 0) {
            _registrationState = RegistrationState.registered;
            notifyListeners();
            return;
          } else {
            debugPrint(
              '[MetaWearablesDAT]Registration error code: $errorCode - ${e.message}',
            );
          }
        } else {
          debugPrint('[MetaWearablesDAT] Registration error: ${e.message}');
        }
      } else {
        debugPrint(
          '[MetaWearablesDAT]Unexpected error during registration: $e',
        );
      }
      notifyListeners();
    } catch (e) {
      debugPrint('[MetaWearablesDAT] Error starting registration: $e');
      notifyListeners();
    }
  }

  Future<void> handleUrl(String url) async {
    try {
      await MetaWearablesDat.handleUrl(url);
    } on PlatformException catch (e) {
      if (e.code == 'REGISTRATION_ERROR' || e.code == 'HANDLE_URL_ERROR') {
        debugPrint(
          '[MetaWearablesDAT] Error during URL handling: ${e.message}',
        );
      }
    } catch (e) {
      debugPrint('[MetaWearablesDAT] Error handling URL: $e');
    } finally {
      await refreshRegistrationState();
      // Restart active device monitoring after returning from Meta AI
      // (registration, unregistration, or permission). The app was in background
      // and the device flow may be stale — restarting picks up the device.
      await MetaWearablesDat.restartActiveDeviceMonitoring();
      await refreshCameraPermissionStatus();
    }
  }

  Future<void> refreshRegistrationState({bool notify = true}) async {
    try {
      _previousRegistrationState = _registrationState;
      _registrationState = await MetaWearablesDat.getRegistrationState();
    } catch (e) {
      debugPrint('[MetaWearablesDAT] Error refreshing registration state: $e');
      _registrationState = RegistrationState.unavailable;
    } finally {
      if (notify) {
        notifyListeners();
      }
    }
  }

  Future<void> refreshCameraPermissionStatus({bool notify = true}) async {
    if (!isRegistered) {
      _hasCameraPermissionGranted = null;
      if (notify) {
        notifyListeners();
      }
      return;
    }

    try {
      final hasPermission = await MetaWearablesDat.getCameraPermissionStatus();
      _hasCameraPermissionGranted = hasPermission;
    } on CameraPermissionException catch (e) {
      debugPrint('[MetaWearablesDAT] Camera permission status error: $e');
      _hasCameraPermissionGranted = false;
    } catch (e) {
      debugPrint(
        '[MetaWearablesDAT] Error checking camera permission status: $e',
      );
      _hasCameraPermissionGranted = false;
    } finally {
      if (notify) {
        notifyListeners();
      }
    }
  }

  Future<bool> requestCameraPermission() async {
    try {
      final hasPermission = await MetaWearablesDat.requestCameraPermission();
      debugPrint(
        '[MetaWearablesDAT] Camera permission granted: $hasPermission',
      );
      _hasCameraPermissionGranted = hasPermission;
      return hasPermission;
    } on CameraPermissionException catch (e) {
      debugPrint('[MetaWearablesDAT] Camera permission error: $e');
      _hasCameraPermissionGranted = false;
      return false;
    } catch (e) {
      debugPrint('[MetaWearablesDAT] Error requesting camera permission: $e');
      _hasCameraPermissionGranted = false;
      return false;
    } finally {
      notifyListeners();
    }
  }

  Future<bool> ensureCameraPermission() async {
    await refreshCameraPermissionStatus();
    if (_hasCameraPermissionGranted ?? false) {
      return true;
    }
    return requestCameraPermission();
  }
}
