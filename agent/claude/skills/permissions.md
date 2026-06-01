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
    if (!granted) {
      // User declined the prompt — SDK returns false (not an exception).
    }
  } on CameraPermissionException catch (e) {
    if (e.isDeviceDisconnected) {
      // No Ray-Ban Meta reachable (powered off, out of range, no connection).
    } else if (e.isInternalError) {
      // SDK-side failure: request already in progress, timeout,
      // Meta AI app missing, generic internal error.
    }
    // isPermissionDenied is reserved for future SDK semantics — current
    // SDK surfaces user denial as `granted == false` above, not here.
  }
}
```

## CameraPermissionException

| Property | Meaning |
|----------|---------|
| `code` | Error code string |
| `message` | Human-readable description |
| `details` | Additional error details (Map) |
| `isDeviceDisconnected` | No Ray-Ban Meta reachable (powered off, out of range, no connection) |
| `isPermissionDenied` | Reserved for future SDK semantics — user denial currently returns `false` from `requestCameraPermission()`, not an exception |
| `isInternalError` | Request already in progress, timeout, Meta AI app missing, or any other SDK-side failure |

## Order matters

```
requestAndroidPermissions()  →  startRegistration()  →  requestCameraPermission()  →  startStreamSession()
        (Android only)              (one-time)              (first-time)                 (each session)
```

Calling methods out of order will fail. On Android, `requestAndroidPermissions()` must complete before any other DAT call.

## Reference implementation

See `example/lib/providers/device_provider.dart` — methods `_initializeRegistrationState()`, `requestCameraPermission()`, and `ensureCameraPermission()`.
