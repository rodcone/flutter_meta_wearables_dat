# Example

`flutter_meta_wearables_dat_mock_device` is the mock-device add-on for [`flutter_meta_wearables_dat`](https://pub.dev/packages/flutter_meta_wearables_dat). The end-to-end example — exercising mock pairing, power-on / don, camera-feed override, streaming, and photo capture against a simulated Ray-Ban Meta — lives in the core plugin's repo:

**See [`flutter_meta_wearables_dat/example`](https://github.com/rodcone/flutter_meta_wearables_dat/tree/main/example).**

For a minimal usage snippet, see the [package README](../README.md#usage).

## Quick reference

```dart
import 'package:flutter_meta_wearables_dat/flutter_meta_wearables_dat.dart';
import 'package:flutter_meta_wearables_dat_mock_device/flutter_meta_wearables_dat_mock_device.dart';

Future<void> main() async {
  await MetaWearablesDatMockDevice.configure(
    initiallyRegistered: true,
    initialPermissionsGranted: true,
  );

  final uuid = await MetaWearablesDatMockDevice.pairRayBanMeta();
  await MetaWearablesDatMockDevice.powerOn(uuid!);
  await MetaWearablesDatMockDevice.don(uuid);
  await MetaWearablesDatMockDevice.setCameraFacing(uuid, CameraFacing.back);

  // Streaming + capture flow through the core plugin against the mock UUID.
  final textureId = await MetaWearablesDat.startStreamSession(uuid);
  // ... render with `Texture(textureId: textureId)` ...
  await MetaWearablesDat.stopStreamSession(uuid);

  await MetaWearablesDatMockDevice.unpairRayBanMeta(uuid);
}
```
