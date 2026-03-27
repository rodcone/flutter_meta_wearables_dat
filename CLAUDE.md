# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Flutter plugin providing a bridge to Meta's Wearables Device Access Toolkit (DAT) for integration with Meta AI Glasses (RayBan Meta). Supports iOS (17.0+) and Android (API 29+).

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

### Native Implementations

**iOS** (`ios/Classes/MetaWearablesDatPlugin.swift`): Uses vendored xcframeworks in `ios/Frameworks/` (MWDATCore, MWDATCamera, MWDATMockDevice). Supports two video codecs: `raw` (CVPixelBuffer via `CMSampleBufferGetImageBuffer`) and `hvc1` (compressed HEVC decoded via `VTDecompressionSession` to BGRA pixel buffers). Zero-copy rendering via Flutter Texture API. Stream session state and errors are forwarded to Dart via dedicated event channel handlers (`StreamSessionStateStreamHandler`, `StreamSessionErrorStreamHandler`).

**Android** (`android/src/main/kotlin/io/rodcone/flutter_meta_wearables_dat/MetaWearablesDatPlugin.kt`): Uses Maven dependencies from GitHub Packages (version controlled via `ext.mwdat_version` in `android/build.gradle`). I420→ARGB frame conversion via `FrameProcessor` rendered directly to SurfaceTexture (zero-copy). Only `raw` codec is supported (Android SDK limitation). Permission handling uses `startActivityForResult` with `PluginRegistry.ActivityResultListener` for the DAT permission contract, and `ActivityCompat.requestPermissions` with `RequestPermissionsResultListener` for Android runtime permissions (Bluetooth, Internet). A single shared `AutoDeviceSelector` instance is used across device monitoring and stream sessions (mirrors the reference app pattern). Stream session state forwarded via `StreamSessionStateStreamHandler`; errors emitted programmatically via `StreamSessionErrorStreamHandler` (Android SDK has no native error publisher). Photo capture uses `DatResult<PhotoData, CaptureError>` with typed error handling. **Important:** SDK initialization (`Wearables.initialize()`) is deferred until after Bluetooth permissions are granted — this is critical for device discovery to work. MainActivity must extend `FlutterFragmentActivity`.

### Integration Lifecycle

Four-phase flow: **Android Permissions** (`requestAndroidPermissions()` — Bluetooth/Internet, no-op on iOS) → **Registration** (`startRegistration()` + deep link `handleUrl()`) → **Camera Permission** (`requestCameraPermission()`) → **Streaming** (`startStreamSession()` returns a texture ID for zero-copy rendering via Flutter's `Texture` widget; session state and errors monitored via dedicated event channels). On Android, `requestAndroidPermissions()` must be called first as it gates SDK initialization.

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