# Camera streaming

## Prerequisites

- Registration complete (`RegistrationState.registered`)
- Camera permission granted (`requestCameraPermission()` returned `true`)

## Starting a stream session

```dart
// Subscribe to state and error streams BEFORE starting
final stateSub = MetaWearablesDat.streamSessionStateStream().listen((state) {
  // StreamSessionState: stopping, stopped, waitingForDevice, starting, streaming, paused
});

final errorSub = MetaWearablesDat.streamSessionErrorStream().listen((error) {
  // StreamSessionError: code + message
  if (error.isThermalCritical) { /* device overheating — stream paused */ }
  if (error.isHingesClosed) { /* glasses folded */ }
  if (error.code == 'datAppOnTheGlassesUpdateRequired') {
    // On-device DAT app needs updating — bounce user to Meta AI
    MetaWearablesDat.openDATGlassesAppUpdate();
  }
  // Other 0.5.0 codes: thermalEmergency, peakPowerShutdown, batteryCritical,
  // deviceThermalCritical, deviceThermalEmergency, devicePeakPowerShutdown,
  // deviceBatteryCritical, dwaUnavailable.
});

// Start streaming — returns texture ID
final textureId = await MetaWearablesDat.startStreamSession(
  null, // null = AutoDeviceSelector (recommended for real devices)
  fps: 24,
  streamQuality: StreamQuality.low,
  videoCodec: VideoCodec.raw,
);

// Render with Flutter's Texture widget — zero-copy GPU pipeline
Texture(textureId: textureId)
```

## Video codecs

| Codec | Platform | Description |
|-------|----------|-------------|
| `VideoCodec.raw` | iOS & Android | Raw uncompressed frames. iOS: BGRA. Android: I420 planar YUV. Default. |
| `VideoCodec.hvc1` | iOS only | Compressed HEVC. Smaller over-the-wire payload than `raw`. Without `enableBackgroundStreaming()`, also survives a brief background transition — HEVC decoder auto-paused on background, auto-recreated on foreground. Ignored on Android. |

## Background streaming (optional — both platforms, both codecs)

Call **before** `startStreamSession()` to keep the session alive when the host app is backgrounded, the phone is locked, or both.

```dart
await MetaWearablesDat.enableBackgroundStreaming(
  androidNotification: const BackgroundNotification(
    title: 'Streaming from your glasses',
    text: 'Keeps the camera stream alive in the background.',
    channelId: 'myapp.streaming',
    channelName: 'Camera Stream',
    // iconResourceName: 'ic_stat_recording', // optional, falls back to app icon
  ),
);

final textureId = await MetaWearablesDat.startStreamSession(null);

// ...when done:
await MetaWearablesDat.stopStreamSession(null);
await MetaWearablesDat.disableBackgroundStreaming();
```

**iOS `Info.plist`**: add `audio` and `bluetooth-central` to `UIBackgroundModes` on top of the default entries. No other code changes.

**Android manifest**: nothing to change — the plugin manifest auto-merges `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_CONNECTED_DEVICE`, `WAKE_LOCK` and the internal foreground service. `BackgroundNotification` is required on Android (OS mandate).

**How it works.** iOS activates an `AVAudioSession` to keep the process scheduled in background; the HEVC hardware decoder is invalidated on background and recreated on the first frame after foreground (brief keyframe-wait stall, no freeze). Raw hvc1 NAL bytes still flow to `videoFramesStream()` while backgrounded for recording. Android starts a foreground service of type `connectedDevice` with a customizable notification and a `PARTIAL_WAKE_LOCK`.

**Frames in background.** The `Texture` widget can't render in background (no GPU access), but every frame is still emitted on `videoFramesStream()`:

```dart
final framesSub = MetaWearablesDat.videoFramesStream().listen((frame) {
  // frame.codec, frame.bytes, frame.width, frame.height,
  // frame.presentationTimestampUs, frame.isKeyframe
});
```

Payload layout:

| Codec | iOS bytes | Android bytes |
|-------|-----------|---------------|
| `raw` | BGRA, `width * height * 4` | I420 planar YUV, `width * height * 3/2` |
| `hvc1` | HEVC NAL units (self-contained: keyframes carry VPS/SPS/PPS) | n/a |

`videoFramesStream()` is zero-cost when no subscriber is attached. Subscribe **before** `startStreamSession()` to capture the opening keyframe. `captureStreamFrame` still returns `null` while backgrounded — use `videoFramesStream()` for pixel data in background.

**Without `enableBackgroundStreaming()`**, the SDK stops delivering frames when the host OS suspends the app. Exception: `VideoCodec.hvc1` on iOS survives brief transitions via the auto-managed decoder lifecycle (for long-lived background, still call `enableBackgroundStreaming()`).

## Stream quality (resolution)

| Quality | Resolution |
|---------|-----------|
| `StreamQuality.low` | 360 x 640 |
| `StreamQuality.medium` | 504 x 896 |
| `StreamQuality.high` | 720 x 1280 |

**Valid FPS values:** 2, 7, 15, 24, 30

Lower resolution and frame rate yield higher visual quality due to less Bluetooth compression.

## Device thermal monitoring (optional)

`deviceStateStream()` emits `DeviceState` whenever the active device's thermal level changes. Subscribe to drive a "device is getting hot" indicator *before* a thermal error stops the stream.

```dart
final thermalSub = MetaWearablesDat.deviceStateStream().listen((state) {
  // state.thermalLevel: unknown, none, light, moderate, severe, critical, emergency, shutdown
});
```

The stream switches its underlying subscription automatically when the active device changes; emits nothing while no device is active. Surface UI at `severe` / `critical` — by `emergency` the stream has already stopped.

## StreamSessionState values

| State | Int | Meaning |
|-------|-----|---------|
| `stopping` | 0 | Session is stopping |
| `stopped` | 1 | Session is stopped |
| `waitingForDevice` | 2 | Waiting for device to become available |
| `starting` | 3 | Session is starting |
| `streaming` | 4 | Actively streaming |
| `paused` | 5 | Temporarily paused |

## Photo capture during streaming

```dart
final photo = await MetaWearablesDat.capturePhoto(
  null, // or specific deviceUUID
  format: PhotoCaptureFormat.jpeg, // or .heic (iOS only)
);
// photo.bytes — Uint8List of the image
// photo.format — "jpeg" or "heic"
// photo.fileExtension — "jpg" or "heic"
// photo.mimeType — "image/jpeg" or "image/heic"
```

## Raw frame capture for ML/OCR

```dart
// Dart-side rasterization — no native call, near-instantaneous
final frame = await MetaWearablesDat.captureStreamFrame(
  textureId,
  width: 720,
  height: 1280,
  format: FrameFormat.rawRgba, // 4 bytes per pixel
);
if (frame != null) {
  // frame.bytes — raw RGBA pixel data (~3.7 MB at 720x1280)
  await runOcr(frame.bytes, frame.width, frame.height);
}
```

Capture every 200-500ms (e.g., with `Timer.periodic`), not every rendered frame.

## Stopping

```dart
await MetaWearablesDat.stopStreamSession(null);
// Cancel subscriptions
stateSub.cancel();
errorSub.cancel();
```

## Reference implementation

See `example/lib/providers/stream_provider.dart` for the canonical pattern.
