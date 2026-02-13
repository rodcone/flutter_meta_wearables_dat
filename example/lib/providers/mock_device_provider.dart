import 'package:flutter/foundation.dart';
import 'package:flutter_meta_wearables_dat/flutter_meta_wearables_dat.dart';

/// Provider to manage mock device operations and state.
/// Handles pairing, unpairing, and device state operations for mock devices.
class MockDeviceProvider extends ChangeNotifier {
  String? _deviceUUID;

  String? get deviceUUID => _deviceUUID;
  bool get hasDevice => _deviceUUID != null;

  Future<void> pairMockRayBanMeta() async {
    final deviceUUID = await MetaWearablesDat.pairMockRayBanMeta();
    _deviceUUID = deviceUUID;
    notifyListeners();
  }

  Future<void> unpairMockRayBanMeta() async {
    if (_deviceUUID == null) return;
    await MetaWearablesDat.unpairMockRayBanMeta(_deviceUUID!);
    _deviceUUID = null;
    notifyListeners();
  }

  Future<void> powerOn() async {
    if (_deviceUUID == null) return;
    await MetaWearablesDat.mockDevicePowerOn(_deviceUUID!);
    notifyListeners();
  }

  Future<void> powerOff() async {
    if (_deviceUUID == null) return;
    await MetaWearablesDat.mockDevicePowerOff(_deviceUUID!);
    notifyListeners();
  }

  Future<void> don() async {
    if (_deviceUUID == null) return;
    await MetaWearablesDat.mockDeviceDon(_deviceUUID!);
    notifyListeners();
  }

  Future<void> doff() async {
    if (_deviceUUID == null) return;
    await MetaWearablesDat.mockDeviceDoff(_deviceUUID!);
    notifyListeners();
  }
}
