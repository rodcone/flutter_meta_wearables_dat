This documentation folder contains the `CameraAccess` Android sample (Kotlin) from Meta. The Flutter `example` app replicates all features of this sample, providing a cross-platform equivalent for plugin users.

To keep the repository lightweight, the Android sample app is excluded via .gitignore. If needed, you can clone it directly from `https://github.com/facebook/meta-wearables-dat-android/tree/main/samples/CameraAccess`.

## Key SDK types (Android DAT 0.6.0)

### StreamSessionState enum
- `STARTING` — session is starting
- `STARTED` — session has started (pre-streaming)
- `STREAMING` — actively streaming video frames
- `STOPPING` — session is stopping
- `STOPPED` — session is fully stopped
- `CLOSED` — session is closed/disposed

### CaptureError sealed interface
- `CaptureError.DeviceDisconnected` — device was disconnected during capture
- `CaptureError.NotStreaming` — capture attempted when not streaming
- `CaptureError.CaptureInProgress` — another capture is already in progress
- `CaptureError.CaptureFailed` — capture failed for another reason

### PhotoData sealed class
- `PhotoData.Bitmap` — captured photo as an Android Bitmap
- `PhotoData.HEIC` — captured photo as HEIC-encoded ByteBuffer

### Platform differences from iOS

| Feature | iOS | Android |
|---------|-----|---------|
| Video codec selection | `raw` and `hvc1` | `raw` only (I420) |
| Background streaming | Yes (with `hvc1`) | No |
| Error publisher | `session.errorPublisher` flow | No native error flow |
| Session states | stopping, stopped, waitingForDevice, starting, streaming, paused | STARTING, STARTED, STREAMING, STOPPING, STOPPED, CLOSED |
| Photo format param | Selectable (HEIC/JPEG) | Device-determined |
| Photo capture result | `AnyListenerToken` pattern | `DatResult<PhotoData, CaptureError>` |
