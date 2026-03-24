## 0.2.0
* **BREAKING**: Update to DAT SDK 0.5.0 (iOS).
* Add `VideoCodec` enum — choose between `raw` (default, foreground-only) and `hvc1` (compressed HEVC, works in background).
* Add `videoCodec` parameter to `startStreamSession()`.
* Add `streamSessionStateStream()` — observe stream session state changes (stopped, streaming, paused, etc.).
* Add `streamSessionErrorStream()` — receive stream errors including `thermalCritical` for device overheating.
* Add `StreamSessionState` enum and `StreamSessionError` class.
* Add `PhotoCaptureFormat` enum — choose between `heic` and `jpeg` when capturing photos.
* Add `format` parameter to `capturePhoto()` (default: `jpeg`).
* High resolution streaming (720x1280) now works reliably.

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