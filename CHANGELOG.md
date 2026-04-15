## 0.2.2
* **iOS**: Safely manage `VTDecompressionSession` across app lifecycle when using `VideoCodec.hvc1`. The hardware HEVC decoder is now invalidated on app background entry (required by iOS — GPU access is forbidden while backgrounded) and recreated lazily on foreground return. The underlying `StreamSession` stays alive throughout; rendering resumes instantly without flicker when the app returns to foreground.

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