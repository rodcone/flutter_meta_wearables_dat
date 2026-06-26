# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Flutter plugin providing a bridge to Meta's Wearables Device Access Toolkit (DAT) for integration with Meta AI Glasses (Ray-Ban Meta). Supports iOS (17.0+) and Android (API 29+).

This repo is a **monorepo with two federated plugins** (Firebase / Datadog pattern):

- **`flutter_meta_wearables_dat/`** (root) — required core. Real-device registration, streaming, photo capture, background streaming. No mock-device code, no camera-symbol linkage; production apps therefore don't need `NSCameraUsageDescription` (iOS) or `CAMERA` (Android) just to ship the plugin.
- **`flutter_meta_wearables_dat_mock_device/`** (sibling) — optional add-on. Vendors `MWDATMockDevice.xcframework` (iOS) and depends on `mwdat-mockdevice` (Android) to drive a simulated Ray-Ban Meta from the phone's camera. Pulled in only for dev/staging. Owns its own method channel (`flutter_meta_wearables_dat_mock_device`), Dart facade (`MetaWearablesDatMockDevice`), and the `Permission` / `PermissionStatus` / `CameraFacing` / `GlassesModel` enums (all referenced exclusively by mock APIs). Since DAT 0.8.0 the facade pairs via `pairGlasses({GlassesModel model})` (replacing `pairRayBanMeta()`); the native layer maps the model token to the SDK's `GlassesModel` and `MockGlasses`/`MockGlassesServices` types (renamed from `MockDisplaylessGlasses*` in 0.8.0).

The split was introduced in 0.4.0 because Apple's binary scanner rejected v0.3.x builds for missing `NSCameraUsageDescription` whenever `MWDATMockDevice.xcframework` was statically linked, even if the host app never instantiated a mock device. See `CHANGELOG.md` for the full migration table.

## Common Commands

```bash
# Get dependencies (run from example/ for the example app)
flutter pub get

# Analyze/lint (uses very_good_analysis)
dart analyze

# Build example app
cd example && flutter build ios --release --no-codesign
cd example && flutter build apk

# Clean
cd example && flutter clean

# iOS pod sync after framework changes
cd example/ios && pod update

# Android dependency sync
cd example/android && ./gradlew build --refresh-dependencies
```

No test suite exists yet.

## Architecture

### Plugin Layer Pattern

```
MetaWearablesDat (lib/flutter_meta_wearables_dat.dart) # Static public API facade
    ↓
MetaWearablesDatPlatform (lib/..._platform_interface.dart)  # Abstract contract
    ↓
MethodChannelMetaWearablesDat (lib/..._method_channel.dart) # Method/event channel impl
    ↓
Native: iOS (Swift) | Android (Kotlin)
```

All three Dart files in `lib/` form the plugin's public API. `MetaWearablesDat` is the entry point with static methods that delegate to the platform interface singleton.

### Communication Channels

- **Method channel** `flutter_meta_wearables_dat` — request/response calls (registration, permissions, streaming control, `openDATGlassesAppUpdate`). The mock add-on owns a separate `flutter_meta_wearables_dat_mock_device` channel; the only cross-channel hop is an internal `_setVideoFeedRotation` call (mock plugin → core) so the mock package can update the texture rotation when its video feed changes orientation.
- **Event channels:**
  - `flutter_meta_wearables_dat/registration_state` — registration state int values
  - `flutter_meta_wearables_dat/active_device` — boolean device availability
  - `flutter_meta_wearables_dat/stream_session_state` — stream state int values (stopping=0, stopped=1, waitingForDevice=2, starting=3, streaming=4, paused=5). Dart-facing channel name is kept as `stream_session_state` for backwards compatibility even though the SDK renamed `StreamSessionState` → `StreamState` in 0.7.0.
  - `flutter_meta_wearables_dat/stream_session_errors` — error maps with `code` and `message` keys. Carries both `Stream.errorStream` errors (`thermalCritical`, `thermalEmergency`, `peakPowerShutdown`, `batteryCritical`, …) and `DeviceSession.errors` (`deviceThermalCritical`, `datAppOnTheGlassesUpdateRequired`, `dwaUnavailable`, …). String codes are kept identical across iOS and Android.
  - `flutter_meta_wearables_dat/video_stream_size` — `{width, height}` map emitted on stream start and resolution changes
  - `flutter_meta_wearables_dat/video_frames` — per-frame payloads (`codec`, `bytes`, `width`, `height`, `ptsUs`, `isKeyframe`) emitted in both foreground and background when a Dart subscriber is attached; zero-cost when no listeners. Codec-config frames (`VideoFrame.isCodecConfig == true` on Android in DAT 0.7.0) are filtered out before emission so recording consumers never see parameter-set frames as payload.
  - `flutter_meta_wearables_dat/device_state` — `{thermalLevel: Int}` map (Dart `ThermalLevel`: unknown=0, none=1, light=2, moderate=3, severe=4, critical=5, emergency=6, shutdown=7). The handler tracks the active device via `AutoDeviceSelector` and switches its inner per-device subscription whenever the active device changes.

### Native Implementations

**iOS** (`ios/flutter_meta_wearables_dat/Sources/flutter_meta_wearables_dat/MetaWearablesDatPlugin.swift`): Uses vendored xcframeworks in `ios/flutter_meta_wearables_dat/Frameworks/` (MWDATCore, MWDATCamera at DAT 0.8.0; in 0.8.0 `Stream.start()`/`Stream.stop()` became synchronous — no `await` — and `capturePhoto` enforces a client-side timeout so the Dart call always resolves with a typed `CAPTURE_PHOTO_FAILED`/`photoCaptureTimeout` error rather than hanging. `DeviceType.metaGlasses` is mapped to the `metaGlasses` code). `MWDATMockDevice.xcframework` lives in the mock add-on's `flutter_meta_wearables_dat_mock_device/ios/flutter_meta_wearables_dat_mock_device/Frameworks/` and is only linked when that package is in `pubspec.yaml`. Supports two video codecs: `raw` (CVPixelBuffer via `CMSampleBufferGetImageBuffer`) and `hvc1` (compressed HEVC decoded via `VTDecompressionSession` to BGRA pixel buffers). Zero-copy rendering via Flutter Texture API. DAT 0.7.0 renamed `StreamSession` → `Stream`, which collides with `Foundation.Stream` — Swift code therefore qualifies the type as `MWDATCamera.Stream` everywhere. Stream state, stream errors, device-session errors, and per-device thermal state are forwarded to Dart via dedicated event channel handlers: `StreamStateStreamHandler`, `StreamErrorStreamHandler` (also accepts `DeviceSessionError` via a `send(deviceSessionError:)` overload — funnels into the same `stream_session_errors` channel as `Stream.errorStream`), and `DeviceStateStreamHandler`. The `openDATGlassesAppUpdate` method-channel handler is the recovery path for the new `datAppOnTheGlassesUpdateRequired` `DeviceSessionError` and maps `NavigationError` cases to `metaAINotInstalled` / `notRegistered` `FlutterError` codes. For `hvc1`, the plugin observes `applicationDidEnterBackground` / `applicationWillEnterForeground` via `FlutterPluginRegistrar.addApplicationDelegate` — by default it invalidates the `VTDecompressionSession` on background (iOS forbids GPU access from backgrounded apps) and lets `decodeCompressedFrame()`'s lazy-init recreate it on the first frame after foregrounding. Frame processing is gated by an `isInBackground` flag; the underlying `MWDATCamera.Stream` is never stopped, so rendering resumes instantly on foreground return. **Background streaming** is managed by `BackgroundStreamingController` (`ios/flutter_meta_wearables_dat/Sources/flutter_meta_wearables_dat/BackgroundStreamingController.swift`) — when enabled, it activates an `AVAudioSession` (`.playAndRecord` / `.videoRecording` with `.allowBluetoothHFP` + `.mixWithOthers`) and observes `AVAudioSession.interruptionNotification` / `mediaServicesWereResetNotification` to re-activate on phone-call interruption / media-services-reset recovery. The HEVC decoder uses **hardware decode only** on both foreground and background-streaming paths; iOS's software HEVC decoder produced grey / corrupted frames in earlier 0.5.0 prereleases so that path was removed. The hardware decoder is invalidated on `applicationDidEnterBackground` and lazily recreated on the first frame after foreground, so background→foreground incurs a brief stall waiting for the next keyframe (acceptable trade-off vs broken frames). Decoded/raw frames are forwarded to Dart via `VideoFrameStreamHandler` on the `video_frames` event channel in both foreground and background — iOS emits **BGRA** bytes for `raw` (direct memcpy from the `CVPixelBuffer`) and raw **hvc1 NAL units** for `hvc1` (from the existing `CMBlockBuffer`). Texture writes are skipped while `isInBackground` since Metal writes from backgrounded apps are undefined; frame *emission* is not.

**Android** (`android/src/main/kotlin/io/rodcone/flutter_meta_wearables_dat/MetaWearablesDatPlugin.kt`): Uses Maven dependencies from GitHub Packages (version controlled via `ext.mwdat_version` in `android/build.gradle` — currently DAT 0.8.0; core depends on `mwdat-core` + `mwdat-camera` only — `mwdat-mockdevice` lives in the mock add-on's `build.gradle`). DAT 0.8.0 added `StreamState.PAUSED` (mapped to Dart `paused=5` in `StreamStateStreamHandler.mapState`, whose `when` is intentionally exhaustive with no `else`) and `DeviceType.META_GLASSES` (mapped to the `metaGlasses` code). I420→ARGB frame conversion via `FrameProcessor` rendered directly to SurfaceTexture (zero-copy). Only `raw` codec is supported (Android SDK limitation). DAT 0.7.0 renamed `Session` → `DeviceSession` and `StreamSessionState` → `StreamState`; the Kotlin code uses the new names. `RegistrationState` is also a plain enum in 0.7.0 (was a sealed class hierarchy in 0.6.x) — `mapRegistrationState` uses `when (state) { UNAVAILABLE -> 0, … }` against the UPPER_CASE values. Permission handling uses `startActivityForResult` with `PluginRegistry.ActivityResultListener` for the DAT permission contract, and `ActivityCompat.requestPermissions` with `RequestPermissionsResultListener` for Android runtime permissions (Bluetooth, Internet). A single shared `AutoDeviceSelector` instance is used across device monitoring, stream sessions, and the `DeviceStateStreamHandler` (thermal). Stream state forwarded via `StreamStateStreamHandler` (file: `StreamStateStreamHandler.kt`). Errors funnel through `StreamSessionErrorStreamHandler` which has three entry points: (a) `send(StreamError)` for `Stream.errorStream` events, (b) `send(DeviceSessionError)` for `DeviceSession.errors` events — the plugin subscribes to that `SharedFlow<DeviceSessionError>` in `ensureSessionStarted`, mapping to codes like `deviceThermalCritical` / `datAppOnTheGlassesUpdateRequired` / `dwaUnavailable`, and (c) `sendError(code, message)` for pre-stream failures (`Wearables.createSession` / `addStream` `onFailure`). The `openDATGlassesAppUpdate` method-channel handler calls `Wearables.openDATGlassesAppUpdate(activity)` and maps `NavigationError` to iOS-equivalent code strings. Photo capture uses `DatResult<PhotoData, CaptureError>` with typed error handling. **Important:** SDK initialization (`Wearables.initialize()`) is deferred until after Bluetooth permissions are granted — this is critical for device discovery to work. MainActivity must extend `FlutterFragmentActivity`. **Background streaming** is handled by `BackgroundStreamingService.kt` — a foreground service of type `connectedDevice` (API 30+; plain foreground on API 29) that holds a `PARTIAL_WAKE_LOCK` tagged `MWDAT::StreamingWakeLock` and shows a user-customizable notification (title/text/channelId/channelName/iconResourceName passed as intent extras from the plugin). On Android 13+ (API 33+) `enableBackgroundStreaming` prompts for `POST_NOTIFICATIONS` via a `NOTIFICATION_PERMISSION_REQUEST_CODE` path before starting the service; if denied the service still starts (stream survives) but the OS silently suppresses the notification. The plugin tracks `backgroundStreamingStarted` and stops the service in `onDetachedFromEngine` to avoid hot-restart notification leaks. Frames are forwarded to Dart via `VideoFrameStreamHandler` on the `video_frames` event channel — the native `VideoFrame.buffer` (I420 planar YUV, `width * height * 3/2` bytes) is copied verbatim into a `Uint8List` so recording apps can write straight to disk without the I420→ARGB conversion the `FrameProcessor` performs for the texture. Emission is guarded by `videoFrameStreamHandler.hasListener` so non-recording apps pay zero per-frame cost.

### Integration Lifecycle

Four-phase flow (+ optional 5th): **Android Permissions** (`requestAndroidPermissions()` — Bluetooth/Internet, no-op on iOS) → **Registration** (`startRegistration()` + deep link `handleUrl()`) → **Camera Permission** (`requestCameraPermission()`) → **Streaming** (`startStreamSession()` returns a texture ID for zero-copy rendering via Flutter's `Texture` widget; session state and errors monitored via dedicated event channels). On Android, `requestAndroidPermissions()` must be called first as it gates SDK initialization.

**Optional — Background streaming.** Apps that need the session to survive the app being backgrounded, the phone being locked, or both, can opt in *before* `startStreamSession()` by calling `enableBackgroundStreaming(androidNotification: ...)`. On iOS this activates an `AVAudioSession` that keeps the process scheduled; the HEVC decoder is invalidated on background entry (iOS forbids GPU access from backgrounded apps) and lazily recreated on the first frame after foreground, so resume has a brief keyframe-wait stall. On Android it starts a foreground service + wake lock with the provided notification. Call `disableBackgroundStreaming()` after stopping the session. Frames delivered while the Flutter Texture can't render (iOS backgrounded / Android backgrounded) are still emitted on the `video_frames` event channel, accessible from Dart via `MetaWearablesDat.videoFramesStream()` — subscribe before `startStreamSession()` if you need the opening keyframe.

**Optional — Thermal monitoring + DAT-app-update recovery (new in 0.5.0).** Apps can subscribe to `MetaWearablesDat.deviceStateStream()` for live `ThermalLevel` updates so they can warn the user at `severe` / `critical` — by the time a `thermalCritical` error reaches `streamSessionErrorStream()` the stream has already paused. When `streamSessionErrorStream()` emits `datAppOnTheGlassesUpdateRequired`, call `MetaWearablesDat.openDATGlassesAppUpdate()` to bounce the user into the Meta AI app to update the on-device DAT app; the SDK refuses to stream until the user does. The example app's stream screen demonstrates both: a thermal chip in the top-left and an inline "Update" action in the error banner.

### Example App

Located in `example/`. Uses Provider for state management with three providers:
- `DeviceProvider` — registration state + permission management
- `MockDeviceProvider` — mock device pairing/control
- `StreamSessionProvider` — active device monitoring + streaming sessions

Deep link handling via `app_links` package for DAT registration callbacks.

## Updating DAT Versions

See `doc/MAINTAINERS.md` for detailed steps. Currently on **DAT 0.8.0** on both platforms. Summary:
- **iOS**: Download xcframeworks from github.com/facebook/meta-wearables-dat-ios releases → replace in `ios/flutter_meta_wearables_dat/Frameworks/` (core: `MWDATCore` + `MWDATCamera`) and `flutter_meta_wearables_dat_mock_device/ios/flutter_meta_wearables_dat_mock_device/Frameworks/` (mock: `MWDATMockDevice`) → `pod update` in example/ios (or delete the workspace's `swiftpm/` dirs under SPM mode). Skip `MWDATDisplay` and `MWDATMockDeviceTestClient` xcframeworks — not vendored. Both CocoaPods and Swift Package Manager are supported; CI exercises both via the `ios-build` matrix.
- **Android**: Update `ext.mwdat_version` in both `android/build.gradle` files (core + mock add-on, must match) → sync Gradle. The `versions-in-sync` CI job enforces this.

## Linting

Uses `very_good_analysis` package. Suppressed rules: `document_ignores`, `lines_longer_than_80_chars`, `public_member_api_docs`, `sort_constructors_first`, `todo`.

## API Reference (Important to read, it's official and updated)
Fetch https://wearables.developer.meta.com/llms.txt?full=true for the Wearables DAT SDK API reference.

## Consumer Agent Files

The `agent/` directory contains AI assistant configuration files for **developers using this plugin** (not maintainers). These are installed into consumer projects via `./install-skills.sh`.

- `AGENTS.md` — Universal AI reference (works with 20+ AI tools)
- `agent/claude/` — Claude Code skills, commands, rules
- `agent/cursor/rules/` — Cursor IDE rules (.mdc files)
- `agent/github/` — GitHub Copilot instructions

See [AI-Assisted Development](https://wearables.developer.meta.com/docs/ai-assisted) for Meta's approach.
