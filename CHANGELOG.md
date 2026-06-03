## 0.5.1
* Future-proof Android Gradle scripts for Flutter's [Built-in Kotlin migration](https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-plugin-authors). The Kotlin Gradle Plugin is now applied conditionally (`if (agpMajor < 9)`) — once a consumer upgrades to AGP 9, KGP will be auto-injected by Flutter's tooling and this plugin will stop contributing to the `Your app uses the following plugins that apply Kotlin Gradle Plugin (KGP)` warning. On AGP < 9 (current Flutter 3.44 baseline) nothing changes: KGP is still applied so the plugin continues to compile, and the warning continues to fire from this and other plugins in the same situation until the host app moves to AGP 9.
* Replace the deprecated `android.kotlinOptions { }` block with the modern top-level `kotlin.compilerOptions { }` DSL.
* **Android** `requestCameraPermission`: stop collapsing `RequestPermissionContract.parseResult` failures (`NO_DEVICE`, `REQUEST_TIMEOUT`, `CONNECTION_ERROR`, …) to `PermissionStatus.Denied`. Those now surface through `mapPermissionError` as typed `CameraPermissionException`s (`DEVICE_DISCONNECTED` / `INTERNAL_ERROR`), matching the contract the Dart side already documents — `false` means *user explicitly denied*, not "something went wrong".
* **iOS** `getCameraPermissionStatus`: stop swallowing every `MWDATCore.PermissionError` as `false`. The status check now routes through the same `mapPermissionError` helper as `requestCameraPermission`, so no-device / Meta-AI-missing / timeout cases are reported identically across iOS and Android.
* Gate `debugPrint` calls in the event-stream pipelines (`registrationState`, `streamSessionState`, `streamSessionError`, `activeDevice`, `videoStreamSize`, `deviceState`) behind `kDebugMode`. Flutter's `debugPrint` is *not* automatically a no-op in release builds, so previously consumers' release apps were emitting per-event plugin logs they had no way to silence.
* No API changes; consumers do not need to change anything beyond bumping the dependency.

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