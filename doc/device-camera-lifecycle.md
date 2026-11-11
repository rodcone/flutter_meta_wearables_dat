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

On Android, a device start waits up to 20 seconds, then requests cleanup if it
times out. Cleanup can wait a further 10 seconds for the SDK to confirm shutdown.
`stopDeviceSession` also waits up to 10 seconds and throws `STOP_TIMEOUT` when
shutdown is unconfirmed. The device-state stream remains `stopping` until the
SDK reports `stopped`; a retry waits for that confirmation before creating a new
session. A device-initiated stop emits one terminal `stopped`, after releasing
the camera and texture. Connection timeouts and failed session creation keep
`STREAM_ERROR` for legacy `startStreamSession` calls and use
`DEVICE_SESSION_ERROR` for `startDeviceSession`.

## Android device verification

Use paired glasses with camera permission granted and subscribe to
`deviceSessionStateStream()` before starting. Native unit tests simulate delayed
starts and missing stop acknowledgements; these steps check the physical device
behavior separately:

1. Run the separate-lifecycle sequence above. Confirm that stopping the camera
   leaves the device connected, and reattaching gives a working preview using
   the new texture ID.
2. With a camera stream running, power off the glasses. Confirm the preview is
   cleared and there is one terminal device `stopped`, with no later `stopping`
   event. Power the glasses on, wait for availability, and reconnect successfully.
3. Start a device session, then request `stopDeviceSession` while it is still
   starting. Confirm that start fails, stop completes when acknowledged, and a
   later start succeeds. Repeat using the combined `startStreamSession` and
   `stopStreamSession` calls: the failed start keeps `STREAM_ERROR`, and stop may
   report `SESSION_NOT_FOUND` if no camera was created. A later start must work.
4. If a start or stop times out, confirm that no successful connection or new
   texture is returned while the old session is still stopping. Once the SDK
   confirms `stopped` and the glasses are available, retry and verify streaming.
