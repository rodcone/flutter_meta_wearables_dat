## 0.9.1

Contains contributions by [@kelvinharron](https://github.com/kelvinharron) — the AVAudioSession, stop-cascade, and HEVC keyframe work below.

**Fixed**

* **iOS: `enableBackgroundStreaming()` / `disableBackgroundStreaming()` no longer freeze the UI.** AVAudioSession activation and deactivation block for hundreds of milliseconds while the media server negotiates, and both ran inline on the platform thread. All session work now runs on a private serial queue; the Dart futures resolve when the work actually completes, and `disableBackgroundStreaming()` in particular now resolves only after the deactivation lands — await it before backgrounding if you rely on the keep-alive being gone.
* **iOS: a 0.9.0 defect that could strand the glasses after a background-stop timeout.** The `abortStopWait` flag set by an expiring background assertion was never cleared, so one expiry made every later teardown skip its stop-confirmation wait and release the stream mid-cascade — the stale-capability failure that makes the next start reject. Reset on foreground.
* **iOS: green / glitched frames in `videoFramesStream()` recordings.** The SDK's keyframe attachment is absent on most predicted frames, which read as keyframes, so VPS/SPS/PPS were prepended to nearly every P-frame and downstream decoders sampled mid-GOP entry points. Burst boundaries are now keyed off a NAL-unit scan for true IRAP pictures (the SDK flag is a fallback when framing can't be parsed), parameter sets are cached per session and prepended only where genuinely missing, and `isKeyframe` now means "self-decodable as shipped" — an IRAP that couldn't be made self-contained reports `false` rather than pointing a recorder at an undecodable segment start.
* **iOS `hvc1`: frame corruption and preview freezes after a mid-stream quality switch.** The glasses adapt stream quality to Bluetooth bandwidth a few seconds into a stream, announcing the switch with in-band VPS/SPS/PPS + IDR. The SDK's `CMFormatDescription` is not rebuilt when that happens, so the decoder rejected every post-switch frame as corrupt, sync frames included, and the preview froze until the parameters happened to match again. The decoder now rebuilds itself from the bitstream's in-band parameter sets and rewraps samples with that description, so the switch decodes seamlessly.
* **iOS `hvc1`: the FPS throttle no longer corrupts decode by dropping frames.** It ran ahead of the decoder, and every dropped P-frame broke the HEVC reference chain until the next sync frame. All frames are now decoded, in order on a serial queue; only the texture push is throttled.
* **iOS: stream and session stop-waits are event-driven** on the state publishers rather than 50ms polls, resolving as soon as the glasses acknowledge.
* Example: `flutter build apk` no longer fails on the current Flutter SDK (a `lintVitalRelease` false positive on `MainActivity`, now disabled with rationale).
* Android: the `AppForegroundTracker` logged under a different tag (`MWDAT`) than every other component (`MetaWearablesDat`), so the obvious logcat filter silently dropped the lifecycle lines.
* The background-stop error-suppression window now tracks the teardown's real worst case (15s, was 5s); it still closes early the moment teardown completes.

**Changed**

* **`stopStreamSession()` now ends the whole device session, on both platforms.** The glasses' stream-ended tone hangs off the session lifecycle, so the previous stream-only stop never chimed — the glasses only signalled when the app was backgrounded or killed. This matches Meta's CameraAccess sample and the 0.9.0 background path. **Trade-off:** the next `startStreamSession()` is a full session reconnect rather than a fast capability re-attach, so restart takes noticeably longer. The future also resolves only after the stop handshake completes (normally quick; bounded by backstops for a dead device).
* **iOS: the background-streaming keep-alive no longer requests Bluetooth HFP.** `.allowBluetoothHFP` exists for glasses-mic capture only; requesting it from the keep-alive dropped all glasses audio to 8 kHz mono and opened a SCO link that contended with the video stream for bandwidth. Glasses audio stays on A2DP; apps that want the glasses microphone configure HFP themselves.
* Example: the codec picker is platform-aware. iOS offers both codecs (`raw` remains the default); Android shows only `raw`. On iOS the background-streaming toggle animates out when `raw` is selected, and selecting `raw` also releases the keep-alive.
* `CameraPermissionException.toString()` now includes the `details` map when present.

## 0.9.0

**BREAKING CHANGES**

* **Backgrounding now stops the stream session unless you opt in.** Previously the plugin only stopped *rendering* while backgrounded on iOS and did nothing at all on Android, leaving a live session, an attached camera capability and a registered texture with no event to Dart — apps were left holding a texture id and a `Texture` frozen on its last frame. Now a true background transition (app backgrounded or phone locked) tears the `DeviceSession` down, emits a terminal `stopped`, and releases the texture. Call `enableBackgroundStreaming()` **before** `startStreamSession()` to keep the old behaviour.
* **There is no auto-resume.** Returning to the foreground does nothing by design — the plugin never reactivates the glasses camera on its own. Show your placeholder and let the user restart.
* **`startStreamSession()` now fails with `APP_BACKGROUNDED`** while the app is backgrounded and background streaming is off. Checked on entry and again at the final commit point, so a start that was in flight when the app backgrounded cannot leave a live stream running with nothing to stop it.
* **New `stoppedForBackground` code on `streamSessionErrorStream()`**, emitted just before the terminal `stopped`, so a deliberate stop is distinguishable from a fault. Exclude it from any retry logic.
* **iOS: raw-codec frames now reach `videoFramesStream()` while backgrounded.** `emitRaw` sat after the background guard while `emitHvc1` sat before it, so with `VideoCodec.raw` — the default — nothing was delivered in background despite the documented contract. Raw frames are also no longer FPS-throttled, matching hvc1 and Android; apps with a low `fps` subscribed to `videoFramesStream()` will see more callbacks.

**What you must change**

Subscribe to `streamSessionStateStream()` and clear your texture id on `StreamSessionState.stopped`. An app that caches the texture id and never listens will render an unregistered texture — black or frozen — after any background round trip.

**Fixes**

* **Android emitted no terminal `stopped` on any plugin-initiated teardown.** The state handler was detached before `stream.stop()`, so the SDK's `STOPPING`/`STOPPED` transitions were never observed. This affected every stop, not just backgrounding — the same bug iOS fixed in 0.8.1.
* **iOS lifecycle detection missed `UISceneDelegate` hosts entirely.** Flutter stops forwarding application lifecycle events once a host adopts scenes, and current Flutter templates are scene-based by default, so the plugin was silently blind on a growing share of apps. Lifecycle is now observed via `NotificationCenter`, which UIKit posts in both cases.
* Android gained process-wide foreground detection, which it had no notion of at all. Rotation, activity transitions and multi-window do not count as backgrounding.
* Teardown noise no longer surfaces as an error: the SDK's `videoStreamingError` during a deliberate background stop is suppressed for a bounded window, so apps stop showing "Video streaming encountered an error" for a clean shutdown.
* Android: the foreground service no longer resurrects itself after process death with default branding, no engine and an unstoppable wake lock; it also stops when the user swipes the app from Recents. The wake lock gained a timeout backstop.
* Transient interruptions never stop a stream: Control Center, the notification shade, the app-switcher preview and incoming-call banners on iOS; rotation and split-screen on Android.

**Added**

* `MetaWearablesDat.isBackgroundStreamingEnabled()` — reads the flag from the native side. Dart's copy drifts across a hot restart, where the isolate resets but the audio session or foreground service keeps running.

## 0.8.1
* **Stream teardowns are no longer silent.** iOS detached the stream-state handler *before* stopping the camera, so every plugin-initiated teardown — the device-availability watchdog, or a `DeviceSession` that stopped underneath us — reached Dart as nothing at all. Apps were left holding a live texture id and a `Texture` frozen on its last frame, with no state change and no error. `streamSessionStateStream()` now emits a terminal `stopped` on those paths.
* **The iOS device-availability watchdog no longer tears the session down on a transient link blip.** `activeDeviceStream()` yields `nil` as soon as no device satisfies the SDK's eligibility test, which requires `LinkState.connected` — so a momentary `.connecting` emitted `nil` even though the glasses never went away. The SDK's own handler stops the stream only on a genuine `.disconnected`. A 2 s grace period now has to elapse, and the selector is re-checked, before anything is torn down.
* **iOS `hvc1`: recover from a mid-stream codec-configuration change.** The `VTDecompressionSession` was built from the first frame's `CMFormatDescription` and cached forever. The glasses can push a new codec config mid-stream, after which every decode failed and — because the cached session stayed non-`nil` — nothing ever recreated it: a permanent freeze with no error on any channel. The session is now revalidated against each frame's format description and recreated when it no longer matches.

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
