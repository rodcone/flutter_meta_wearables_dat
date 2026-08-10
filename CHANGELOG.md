## 0.9.0
**BREAKING CHANGES**
* iOS: `stopStreamSession()` now ends the underlying `DeviceSession` instead of keeping it cached for the process lifetime. The glasses' stream-ended tone hangs off the session lifecycle, so the cached session meant the tone only played when the app was killed. The Dart API is unchanged, but every `startStreamSession()` after a stop now pays a full session reconnect instead of a fast capability re-add.
* iOS: session teardown waits for the `DeviceSession` to actually reach `.stopped` (10 s backstop) before releasing it, so the session-end handshake reliably reaches the glasses.
* iOS: stream teardown is now event-driven — the plugin holds its `Camera`/`Stream` references until the SDK reports `.stopped` (30 s backstop) instead of polling for 3 s and releasing unconditionally. The SDK's stop cascade holds the `Stream` weakly; the old bounded release could cancel the stop handshake mid-flight and strand a live capability on the glasses.
* iOS: `stopStreamSession()` with no active stream still ends a lingering `DeviceSession` left behind by a failed start (the call still rejects with `SESSION_NOT_FOUND` afterwards).
* Example app: iOS camera transport switched from Bluetooth Classic to Wi-Fi. The glasses play their stream-started tone only on the Wi-Fi transport; the Info.plist and entitlements comments document how to switch back. Delete and reinstall the app after switching transports — stale accessory pairing state otherwise keeps the old transport.

## 0.8.0
**BREAKING CHANGES**
* Update to Meta Wearables DAT **0.9.0** on both platforms.
* **Minimum iOS deployment target is now 17.2** (was 17.0). The vendored xcframeworks are built `-target arm64-apple-ios17.2`, so apps below that will fail to link.
* iOS: `capturePhoto()` failures now resolve in milliseconds instead of waiting out the 15 s timeout — DAT 0.9.0 reports them through `StreamError.photoCaptureFailed`, surfaced as `PlatformException(CAPTURE_PHOTO_FAILED, details: photoCaptureFailed)`. The timeout remains as a backstop.
* `hingesClosed` now also fires when the glasses are **taken off**, not just when the arms are folded. The SDK does not auto-resume in either case: tear the session down (clear your texture ID and streaming flag) or the `Texture` widget freezes on its last frame.
* Android: two `DeviceSessionError` cases that previously collapsed into `unexpectedError` now report properly as `sessionEndedByDevice` and `capabilityDenied`; `DEVICE_DISCONNECTED` maps to `deviceNotConnected`.
* Android: stream-level `thermalEmergency` is gone (DAT 0.9.0 removed `StreamError.THERMAL_EMERGENCY`) — a thermal emergency now arrives as the session-level `deviceThermalEmergency`. `thermalEmergency` is iOS-only from this release.
* Android: `Stream.start()` failures are no longer silently swallowed; they surface on `streamSessionErrorStream()`.
* Photo-capture failures are documented as never appearing on `streamSessionErrorStream()` on either platform — they reject the `capturePhoto()` future.
* Add a README note on opting out of DAT crash reporting (host-app config only, no plugin API).

## 0.7.2
* Improve README.

## 0.7.1
* Docs: document the iOS Wi‑Fi vs Bluetooth Classic camera transport choice, with migration/switching steps.

## 0.7.0
**BREAKING CHANGES**
* Update to Meta Wearables DAT **0.8.0** on both platforms.
* Add the **Meta Glasses** device type (`WearableDeviceType.metaGlasses`).
* Android: observe the new `StreamState.paused` mid-session (parity with iOS).
* iOS: `capturePhoto()` no longer hangs on an accepted-but-undelivered capture — it now times out with `PlatformException(CAPTURE_PHOTO_FAILED, details: photoCaptureTimeout)`.
* Surface the SDK's new registration/unregistration `timeout` errors.
* **Mock add-on:** `pairRayBanMeta()` → `pairGlasses(model:)` with a new `GlassesModel` enum (see its changelog).

## 0.6.1
* iOS: Fix `noEligibleDevice` and empty `getDevices()` right after camera permission grant by keeping the SDK device list warm.
* `requestCameraPermission()` waits briefly for device discovery before returning (iOS and Android).

## 0.6.0
* Add `getDevices()` and wearable device types for listing paired glasses, connection state, compatibility, and the active/streaming pair.
* Add device pinning via `startStreamSession(deviceId)` (`null` keeps automatic selection), with `STREAM_ACTIVE` protection and a paired-device picker in the example app.

## 0.5.3
* iOS: Fix first-registration device discovery and a `startStreamSession` hang after a failed start; surface genuine session errors.

## 0.5.2
* iOS: Add Swift Package Manager support alongside CocoaPods.

## 0.5.1
* Prepare Android Gradle for Flutter's Built-in Kotlin migration.
* Camera permission errors are now typed `CameraPermissionException`s on both platforms; a `false` return means *user denied*, exclusively.
* Gate event-stream `debugPrint` behind `kDebugMode` so release builds stop logging plugin events.

## 0.5.0
* Update to DAT SDK 0.7.0 on iOS and Android. Existing Dart APIs unchanged; new opt-in additions below — non-breaking, drop-in upgrade.
* New `openDATGlassesAppUpdate()` — opens the Meta AI app to update the on-device DAT app. Pair with the new `datAppOnTheGlassesUpdateRequired` error code to drive a "tap to update" UI.
* New `deviceStateStream()` returning `Stream<DeviceState>` for live `ThermalLevel` updates. Lets apps warn the user *before* a thermal error stops the stream.
* New `StreamSessionError` codes: `thermalEmergency`, `peakPowerShutdown`, `batteryCritical`, plus device-session variants (`deviceThermalCritical`, `deviceThermalEmergency`, `devicePeakPowerShutdown`, `deviceBatteryCritical`, `datAppOnTheGlassesUpdateRequired`, `dwaUnavailable`).
* Inherits DAT 0.7.0 bug fixes: Android `checkPermission` double-resume crash, post-Bluetooth-reconnect stale state, photo capture timeout, `ServiceConnection` leak during registration; iOS session stop propagation.
* Display capability (new in DAT 0.7.0 for Ray-Ban Display glasses) is intentionally **not** bundled — to keep this package focused on camera. A future `flutter_meta_wearables_dat_display` add-on will mirror the mock-device split.

## 0.4.0
* **BREAKING**: MockDeviceKit moved to a separate optional package, `flutter_meta_wearables_dat_mock_device`. Production apps no longer link `MWDATMockDevice.xcframework` (iOS) or `mwdat-mockdevice` (Android) and therefore no longer need `NSCameraUsageDescription` (iOS) or the `CAMERA` permission (Android) just to ship the plugin. The Apple App Store binary scanner previously rejected v0.3.x builds that omitted those strings because MockDeviceKit unconditionally linked `AVFoundation`; that requirement is gone.
* Apps that pair against a mock device for development should add `flutter_meta_wearables_dat_mock_device` to `pubspec.yaml` and migrate calls — see the migration table below. The shape mirrors Firebase's `firebase_core` + per-feature packages and Datadog's `datadog_flutter_plugin` + `datadog_session_replay`.
* Mock APIs renamed (the `Mock*` prefix is now redundant given the namespace):

| Before (0.3.x, core) | After (0.4.0, mock add-on) |
|---|---|
| `MetaWearablesDat.configureMockDevices(...)` | `MetaWearablesDatMockDevice.configure(...)` |
| `MetaWearablesDat.disableMockDevices()` | `MetaWearablesDatMockDevice.disable()` |
| `MetaWearablesDat.pairMockRayBanMeta()` | `MetaWearablesDatMockDevice.pairRayBanMeta()` |
| `MetaWearablesDat.unpairMockRayBanMeta(uuid)` | `MetaWearablesDatMockDevice.unpairRayBanMeta(uuid)` |
| `MetaWearablesDat.setMockPermission(p, s)` | `MetaWearablesDatMockDevice.setPermission(p, s)` |
| `MetaWearablesDat.setMockPermissionRequestResult(p, s)` | `MetaWearablesDatMockDevice.setPermissionRequestResult(p, s)` |
| `MetaWearablesDat.mockDevicePowerOn(uuid)` | `MetaWearablesDatMockDevice.powerOn(uuid)` |
| `MetaWearablesDat.mockDevicePowerOff(uuid)` | `MetaWearablesDatMockDevice.powerOff(uuid)` |
| `MetaWearablesDat.mockDeviceDon(uuid)` | `MetaWearablesDatMockDevice.don(uuid)` |
| `MetaWearablesDat.mockDeviceDoff(uuid)` | `MetaWearablesDatMockDevice.doff(uuid)` |
| `MetaWearablesDat.setMockCameraFeed(uuid, path)` | `MetaWearablesDatMockDevice.setCameraFeed(uuid, path)` |
| `MetaWearablesDat.setMockCameraFacing(uuid, f)` | `MetaWearablesDatMockDevice.setCameraFacing(uuid, f)` |
| `MetaWearablesDat.setMockCapturedImage(uuid, path)` | `MetaWearablesDatMockDevice.setCapturedImage(uuid, path)` |

* The `Permission`, `PermissionStatus`, and `CameraFacing` enums (referenced exclusively by mock APIs) moved to the mock add-on. Import them from `flutter_meta_wearables_dat_mock_device` after migrating.
* All non-mock APIs (`startRegistration`, `requestCameraPermission`, `requestAndroidPermissions`, `startStreamSession` / `stopStreamSession`, `capturePhoto`, `enableBackgroundStreaming` / `disableBackgroundStreaming`, every event stream) keep the same signatures and behavior — production code that doesn't touch mock devices needs no changes other than potentially removing `NSCameraUsageDescription` and `CAMERA`.

## 0.3.1
* Fix: CMSampleBufferGetFormatDescription used with .hvc1 background streaming to correctly pass VPS/SPS/PPS and enable ffmpeg_kit_flutter use cases while backgrounded.

## 0.3.0
* **BREAKING**: Update to DAT SDK 0.6.0 on iOS and Android.
* New `setMockCameraFacing()` to switch the mock device's camera between front and back; adds `CameraFacing`.
* New `configureMockDevices()`, `disableMockDevices()`, `setMockPermission()` and `setMockPermissionRequestResult()` for finer-grained mock device control.
* New `videoStreamSizeStream()` exposing the native video frame dimensions so Dart can drive an `AspectRatio` around the `Texture` widget instead of forcing a fixed size.
* New opt-in background streaming on **both iOS and Android**: `enableBackgroundStreaming(androidNotification:)` / `disableBackgroundStreaming()` keep the session alive when the host app is backgrounded or the phone is locked. iOS activates an `AVAudioSession` (`.playAndRecord` / `.videoRecording` with `.allowBluetoothHFP` + `.mixWithOthers`) and forces software HEVC decoding so the decoder survives background→foreground without stutter. Android starts a foreground service of type `connectedDevice` with a user-customizable notification (title/text/channelId/channelName/icon) and a `PARTIAL_WAKE_LOCK`; the plugin manifest auto-merges the required `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_CONNECTED_DEVICE`, and `WAKE_LOCK` permissions. iOS hosts must add `audio` and `bluetooth-central` to `UIBackgroundModes`.
* New `videoFramesStream()` emitting per-frame `VideoFrame` payloads (codec / bytes / width / height / presentationTimestampUs / isKeyframe) in **both foreground and background**, so apps can record to disk or run custom processing while the Flutter `Texture` can't render. Zero per-frame cost when no subscriber is attached. iOS emits BGRA for `raw` and raw `hvc1` NAL units for `hvc1`; Android emits I420 planar YUV (`width * height * 3/2` bytes) verbatim from the SDK.
* New `BackgroundNotification` value type for configuring the Android foreground service notification.

## 0.2.2
* **iOS**: `VideoCodec.hvc1` — invalidate `VTDecompressionSession` in background and recreate on foreground; stream session stays alive.

## 0.2.1
* Add AI coding agent configs (`AGENTS.md`, Claude Code, Cursor, Copilot) with `install-skills.sh` installer.

## 0.2.0
* **BREAKING**: Update to DAT SDK 0.5.0 on iOS and Android.
* `startStreamSession()` gains `videoCodec` and new `VideoCodec`: `raw` (default, foreground-only) or `hvc1` (compressed HEVC, background-friendly, iOS only).
* New `streamSessionStateStream()` and `streamSessionErrorStream()` to observe session lifecycle (stopped, streaming, paused, …) and errors such as thermal limits; adds `StreamSessionState` and `StreamSessionError`.
* `capturePhoto()` gains `format` and new `PhotoCaptureFormat`: `heic` or `jpeg` (default `jpeg`).
* **Android**: Photo capture failures use typed `CaptureError` (e.g. DeviceDisconnected, NotStreaming, CaptureInProgress, CaptureFailed).
* High-resolution streaming at 720×1280 works reliably on both platforms.

## 0.1.2
* Add `captureStreamFrame` method.

## 0.1.1
* Add performance optimizations.

## 0.1.0
* Implement Texture API for streaming optimization.
* Add `streamQuality` parameter.
* Improve documentation and example app.

## 0.0.3
* Fix demo gif in README.

## 0.0.2
* Improve pub.dev package page.

## 0.0.1
* Initial release.
