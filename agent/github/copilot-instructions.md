# flutter_meta_wearables_dat — Copilot Instructions

Flutter plugin for Meta's Wearables Device Access Toolkit (DAT). Streams video from Meta AI Glasses (Ray-Ban Meta) on iOS (17.0+) and Android (API 29+).

## API

All methods are static on `MetaWearablesDat`. Single import: `import 'package:flutter_meta_wearables_dat/flutter_meta_wearables_dat.dart';`

### Integration lifecycle (order matters)

1. `requestAndroidPermissions()` — Android only, gates SDK init. No-op on iOS.
2. `startRegistration()` → user confirms in Meta AI → `handleUrl(url)` deep link callback
3. `restartActiveDeviceMonitoring()` — call after registration (critical on Android)
4. `requestCameraPermission()` — Meta AI permission bottom sheet
5. `startStreamSession(deviceUUID, fps:, streamQuality:, videoCodec:)` → returns `textureId`
6. Render: `Texture(textureId: textureId)` — zero-copy GPU rendering

### Key methods

- `registrationStateStream()` — RegistrationState: unavailable(0), available(1), registering(2), registered(3)
- `activeDeviceStream()` — bool, device availability
- `streamSessionStateStream()` — stopping(0), stopped(1), waitingForDevice(2), starting(3), streaming(4), paused(5)
- `streamSessionErrorStream()` — StreamSessionError with code/message. Codes: thermalCritical, hingesClosed, permissionDenied, deviceNotConnected, etc.
- `stopStreamSession(deviceUUID)` — end session
- `capturePhoto(deviceUUID, format:)` — PhotoCaptureFormat.jpeg or .heic
- `captureStreamFrame(textureId, width:, height:, format:)` — Dart-side rasterization for ML/OCR

### Mock device (testing without glasses)

- `pairMockRayBanMeta()` → UUID, `mockDevicePowerOn(uuid)`, `mockDeviceDon(uuid)`
- `setMockCameraFeed(uuid, videoPath)` — H.265 video
- Pass specific UUID to `startStreamSession` (not null)

## Platform differences

- `VideoCodec.hvc1` — iOS only (background streaming). Falls back to raw on Android.
- `FlutterFragmentActivity` required on Android (not FlutterActivity).
- `requestAndroidPermissions()` must be called first on Android.
- Photo format selection works on iOS only; Android device determines format.

## Setup

- iOS: Info.plist needs Bluetooth, external accessory, background modes, URL scheme, MWDAT dict
- Android: AndroidManifest permissions, GitHub Packages repo in settings.gradle.kts, GITHUB_TOKEN
- Deep links: `app_links` package, forward all URIs to `handleUrl()`

## Streams

Subscribe BEFORE starting operations. Cancel in dispose(). Always handle errors.

## Full reference

See AGENTS.md at repository root for complete API signatures, configuration XML/Kotlin snippets, and debugging guide.
