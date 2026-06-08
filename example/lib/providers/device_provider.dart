import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_meta_wearables_dat/flutter_meta_wearables_dat.dart';

/// Provider to manage registration state and camera permissions.
class DeviceProvider extends ChangeNotifier {
  bool? _hasCameraPermissionGranted;
  RegistrationState? _registrationState;
  StreamSubscription<RegistrationState>? _registrationStateSubscription;
  // Gates the register-transition side effects (active-device restart +
  // camera-permission auto-request) so they only fire on a genuine state
  // change, never while seeding the initial state on launch.
  bool _initialized = false;

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
      _initialized = true;
      notifyListeners();

      // Listen to state changes
      _registrationStateSubscription =
          MetaWearablesDat.registrationStateStream().listen(
            (state) {
              _setRegistrationState(state);
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
    unawaited(HapticFeedback.lightImpact());

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
    unawaited(HapticFeedback.mediumImpact());

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
      _setRegistrationState(await MetaWearablesDat.getRegistrationState());
    } catch (e) {
      debugPrint('[MetaWearablesDAT] Error refreshing registration state: $e');
      _setRegistrationState(RegistrationState.unavailable);
    } finally {
      if (notify) {
        notifyListeners();
      }
    }
  }

  /// Updates the cached registration state and fires the one-time side effects
  /// that must run when the user (re-)registers. Routing both the registration
  /// stream and [refreshRegistrationState] through here means the
  /// unregistered→registered transition is handled exactly once, regardless of
  /// which path observes it first. Side effects are suppressed until
  /// [_initialized] so simply launching the app while already registered does
  /// not bounce the user into Meta AI.
  void _setRegistrationState(RegistrationState state) {
    final wasRegistered = _registrationState == RegistrationState.registered;
    _registrationState = state;

    if (!_initialized) return;
    if (state != RegistrationState.registered || wasRegistered) return;

    // Fresh (re-)registration. Re-subscribe the plugin to the device flow so it
    // picks up the newly available device…
    unawaited(MetaWearablesDat.restartActiveDeviceMonitoring());
    // …and re-request camera permission. Unregistration revokes it, and the SDK
    // will not surface the glasses in its device flow until at least one
    // permission is granted again via Meta AI — so without this the user is
    // stranded behind a Start button that never enables. This is a no-op (no
    // Meta AI navigation) when permission is already granted, e.g. right after
    // first-time onboarding.
    unawaited(requestCameraPermission());
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
      if (e.isDeviceDisconnected) {
        // Expected while the glasses are still (re)connecting — not a denial.
        // Leave the status unknown; it resolves once a device is active or the
        // user re-grants permission (auto-requested on the register transition).
        _hasCameraPermissionGranted = null;
      } else {
        debugPrint('[MetaWearablesDAT] Camera permission status error: $e');
        _hasCameraPermissionGranted = false;
      }
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
