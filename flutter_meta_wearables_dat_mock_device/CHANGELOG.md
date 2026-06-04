## 0.5.1

* Future-proof Android Gradle scripts for Flutter's [Built-in Kotlin migration](https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-plugin-authors). The Kotlin Gradle Plugin is now applied conditionally (`if (agpMajor < 9)`) — once a consumer upgrades to AGP 9, KGP will be auto-injected by Flutter's tooling and this plugin will stop contributing to the `Your app uses the following plugins that apply Kotlin Gradle Plugin (KGP)` warning. On AGP < 9 (current Flutter 3.44 baseline) nothing changes: KGP is still applied so the plugin continues to compile, and the warning continues to fire from this and other plugins in the same situation until the host app moves to AGP 9.
* Replace the deprecated `android.kotlinOptions { }` block with the modern top-level `kotlin.compilerOptions { }` DSL.
* No API changes; consumers do not need to change anything beyond bumping the dependency.

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
