![Pub Version](https://img.shields.io/pub/v/flutter_meta_wearables_dat_mock_device)
![Pub Likes](https://img.shields.io/pub/likes/flutter_meta_wearables_dat_mock_device)
![Pub Points](https://img.shields.io/pub/points/flutter_meta_wearables_dat_mock_device)
[![style: very good analysis](https://img.shields.io/badge/style-very_good_analysis-B22C89.svg)](https://pub.dev/packages/very_good_analysis)

# flutter_meta_wearables_dat_mock_device

Optional **MockDeviceKit** add-on for [`flutter_meta_wearables_dat`](https://pub.dev/packages/flutter_meta_wearables_dat). Simulates a Ray-Ban Meta backed by the phone's camera so you can exercise pairing / registration / streaming without physical glasses.

> **Add this only in dev/staging builds.** It vendors `MWDATMockDevice.xcframework` (iOS) and depends on `mwdat-mockdevice` (Android), which links `AVFoundation` / `Camera` symbols. Production apps should pull in the core plugin alone so they don't have to declare `NSCameraUsageDescription` (iOS) or the `CAMERA` permission (Android) just to ship.

## Setup

```yaml
# pubspec.yaml
dependencies:
  flutter_meta_wearables_dat: ^0.9.2
  flutter_meta_wearables_dat_mock_device: ^0.9.2
```

Apps using this package **must** declare the camera permission strings the simulated feed needs:

- **iOS** — `NSCameraUsageDescription` in `Info.plist`.
- **Android** — `<uses-permission android:name="android.permission.CAMERA" />` in `AndroidManifest.xml`.

**Since DAT 0.9.0, mock devices also require the same transport declarations as real hardware.** MockDeviceKit now runs the same `Info.plist`-based link-availability check, so a mock-only app that skipped these will fail exactly as a real device would: `NSBluetoothAlwaysUsageDescription` at minimum, plus `NSLocalNetworkUsageDescription` and `NSBonjourServices` if you exercise the Wi-Fi transport.

See the [core plugin's README](https://github.com/rodcone/flutter_meta_wearables_dat#readme) for the rest of the integration setup (Bluetooth, deep links, GitHub Packages repo, MainActivity).

## Usage

```dart
import 'package:flutter_meta_wearables_dat/flutter_meta_wearables_dat.dart';
import 'package:flutter_meta_wearables_dat_mock_device/flutter_meta_wearables_dat_mock_device.dart';

// Pre-grant registration + camera so the mock flow doesn't bounce through Meta AI
await MetaWearablesDatMockDevice.configure(
  initiallyRegistered: true,
  initialPermissionsGranted: true,
);

// `model` defaults to GlassesModel.rayBanMeta; pass any GlassesModel value.
final uuid = await MetaWearablesDatMockDevice.pairGlasses();
await MetaWearablesDatMockDevice.powerOn(uuid!);
await MetaWearablesDatMockDevice.don(uuid);
await MetaWearablesDatMockDevice.setCameraFacing(uuid, CameraFacing.back);

// Optional — replace the live camera with a pre-recorded H.265/HEVC clip
// await MetaWearablesDatMockDevice.setCameraFeed(uuid, videoPath);

// Streaming, photo capture, registration state, etc. all go through the core
// plugin against the mock UUID.
final textureId = await MetaWearablesDat.startStreamSession(uuid);
```

The `Permission`, `PermissionStatus`, and `CameraFacing` enums are exported from this package.

## API

| Method | Purpose |
|---|---|
| `configure({initiallyRegistered, initialPermissionsGranted})` | Reset & enable the mock subsystem |
| `disable()` | Tear down the mock subsystem |
| `pairGlasses({model})` / `unpairGlasses(uuid)` | Pair / unpair a simulated device (`model` defaults to `GlassesModel.rayBanMeta`) |
| `powerOn(uuid)` / `powerOff(uuid)` | Power the device on / off |
| `don(uuid)` / `doff(uuid)` | Simulate the user wearing / removing the glasses |
| `setCameraFacing(uuid, facing)` | Switch front / back camera |
| `setCameraFeed(uuid, path?)` | Override the camera feed with a video file (H.265/HEVC) |
| `setCapturedImage(uuid, path?)` | Override the photo returned by `capturePhoto` |
| `setPermission(p, s)` / `setPermissionRequestResult(p, s)` | Override permission state for testing |

## Migrating from `flutter_meta_wearables_dat` 0.3.x

Mock APIs used to live on the core plugin under `MetaWearablesDat.pairMockRayBanMeta()` etc. They moved here in 0.4.0 — see the [migration table in the changelog](CHANGELOG.md).

## Example app

The end-to-end example lives in the core plugin's repo and exercises the full flow including this add-on: see [`flutter_meta_wearables_dat/example`](https://github.com/rodcone/flutter_meta_wearables_dat/tree/main/example).

## License

MIT — see [LICENSE](LICENSE).
