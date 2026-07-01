# flutter_meta_wearables_dat — Copilot Instructions

Flutter plugin for Meta's Wearables Device Access Toolkit (DAT). Streams video from Meta AI Glasses (Ray-Ban Meta) on iOS (17.0+) and Android (API 29+).

## API

All methods are static on `MetaWearablesDat`. Single import: `import 'package:flutter_meta_wearables_dat/flutter_meta_wearables_dat.dart';`

### Integration lifecycle (order matters)

1. `requestAndroidPermissions()` — Android only, gates SDK init. No-op on iOS.
2. `startRegistration()` → user confirms in Meta AI → `handleUrl(url)` deep link callback
3. `restartActiveDeviceMonitoring()` — call after registration (critical on Android)
4. `requestCameraPermission()` — Meta AI permission bottom sheet
5. `startStreamSession(deviceId, fps:, streamQuality:, videoCodec:)` → returns `textureId` — pass a `WearableDevice.id` from `getDevices()` to pin a specific pair, or `null` to auto-select
6. Render: `Texture(textureId: textureId)` — zero-copy GPU rendering

### Key methods

- `registrationStateStream()` — RegistrationState: unavailable(0), available(1), registering(2), registered(3)
- `activeDeviceStream()` — bool, device availability
- `getDevices()` → `List<WearableDevice>` (id, name, type, linkState, compatibility, supportsDisplay, isActive, isStreamingDevice). Pass an `id` to `startStreamSession` to pin that pair; requesting a *different* device while one is streaming throws `PlatformException` `STREAM_ACTIVE`. Android throws `NOT_INITIALIZED` if called before Bluetooth permission.
- `streamSessionStateStream()` — stopping(0), stopped(1), waitingForDevice(2), starting(3), streaming(4), paused(5)
- `streamSessionErrorStream()` — StreamSessionError with code/message. Codes: thermalCritical, thermalEmergency, peakPowerShutdown, batteryCritical, hingesClosed, permissionDenied, deviceNotConnected, datAppOnTheGlassesUpdateRequired (recover via `openDATGlassesAppUpdate()`), dwaUnavailable, plus device-session variants (deviceThermalCritical etc.).
- `deviceStateStream()` — `Stream<DeviceState>` of live `ThermalLevel` (unknown, none, light, moderate, severe, critical, emergency, shutdown). Use to warn the user *before* a thermal error stops the stream.
- `openDATGlassesAppUpdate()` — opens the Meta AI app to the DAT-app-update screen. Pair with the `datAppOnTheGlassesUpdateRequired` error code to drive a "tap to update" UI.
- `videoStreamSizeStream()` — VideoStreamSize (width/height/aspectRatio) emitted on stream start and resolution changes
- `stopStreamSession(deviceId)` — end session
- `capturePhoto(deviceId, format:)` — PhotoCaptureFormat.jpeg or .heic
- `captureStreamFrame(textureId, width:, height:, format:)` — Dart-side rasterization for ML/OCR. Returns `null` while backgrounded.
- `enableBackgroundStreaming(androidNotification: BackgroundNotification(...))` — opt-in; call BEFORE `startStreamSession()` to keep the session alive while backgrounded or screen-locked. iOS + Android. `BackgroundNotification` is required on Android.
- `disableBackgroundStreaming()` — tears down the iOS `AVAudioSession` / stops the Android foreground service. Idempotent.
- `videoFramesStream()` — per-frame `VideoFrame` (codec, bytes, width, height, presentationTimestampUs, isKeyframe) in both foreground and background. Zero-cost when no listener is attached. Subscribe before `startStreamSession()` to capture the opening keyframe.

### Mock device (testing without glasses)

Mock support lives in the optional add-on `flutter_meta_wearables_dat_mock_device` (since 0.4.0). Production builds that omit it skip `MWDATMockDevice` linkage and don't need `NSCameraUsageDescription` / `CAMERA`.

- Add `flutter_meta_wearables_dat_mock_device: ^0.7.0` to dev/staging `pubspec.yaml`.
- Import: `import 'package:flutter_meta_wearables_dat_mock_device/flutter_meta_wearables_dat_mock_device.dart';`
- Optional bypass for registration/permission flows: `MetaWearablesDatMockDevice.configure(initiallyRegistered: true, initialPermissionsGranted: true)`
- Lifecycle: `MetaWearablesDatMockDevice.pairGlasses({model})` → UUID (`model` defaults to `GlassesModel.rayBanMeta`; other values: `oakleyMetaHSTN`, `oakleyMetaVanguard`, `rayBanMetaOptics`, `metaGlasses`), then `.powerOn(uuid)` + `.don(uuid)`, optionally `.setCameraFacing(uuid, CameraFacing.back)`
- Override feeds: `MetaWearablesDatMockDevice.setCameraFeed(uuid, videoPath)` (H.265), `.setCapturedImage(uuid, imagePath)`
- Streaming/capture still go through the core API: pass the specific UUID (not null) to `MetaWearablesDat.startStreamSession(uuid)`.
- Cleanup: `MetaWearablesDatMockDevice.unpairGlasses(uuid)`.
- `Permission`, `PermissionStatus`, `CameraFacing` enums all live in the mock package.

## Platform differences

- `VideoCodec.hvc1` — iOS only. Falls back to raw on Android.
- Background streaming works on both platforms via `enableBackgroundStreaming()`. iOS needs `audio` + `bluetooth-central` added to `UIBackgroundModes`; Android needs a `BackgroundNotification` (plugin manifest auto-merges the required FOREGROUND_SERVICE / WAKE_LOCK permissions).
- `videoFramesStream()` payload: iOS `raw` → BGRA, iOS `hvc1` → HEVC NAL units, Android `raw` → I420 planar YUV.
- `FlutterFragmentActivity` required on Android (not FlutterActivity).
- `requestAndroidPermissions()` must be called first on Android.
- Photo format selection works on iOS only; Android device determines format.

## Setup

- iOS: Info.plist needs Bluetooth usage string, URL scheme, MWDAT dict, and `bluetooth-peripheral` background mode. **Camera transport — pick one:** Wi‑Fi (recommended; `NSLocalNetworkUsageDescription` + `NSBonjourServices` + `HotspotConfiguration`/`wifi-info` entitlements — higher bandwidth) **or** Bluetooth Classic (`com.meta.ar.wearable` + `external-accessory` background mode — no Wi‑Fi prompt, works offline). Transport doesn't affect App Store eligibility (SDK links ExternalAccessory either way; Meta limits publishing until GA). For background streaming also add `audio` and `bluetooth-central` to `UIBackgroundModes`.
- Android: AndroidManifest permissions, GitHub Packages repo in settings.gradle.kts, GITHUB_TOKEN. No manifest changes needed for background streaming (permissions auto-merge from plugin).
- Deep links: `app_links` package, forward all URIs to `handleUrl()`

## Streams

Subscribe BEFORE starting operations. Cancel in dispose(). Always handle errors.

## Full reference

See AGENTS.md at repository root for complete API signatures, configuration XML/Kotlin snippets, and debugging guide.
