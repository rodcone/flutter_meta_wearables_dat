# Permissions

## Permission lifecycle

The DAT plugin has two separate permission layers:

1. **Android runtime permissions** — Bluetooth and Internet (Android only)
2. **DAT camera permission** — Granted through the Meta AI app (both platforms)

## Phase 0: Android runtime permissions

```dart
// Must be called FIRST on Android — gates SDK initialization.
// No-op on iOS, safe to always call.
final granted = await MetaWearablesDat.requestAndroidPermissions();
```

If the user denies these, the DAT SDK cannot initialize and device discovery will not work.

## Phase 2: DAT camera permission

After registration is complete:

```dart
// Check if already granted
final hasPermission = await MetaWearablesDat.getCameraPermissionStatus();

if (!hasPermission) {
  // Shows Meta AI permission bottom sheet
  // User can: allow always, allow once, or deny
  try {
    final granted = await MetaWearablesDat.requestCameraPermission();
  } on CameraPermissionException catch (e) {
    if (e.isDeviceDisconnected) {
      // Device is disconnected or powered off
    } else if (e.isPermissionDenied) {
      // User denied permission
    } else if (e.isInternalError) {
      // Internal SDK error
    }
  }
}
```

## CameraPermissionException

| Property | Meaning |
|----------|---------|
| `code` | Error code string |
| `message` | Human-readable description |
| `details` | Additional error details (Map) |
| `isDeviceDisconnected` | Device is disconnected or powered off |
| `isPermissionDenied` | User denied permission |
| `isInternalError` | Internal SDK error |

## Order matters

```
requestAndroidPermissions()  →  startRegistration()  →  requestCameraPermission()  →  startStreamSession()
        (Android only)              (one-time)              (first-time)                 (each session)
```

Calling methods out of order will fail. On Android, `requestAndroidPermissions()` must complete before any other DAT call.

## Reference implementation

See `example/lib/providers/device_provider.dart` — methods `_initializeRegistrationState()`, `requestCameraPermission()`, and `ensureCameraPermission()`.
