# Mock device testing

## Overview

MockDeviceKit simulates Meta glasses for development and testing without physical hardware. Available on both iOS and Android.

Since `flutter_meta_wearables_dat` 0.4.0 the mock APIs live in a separate optional package, **`flutter_meta_wearables_dat_mock_device`**. Production builds that don't depend on it never link `MWDATMockDevice.xcframework` (iOS) or `mwdat-mockdevice` (Android), and therefore don't need to declare `NSCameraUsageDescription` (iOS) or the `CAMERA` permission (Android).

## Add the package (dev/staging only)

```yaml
# pubspec.yaml
dependencies:
  flutter_meta_wearables_dat: ^0.6.0
  flutter_meta_wearables_dat_mock_device: ^0.6.0
```

```dart
import 'package:flutter_meta_wearables_dat/flutter_meta_wearables_dat.dart';
import 'package:flutter_meta_wearables_dat_mock_device/flutter_meta_wearables_dat_mock_device.dart';
```

> Apps that pull in this package **must** declare `NSCameraUsageDescription` (iOS) and the `CAMERA` permission (Android) — the mock device drives the simulated feed from the phone's camera. The `Permission`, `PermissionStatus`, and `CameraFacing` enums also live in this package.

## Pre-grant registration + camera (optional)

The real-device flow requires registration through Meta AI and a camera permission grant. For mock testing you usually want to skip both:

```dart
await MetaWearablesDatMockDevice.configure(
  initiallyRegistered: true,
  initialPermissionsGranted: true,
);
```

## Creating a mock device

```dart
// `model` defaults to GlassesModel.rayBanMeta. Other values: oakleyMetaHSTN,
// oakleyMetaVanguard, rayBanMetaOptics, metaGlasses.
final deviceUUID = await MetaWearablesDatMockDevice.pairGlasses();
// Returns a UUID string, e.g. "550e8400-e29b-41d4-a716-446655440000"
```

## Simulating device lifecycle

```dart
// Power on the glasses
await MetaWearablesDatMockDevice.powerOn(deviceUUID!);

// Simulate wearing the glasses (required for streaming)
await MetaWearablesDatMockDevice.don(deviceUUID);

// Later — simulate removing
await MetaWearablesDatMockDevice.doff(deviceUUID);

// Power off
await MetaWearablesDatMockDevice.powerOff(deviceUUID);
```

## Setting mock camera feed

```dart
// Pick which side camera the simulated glasses use
await MetaWearablesDatMockDevice.setCameraFacing(deviceUUID, CameraFacing.back);

// Override the live camera with a pre-recorded clip (must be H.265/HEVC)
await MetaWearablesDatMockDevice.setCameraFeed(deviceUUID, videoPath);

// Override the photo returned by capturePhoto()
await MetaWearablesDatMockDevice.setCapturedImage(deviceUUID, imagePath);
```

**Video format requirement:** Mock video files must be in H.265 (HEVC) format. Convert with:

```bash
ffmpeg -i input.mp4 -c:v libx265 -tag:v hvc1 output.mov
```

## Streaming with mock device

Streaming, photo capture, registration state, etc. all go through the **core** `MetaWearablesDat` API against the mock UUID — the mock package only owns lifecycle/feed control:

```dart
final textureId = await MetaWearablesDat.startStreamSession(
  deviceUUID,
  fps: 24,
  streamQuality: StreamQuality.low,
);
```

## Cleanup

```dart
await MetaWearablesDat.stopStreamSession(deviceUUID);
await MetaWearablesDatMockDevice.unpairGlasses(deviceUUID);
```

## Key differences from real devices

- Pass the specific `deviceUUID` to streaming methods (not `null`)
- No registration or camera permission flow needed if you call `MetaWearablesDatMockDevice.configure(initiallyRegistered: true, initialPermissionsGranted: true)`
- Device is always "available" after `powerOn` + `don`
- Video feed comes from the phone's camera (or a pre-recorded clip you set via `setCameraFeed`), not from glasses

## Reference implementation

See `example/lib/providers/mock_device_provider.dart` for the canonical pattern.
