## 0.8.0

* Update to Meta Wearables DAT **0.9.0**.
* **Minimum iOS deployment target is now 17.2** (was 17.0), matching the core package.
* **Changed — action may be required.** iOS mock devices now run the same `Info.plist`-based link-availability check as real hardware. An app that only ever used the mock could previously omit the transport keys; from this release it fails exactly as a real device would. Declare `NSBluetoothAlwaysUsageDescription` at minimum, plus `NSLocalNetworkUsageDescription` and `NSBonjourServices` if you exercise the Wi-Fi transport. No Dart API change.
* Upstream fix: the phone-camera mock feed no longer dies after a few seconds.
* Android: `mwdat-mockdevice` now ships `-dontwarn` consumer ProGuard rules, so R8 no longer needs app-side suppressions for it.

## 0.7.2

* Align version with core package's 0.7.2 release. No API changes.


## 0.7.1

* Align version with core package's 0.7.1 release. No API changes.

## 0.7.0

* Update to Meta Wearables DAT **0.8.0**.
* **BREAKING:** `pairRayBanMeta()` → `pairGlasses({GlassesModel model = GlassesModel.rayBanMeta})` and `unpairRayBanMeta(uuid)` → `unpairGlasses(uuid)`.
* New `GlassesModel` enum to simulate any supported model: `rayBanMeta`, `oakleyMetaHSTN`, `oakleyMetaVanguard`, `rayBanMetaOptics`, `metaGlasses`.

## 0.6.1

* Align version with core package's 0.6.1 release. No API changes.

## 0.6.0

* Version aligned with the core package's 0.6.0 release (read-only `getDevices()`). No mock-add-on API changes.

## 0.5.3

* Docs: clarify that `setPermission` / `setPermissionRequestResult` are iOS only — the Android mock SDK exposes no permission-injection hook, so they no-op there. Version aligned with the core package.

## 0.5.2

* iOS: Add Swift Package Manager support alongside CocoaPods.

## 0.5.1

* Prepare Android Gradle for Flutter's Built-in Kotlin migration.

## 0.5.0

* Update to DAT SDK 0.7.0. Drop-in upgrade — no API changes.
* Inherits DAT 0.7.0 fixes: fold/unfold-and-don/doff cycles now keep consistent device state on both platforms.
* Captouch simulation (`tap`, `tapAndHold`) is new in DAT 0.7.0 but not yet exposed — flagged for a follow-up.

## 0.4.0

* Initial release. Extracted from `flutter_meta_wearables_dat` 0.3.x to keep MockDeviceKit (and its `AVFoundation` / `Camera` linkage) out of production apps.

### Migration from `flutter_meta_wearables_dat` 0.3.x

Mock device APIs moved to this package and were renamed (the `Mock*` prefix on each method is now redundant given the namespace):

| Before | After |
|---|---|
| `MetaWearablesDat.configureMockDevices(...)` | `MetaWearablesDatMockDevice.configure(...)` |
| `MetaWearablesDat.disableMockDevices()` | `MetaWearablesDatMockDevice.disable()` |
| `MetaWearablesDat.pairMockRayBanMeta()` | `MetaWearablesDatMockDevice.pairRayBanMeta()` |
| `MetaWearablesDat.unpairMockRayBanMeta(uuid)` | `MetaWearablesDatMockDevice.unpairRayBanMeta(uuid)` |
| `MetaWearablesDat.setMockPermission(p, s)` | `MetaWearablesDatMockDevice.setPermission(p, s)` |
| `MetaWearablesDat.setMockPermissionRequestResult(p, s)` | `MetaWearablesDatMockDevice.setPermissionRequestResult(p, s)` |
| `MetaWearablesDat.mockDevicePowerOn(uuid)` | `MetaWearablesDatMockDevice.powerOn(uuid)` |
| `MetaWearablesDat.mockDevicePowerOff(uuid)` | `MetaWearablesDatMockDevice.powerOff(uuid)` |
| `MetaWearablesDat.mockDeviceDon(uuid)` | `MetaWearablesDatMockDevice.don(uuid)` |
| `MetaWearablesDat.mockDeviceDoff(uuid)` | `MetaWearablesDatMockDevice.doff(uuid)` |
| `MetaWearablesDat.setMockCameraFeed(uuid, path)` | `MetaWearablesDatMockDevice.setCameraFeed(uuid, path)` |
| `MetaWearablesDat.setMockCameraFacing(uuid, f)` | `MetaWearablesDatMockDevice.setCameraFacing(uuid, f)` |
| `MetaWearablesDat.setMockCapturedImage(uuid, path)` | `MetaWearablesDatMockDevice.setCapturedImage(uuid, path)` |

The `Permission`, `PermissionStatus`, and `CameraFacing` enums also moved here.
