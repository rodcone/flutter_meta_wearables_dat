# Mock device testing

## Overview

MockDeviceKit simulates Meta glasses for development and testing without physical hardware. Available on both iOS and Android.

## Creating a mock device

```dart
final deviceUUID = await MetaWearablesDat.pairMockRayBanMeta();
// Returns a UUID string, e.g. "550e8400-e29b-41d4-a716-446655440000"
```

## Simulating device lifecycle

```dart
// Power on the glasses
await MetaWearablesDat.mockDevicePowerOn(deviceUUID!);

// Simulate wearing the glasses (required for streaming)
await MetaWearablesDat.mockDeviceDon(deviceUUID);

// Later — simulate removing
await MetaWearablesDat.mockDeviceDoff(deviceUUID);

// Power off
await MetaWearablesDat.mockDevicePowerOff(deviceUUID);
```

## Setting mock camera feed

```dart
// Video must be H.265/HEVC format
await MetaWearablesDat.setMockCameraFeed(deviceUUID, videoPath);

// Set image for photo capture
await MetaWearablesDat.setMockCapturedImage(deviceUUID, imagePath);
```

**Video format requirement:** Mock video files must be in H.265 (HEVC) format. Convert with:

```bash
ffmpeg -i input.mp4 -c:v libx265 -tag:v hvc1 output.mov
```

## Streaming with mock device

```dart
// Pass the specific deviceUUID (not null) for mock devices
final textureId = await MetaWearablesDat.startStreamSession(
  deviceUUID,
  fps: 24,
  streamQuality: StreamQuality.low,
);
```

## Cleanup

```dart
await MetaWearablesDat.stopStreamSession(deviceUUID);
await MetaWearablesDat.unpairMockRayBanMeta(deviceUUID);
```

## Key differences from real devices

- Pass the specific `deviceUUID` to streaming methods (not `null`)
- No registration or camera permission flow needed
- Device is always "available" after powerOn + don
- Video feed comes from your file, not a camera

## Reference implementation

See `example/lib/providers/mock_device_provider.dart` for the canonical pattern.
