import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_meta_wearables_dat_mock_device/flutter_meta_wearables_dat_mock_device.dart';

/// Provider to manage mock device operations and state.
/// Handles pairing, unpairing, and device state operations for mock devices.
class MockDeviceProvider extends ChangeNotifier {
  String? _deviceUUID;
  bool _isPoweredOn = false;
  bool _isDonned = false;
  CameraFacing? _cameraFacing;
  GlassesModel _selectedModel = GlassesModel.rayBanMeta;
  GlassesModel? _pairedModel;

  String? get deviceUUID => _deviceUUID;
  bool get hasDevice => _deviceUUID != null;
  bool get isPoweredOn => _isPoweredOn;
  bool get isDonned => _isDonned;

  /// `true` once the mock glasses are both powered on and donned — which is
  /// required before streaming / capture operations reflect anything.
  bool get isActive => _isPoweredOn && _isDonned;
  CameraFacing? get cameraFacing => _cameraFacing;

  /// The model to pair next (driven by the model picker in the UI).
  GlassesModel get selectedModel => _selectedModel;

  /// The model of the currently paired mock device, or `null` if none.
  GlassesModel? get pairedModel => _pairedModel;

  void selectModel(GlassesModel model) {
    if (_selectedModel == model) return;
    _selectedModel = model;
    notifyListeners();
  }

  Future<void> pairMockGlasses() async {
    unawaited(HapticFeedback.lightImpact());

    final deviceUUID = await MetaWearablesDatMockDevice.pairGlasses(
      model: _selectedModel,
    );
    _deviceUUID = deviceUUID;
    _pairedModel = _selectedModel;
    notifyListeners();
  }

  Future<void> unpairMockGlasses() async {
    if (_deviceUUID == null) return;
    await MetaWearablesDatMockDevice.unpairGlasses(_deviceUUID!);
    _deviceUUID = null;
    _pairedModel = null;
    _isPoweredOn = false;
    _isDonned = false;
    _cameraFacing = null;
    notifyListeners();
  }

  Future<void> powerOn() async {
    if (_deviceUUID == null) return;
    await MetaWearablesDatMockDevice.powerOn(_deviceUUID!);
    _isPoweredOn = true;
    // The SDK requires the device to be donned before streaming. The UI no
    // longer exposes don/doff as a separate step, so fold it into power-on.
    try {
      await MetaWearablesDatMockDevice.don(_deviceUUID!);
      _isDonned = true;
    } catch (e) {
      debugPrint('[MetaWearablesDAT] Auto-don after power on failed: $e');
    }
    notifyListeners();
  }

  Future<void> powerOff() async {
    if (_deviceUUID == null) return;
    await MetaWearablesDatMockDevice.powerOff(_deviceUUID!);
    _isPoweredOn = false;
    _isDonned = false;
    notifyListeners();
  }

  Future<void> setCameraFacing(CameraFacing facing) async {
    if (_deviceUUID == null) return;
    await MetaWearablesDatMockDevice.setCameraFacing(_deviceUUID!, facing);
    _cameraFacing = facing;
    notifyListeners();
  }

  /// Clear the local camera-facing selection without issuing a native call —
  /// used when the user switches from the "Live camera" feed mode to the
  /// "Media" mode, so the UI no longer highlights a facing button.
  void clearCameraFacing() {
    if (_cameraFacing == null) return;
    _cameraFacing = null;
    notifyListeners();
  }
}
