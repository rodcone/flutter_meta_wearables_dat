import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_meta_wearables_dat_mock_device/flutter_meta_wearables_dat_mock_device.dart';

/// Meta's Mock Device Kit allows up to three simulated pairs at once.
const int maxMockDevices = 3;

/// One simulated pair of glasses and its locally tracked state.
class MockGlasses {
  MockGlasses({required this.uuid, required this.model});

  final String uuid;
  final GlassesModel model;
  bool isPoweredOn = false;
  bool isDonned = false;
  CameraFacing? cameraFacing;
}

/// Provider to manage mock device operations and state.
/// Handles pairing, unpairing, and device state operations for mock devices.
class MockDeviceProvider extends ChangeNotifier {
  final List<MockGlasses> _devices = <MockGlasses>[];
  GlassesModel _selectedModel = GlassesModel.rayBanMeta;

  /// Every paired mock, in pairing order.
  List<MockGlasses> get devices => List.unmodifiable(_devices);

  /// UUIDs of every paired mock.
  Set<String> get deviceUUIDs => {for (final d in _devices) d.uuid};

  bool get hasDevice => _devices.isNotEmpty;
  bool get canPairMore => _devices.length < maxMockDevices;

  /// The model to pair next (driven by the model picker in the UI).
  GlassesModel get selectedModel => _selectedModel;

  MockGlasses? _find(String uuid) {
    for (final d in _devices) {
      if (d.uuid == uuid) return d;
    }
    return null;
  }

  void selectModel(GlassesModel model) {
    if (_selectedModel == model) return;
    _selectedModel = model;
    notifyListeners();
  }

  Future<void> pairMockGlasses() async {
    if (!canPairMore) return;
    unawaited(HapticFeedback.lightImpact());

    final uuid = await MetaWearablesDatMockDevice.pairGlasses(
      model: _selectedModel,
    );
    if (uuid == null) return;
    _devices.add(MockGlasses(uuid: uuid, model: _selectedModel));
    notifyListeners();
  }

  Future<void> unpairMockGlasses(String uuid) async {
    final device = _find(uuid);
    if (device == null) return;
    await MetaWearablesDatMockDevice.unpairGlasses(uuid);
    _devices.remove(device);
    notifyListeners();
  }

  Future<void> powerOn(String uuid) async {
    final device = _find(uuid);
    if (device == null) return;
    await MetaWearablesDatMockDevice.powerOn(uuid);
    device.isPoweredOn = true;
    // The SDK requires the device to be donned before streaming. The UI no
    // longer exposes don/doff as a separate step, so fold it into power-on.
    try {
      await MetaWearablesDatMockDevice.don(uuid);
      device.isDonned = true;
    } catch (e) {
      debugPrint('[MetaWearablesDAT] Auto-don after power on failed: $e');
    }
    notifyListeners();
  }

  Future<void> powerOff(String uuid) async {
    final device = _find(uuid);
    if (device == null) return;
    await MetaWearablesDatMockDevice.powerOff(uuid);
    device
      ..isPoweredOn = false
      ..isDonned = false;
    notifyListeners();
  }

  Future<void> setCameraFacing(String uuid, CameraFacing facing) async {
    final device = _find(uuid);
    if (device == null) return;
    await MetaWearablesDatMockDevice.setCameraFacing(uuid, facing);
    device.cameraFacing = facing;
    notifyListeners();
  }

  /// Clear the local camera-facing selection without issuing a native call —
  /// used when the user switches from the "Live camera" feed mode to the
  /// "Media" mode, so the UI no longer highlights a facing button.
  void clearCameraFacing(String uuid) {
    final device = _find(uuid);
    if (device == null || device.cameraFacing == null) return;
    device.cameraFacing = null;
    notifyListeners();
  }
}
