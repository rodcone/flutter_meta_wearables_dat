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