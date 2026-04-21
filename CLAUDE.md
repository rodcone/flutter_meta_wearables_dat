# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Flutter plugin providing a bridge to Meta's Wearables Device Access Toolkit (DAT) for integration with Meta AI Glasses (Ray-Ban Meta). Supports iOS (17.0+) and Android (API 29+).

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

- **Method channel** `flutter_meta_wearables_dat` — request/response calls (registration, permissions, streaming control, mock device)
- **Event channels:**
  - `flutter_meta_wearables_dat/registration_state` — registration state int values
  - `flutter_meta_wearables_dat/active_device` — boolean device availability
  - `flutter_meta_wearables_dat/stream_session_state` — stream session state int values (stopping=0, stopped=1, waitingForDevice=2, starting=3, streaming=4, paused=5)
  - `flutter_meta_wearables_dat/stream_session_errors` — error maps with `code` and `message` keys
  - `flutter_meta_wearables_dat/video_stream_size` — `{width, height}` map emitted on stream start and resolution changes
  - `flutter_meta_wearables_dat/video_frames` — per-frame payloads (`codec`, `bytes`, `width`, `height`, `ptsUs`, `isKeyframe`) emitted in both foreground and background when a Dart subscriber is attached; zero-cost when no listeners

### Native Implementations

**iOS** (`ios/Classes/MetaWearablesDatPlugin.swift`): Uses vendored xcframeworks in `ios/Frameworks/` (MWDATCore, MWDATCamera, MWDATMockDevice). Supports two video codecs: `raw` (CVPixelBuffer via `CMSampleBufferGetImageBuffer`) and `hvc1` (compressed HEVC decoded via `VTDecompressionSession` to BGRA pixel buffers). Zero-copy rendering via Flutter Texture API. Stream session state and errors are forwarded to Dart via dedicated event channel handlers (`StreamSessionStateStreamHandler`, `StreamSessionErrorStreamHandler`). For `hvc1`, the plugin observes `applicationDidEnterBackground` / `applicationWillEnterForeground` via `FlutterPluginRegistrar.addApplicationDelegate` — by default it invalidates the `VTDecompressionSession` on background (iOS forbids GPU access from backgrounded apps) and lets `decodeCompressedFrame()`'s lazy-init recreate it on the first frame after foregrounding. Frame processing is gated by an `isInBackground` flag; the underlying `StreamSession` is never stopped, so rendering resumes instantly on foreground return. **Background streaming** is managed by `BackgroundStreamingController` (`ios/Classes/BackgroundStreamingController.swift`) — when enabled, it activates an `AVAudioSession` (`.playAndRecord` / `.videoRecording` with `.allowBluetoothHFP` + `.mixWithOthers`), observes `AVAudioSession.interruptionNotification` / `routeChangeNotification` / `mediaServicesWereResetNotification` to re-activate on phone-call / route-change recovery, and flips `setupDecompressionSession(forceSoftware:)` to `true` so the decoder survives background→foreground without stutter. Decoded/raw frames are forwarded to Dart via `VideoFrameStreamHandler` on the `video_frames` event channel in both foreground and background — iOS emits **BGRA** bytes for `raw` (direct memcpy from the `CVPixelBuffer`) and raw **hvc1 NAL units** for `hvc1` (from the existing `CMBlockBuffer`). Texture writes are skipped while `isInBackground` since Metal writes from backgrounded apps are undefined; frame *emission* is not.

**Android** (`android/src/main/kotlin/io/rodcone/flutter_meta_wearables_dat/MetaWearablesDatPlugin.kt`): Uses Maven dependencies from GitHub Packages (version controlled via `ext.mwdat_version` in `android/build.gradle`). I420→ARGB frame conversion via `FrameProcessor` rendered directly to SurfaceTexture (zero-copy). Only `raw` codec is supported (Android SDK limitation). Permission handling uses `startActivityForResult` with `PluginRegistry.ActivityResultListener` for the DAT permission contract, and `ActivityCompat.requestPermissions` with `RequestPermissionsResultListener` for Android runtime permissions (Bluetooth, Internet). A single shared `AutoDeviceSelector` instance is used across device monitoring and stream sessions (mirrors the reference app pattern). Stream session state forwarded via `StreamSessionStateStreamHandler`; errors emitted programmatically via `StreamSessionErrorStreamHandler` (Android SDK has no native error publisher). Photo capture uses `DatResult<PhotoData, CaptureError>` with typed error handling. **Important:** SDK initialization (`Wearables.initialize()`) is deferred until after Bluetooth permissions are granted — this is critical for device discovery to work. MainActivity must extend `FlutterFragmentActivity`. **Background streaming** is handled by `BackgroundStreamingService.kt` — a foreground service of type `connectedDevice` (API 30+; plain foreground on API 29) that holds a `PARTIAL_WAKE_LOCK` tagged `MWDAT::StreamingWakeLock` and shows a user-customizable notification (title/text/channelId/channelName/iconResourceName passed as intent extras from the plugin). The plugin tracks `backgroundStreamingStarted` and stops the service in `onDetachedFromEngine` to avoid hot-restart notification leaks. Frames are forwarded to Dart via `VideoFrameStreamHandler` on the `video_frames` event channel — the native `VideoFrame.buffer` (I420 planar YUV, `width * height * 3/2` bytes) is copied verbatim into a `Uint8List` so recording apps can write straight to disk without the I420→ARGB conversion the `FrameProcessor` performs for the texture. Emission is guarded by `videoFrameStreamHandler.hasListener` so non-recording apps pay zero per-frame cost.

### Integration Lifecycle

Four-phase flow (+ optional 5th): **Android Permissions** (`requestAndroidPermissions()` — Bluetooth/Internet, no-op on iOS) → **Registration** (`startRegistration()` + deep link `handleUrl()`) → **Camera Permission** (`requestCameraPermission()`) → **Streaming** (`startStreamSession()` returns a texture ID for zero-copy rendering via Flutter's `Texture` widget; session state and errors monitored via dedicated event channels). On Android, `requestAndroidPermissions()` must be called first as it gates SDK initialization.

**Optional — Background streaming.** Apps that need the session to survive the app being backgrounded, the phone being locked, or both, can opt in *before* `startStreamSession()` by calling `enableBackgroundStreaming(androidNotification: ...)`. On iOS this activates an `AVAudioSession` and forces software HEVC decoding; on Android it starts a foreground service + wake lock with the provided notification. Call `disableBackgroundStreaming()` after stopping the session. Frames delivered while the Flutter Texture can't render (iOS backgrounded / Android backgrounded) are still emitted on the `video_frames` event channel, accessible from Dart via `MetaWearablesDat.videoFramesStream()` — subscribe before `startStreamSession()` if you need the opening keyframe.

### Example App

Located in `example/`. Uses Provider for state management with three providers:
- `DeviceProvider` — registration state + permission management
- `MockDeviceProvider` — mock device pairing/control
- `StreamSessionProvider` — active device monitoring + streaming sessions

Deep link handling via `app_links` package for DAT registration callbacks.

## Updating DAT Versions

See `doc/MAINTAINERS.md` for detailed steps. Summary:
- **iOS**: Download xcframeworks from github.com/facebook/meta-wearables-dat-ios releases → replace in `ios/Frameworks/` → `pod update` in example/ios
- **Android**: Update `ext.mwdat_version` in `android/build.gradle` → sync Gradle

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
