# DAT Flutter conventions

## API usage

- Always use `MetaWearablesDat` static methods — never instantiate the class.
- Single import: `import 'package:flutter_meta_wearables_dat/flutter_meta_wearables_dat.dart';`
- All DAT operations are `async` — always `await` them.
- Pass `null` as `deviceUUID` to use AutoDeviceSelector (recommended for real devices). Only pass a specific UUID for mock devices.

## Lifecycle order

This order is critical — calling methods out of order will fail:

1. `requestAndroidPermissions()` — always call first (no-op on iOS, gates SDK init on Android)
2. `startRegistration()` + `handleUrl()` — one-time registration with Meta AI app
3. `restartActiveDeviceMonitoring()` — call after registration completes (critical on Android)
4. `requestCameraPermission()` — shows Meta AI permission bottom sheet
5. `startStreamSession()` — begins camera streaming

## Streams

- Subscribe to streams **before** starting the operation they monitor.
- `registrationStateStream()` — subscribe before `startRegistration()`.
- `activeDeviceStream()` — subscribe early, used to enable/disable the start streaming button.
- `streamSessionStateStream()` and `streamSessionErrorStream()` — subscribe before `startStreamSession()`.
- Always cancel subscriptions in `dispose()`.

## Video rendering

- `startStreamSession()` returns a `textureId` (int).
- Render with `Texture(textureId: textureId)` — zero-copy GPU pipeline, no Dart-side decoding needed.
- Never try to manually decode video frames for display.

## Deep links

- Use the `app_links` package for handling registration callbacks.
- Forward **every** incoming URI to `MetaWearablesDat.handleUrl(uri.toString())`.
- This handles both registration and unregistration callbacks.

## Error handling

- Wrap method channel calls in `try/catch` for `PlatformException`.
- Use `CameraPermissionException` typed checks: `isDeviceDisconnected`, `isPermissionDenied`, `isInternalError`.
- Use `StreamSessionError` typed checks: `isThermalCritical`, `isHingesClosed`, `isPermissionDenied`.

## Platform awareness

- `VideoCodec.hvc1` is iOS-only (supports background streaming). On Android it falls back to `raw`.
- `PhotoCaptureFormat` selection works on iOS. On Android, the device determines the format.
- `FlutterFragmentActivity` is required on Android (not `FlutterActivity`).
