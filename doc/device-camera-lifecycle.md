# Keep the device session connected between camera scans

The device session and its camera capability have separate lifetimes on DAT 1.0.

```dart
// Subscribe before starting. Parent stops remain observable with no camera.
final connection = MetaWearablesDat.deviceSessionStateStream().listen((state) {
  // Handle device-controlled pauses and terminal connection loss here.
});
final frames = MetaWearablesDat.videoFramesStream().listen((frame) {
  // Frames arrive only while a camera stream is started.
});
await MetaWearablesDat.startDeviceSession(null);
// Connected: no camera, no texture, no frames.
var textureId = await MetaWearablesDat.startCameraStream(null);
await MetaWearablesDat.stopCameraStream(null);
// Still connected. The old texture is released.
textureId = await MetaWearablesDat.startCameraStream(null);
// Render using the replacement textureId.
await MetaWearablesDat.stopDeviceSession(null);
await frames.cancel();
await connection.cancel();
```

Enable background streaming before connecting if this lifetime must survive a
locked/backgrounded phone, and disable it after ending the device session.
Camera stop does not disable background opt-in. Stops are idempotent. Lifecycle
commands are serialized; a stop invalidates earlier pending starts. Camera start
requires the matching started parent and never silently reconnects it. Native
startup/shutdown waits are bounded. Device-controlled pauses retain the SDK's
connection and recovery; there is no app `pause()` / `resume()` call.

Existing `startStreamSession` / `stopStreamSession` preserve their combined
connect/start and camera-plus-device-stop behavior.
