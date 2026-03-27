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
  if (error.isThermalCritical) { /* device overheating */ }
  if (error.isHingesClosed) { /* glasses folded */ }
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
| `VideoCodec.raw` | iOS & Android | Raw uncompressed frames. Foreground only. Default. |
| `VideoCodec.hvc1` | iOS only | Compressed HEVC. Foreground + background streaming. Ignored on Android. |

## Stream quality (resolution)

| Quality | Resolution |
|---------|-----------|
| `StreamQuality.low` | 360 x 640 |
| `StreamQuality.medium` | 504 x 896 |
| `StreamQuality.high` | 720 x 1280 |

**Valid FPS values:** 2, 7, 15, 24, 30

Lower resolution and frame rate yield higher visual quality due to less Bluetooth compression.

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
