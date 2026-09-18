# meta-dat-flutter: Local Changes & Formalisation Plan

This document describes the uncommitted local changes made to this plugin and the steps required to formalise them for upstream.

## What Was Changed & Why

### 1. `grabCurrentFrame()` — New Method Channel API

**Problem:** Flutter's `Texture` widget stops receiving updates when the app is backgrounded and resumed. The `textureId` becomes stale, breaking our detection pipeline which needs to periodically grab frames for Gemini landmark matching.

**Solution:** A new `grabCurrentFrame()` method that reads the latest CVPixelBuffer directly from native memory via the method channel, bypassing the Texture rendering lifecycle entirely. The stream session and its pixel buffer remain alive across background/foreground transitions.

**Flow:**

```
Dart: MetaWearablesDat.grabCurrentFrame()
  |
  v
Method Channel: 'grabCurrentFrame'
  |
  v
iOS: MetaWearablesDatPlugin.grabCurrentFrame(result:)
  |
  v
PixelBufferTexture.copyAsJpegData()
  |  1. Acquires os_unfair_lock
  |  2. Reads _latestPixelBuffer (CVPixelBuffer)
  |  3. Wraps in CIImage
  |  4. Encodes to JPEG via static CIContext
  |  5. Returns Data? -> FlutterStandardTypedData -> Uint8List
  |
  v
Dart receives: Uint8List? (JPEG bytes or null)
```

**Files changed:**

| File | Change |
|------|--------|
| `lib/meta_wearables_dat_platform_interface.dart` | Abstract `grabCurrentFrame()` method |
| `lib/meta_wearables_dat_method_channel.dart` | Method channel implementation |
| `lib/flutter_meta_wearables_dat.dart` | Public static API |
| `ios/Classes/PixelBufferTexture.swift` | `copyAsJpegData()` using static CIContext |
| `ios/Classes/MetaWearablesDatPlugin.swift` | `"grabCurrentFrame"` case in handle() |

**Status:** iOS implemented. Android not implemented (will return `MethodNotImplemented`).

### 2. MWDATMockDevice Removed from Production Build

**Problem:** `MWDATMockDevice.xcframework` was unconditionally linked, adding binary size and exposing test-only APIs in production.

**Solution:** Removed from `Package.swift` and `.podspec`. All mock device code wrapped in `#if canImport(MWDATMockDevice)` guards with graceful `UNAVAILABLE` error responses when the framework is absent.

**Files changed:**

| File | Change |
|------|--------|
| `ios/Package.swift` | Removed MWDATMockDevice binary target and dependency |
| `ios/flutter_meta_wearables_dat.podspec` | Removed from vendored_frameworks and OTHER_LDFLAGS |
| `ios/Classes/MetaWearablesDatPlugin.swift` | `#if canImport()` guards on all mock methods |

### 3. NSLog Instrumentation

Structured `[MWDAT:*]` logging added to `ActiveDeviceStreamHandler.swift`, `MetaWearablesDatPlugin.swift`, and a `debugPrint` in the Dart `activeDeviceStream()`. Added during background/foreground debugging. Can be removed or gated behind a debug flag before release.

### 4. SwiftFormat

All Swift files reformatted (2-space to 4-space indentation). Cosmetic only.

---

## Manual Steps to Formalise

### Step 1: Implement `grabCurrentFrame` on Android

The Dart layer and iOS are done. Android is missing.

In `android/src/main/kotlin/.../FrameProcessor.kt`:

- [ ] Retain a reference to the latest rendered `Bitmap` (it is already reused across frames, just make it accessible)
- [ ] Add a synchronised `grabCurrentFrame(): ByteArray?` method that calls `bitmap.compress(Bitmap.CompressFormat.JPEG, 75, ByteArrayOutputStream())` and returns the byte array
- [ ] Ensure the same lock used for frame rendering protects the read

In `android/src/main/kotlin/.../MetaWearablesDatPlugin.kt`:

- [ ] Add `"grabCurrentFrame"` case in `onMethodCall`
- [ ] Call through to the frame processor's `grabCurrentFrame()`
- [ ] Return bytes via `result.success(byteArray)` or `result.success(null)` if no frame available

### Step 2: Add JPEG Quality Parameter (Optional)

The iOS `CIContext.jpegRepresentation` uses default quality which produces large files. Since frames are sent to Gemini at low FPS:

- [ ] Add optional `quality` parameter to `grabCurrentFrame(quality: double?)` in the Dart API
- [ ] Pass through method channel as argument
- [ ] iOS: Use `jpegRepresentation(of:colorSpace:options:)` with `kCGImageDestinationLossyCompressionQuality`
- [ ] Android: Pass quality (0-100) to `bitmap.compress()`
- [ ] Default to 0.7 (70%) if not specified

### Step 3: Add Unit Tests

- [ ] Dart: Verify `grabCurrentFrame` dispatches the correct method channel call
- [ ] Dart: Verify `null` return is handled (no active session)
- [ ] Dart: Verify `Uint8List` return is passed through correctly

### Step 4: Decide on MWDATMockDevice Strategy

Two options:

- **Option A: Keep conditional compilation.** The `#if canImport(MWDATMockDevice)` approach works but means the mock framework must be manually added back to `Package.swift` and the podspec for development/testing builds.
- **Option B: Separate build configurations.** Use a build flag or environment variable to include/exclude mock support, keeping the podspec stable.

- [ ] Decide which approach to use
- [ ] If Option A: document how to re-enable mock support for development
- [ ] If Option B: implement the build flag mechanism

### Step 5: Clean Up Debug Logging

- [ ] Remove or gate `NSLog("[MWDAT:*]")` statements behind a debug flag
- [ ] Remove `debugPrint` from `activeDeviceStream()` in Dart
- [ ] Consider using a logging level toggle (e.g., a static `MetaWearablesDat.debugLogging = false` flag)

### Step 6: Version Bump & Release

- [ ] Bump version in `pubspec.yaml` to `0.2.0` (new API surface)
- [ ] Update `CHANGELOG.md`:
  - Added `grabCurrentFrame()` for on-demand JPEG frame capture independent of Texture lifecycle
  - Removed MWDATMockDevice from production builds (conditional compilation)
- [ ] Update `README.md` with `grabCurrentFrame()` usage example
- [ ] Commit all changes
- [ ] Tag release

### Step 7: Update Consuming App (dumbo-spatial-guide)

Once the plugin is formally released:

- [ ] Update `pubspec.yaml` dependency from local path to versioned reference (git tag or pub)
- [ ] Verify `TourStateService` and `LandmarkDetectionService` still work with the formal API
- [ ] Test background/foreground cycle on both iOS and Android
