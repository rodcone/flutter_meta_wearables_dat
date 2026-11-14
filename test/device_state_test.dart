import 'package:flutter_meta_wearables_dat/flutter_meta_wearables_dat.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const payload = <String, Object?>{
    'deviceId': 'glasses-a',
    'linkState': 'connected',
    'compatibility': 'compatible',
    'thermalLevel': 3,
    'batteryLevel': 72,
    'chargingState': 'notCharging',
    'donState': 'donned',
    'hingeState': 'open',
  };

  test('old construction and thermal-only payload stay compatible', () {
    const legacy = DeviceState(thermalLevel: ThermalLevel.moderate);
    expect(DeviceState.fromMap({'thermalLevel': 3}), legacy);
    expect(legacy.deviceId, isNull);
    expect(legacy.batteryLevel, isNull);
    expect(legacy.linkState, WearableLinkState.unknown);
    expect(legacy.compatibility, WearableCompatibility.undefined);
    expect(legacy.chargingState, WearableChargingState.unknown);
    expect(legacy.donState, WearableDonState.unknown);
    expect(legacy.hingeState, WearableHingeState.unknown);
    for (final level in ThermalLevel.values) {
      expect(
        DeviceState.fromMap({'thermalLevel': level.value}).thermalLevel,
        level,
      );
    }
  });

  test('complete snapshot retains identity and all physical fields', () {
    final state = DeviceState.fromMap(payload);
    expect(state.deviceId, 'glasses-a');
    expect(state.linkState, WearableLinkState.connected);
    expect(state.compatibility, WearableCompatibility.compatible);
    expect(state.batteryLevel, 72);
    expect(state.chargingState, WearableChargingState.notCharging);
    expect(state.donState, WearableDonState.donned);
    expect(state.hingeState, WearableHingeState.open);
    expect(state.thermalLevel, ThermalLevel.moderate);
    expect(state, DeviceState.fromMap({...payload, 'futureField': true}));
    expect(state.hashCode, DeviceState.fromMap(payload).hashCode);
    expect(state.toString(), contains('batteryLevel: 72'));
  });

  test('value equality notices every field independently', () {
    final state = DeviceState.fromMap(payload);
    for (final entry in <String, Object?>{
      'deviceId': 'glasses-b',
      'linkState': 'disconnected',
      'compatibility': 'deviceUpdateRequired',
      'thermalLevel': 4,
      'batteryLevel': 71,
      'chargingState': 'charging',
      'donState': 'doffed',
      'hingeState': 'closed',
    }.entries) {
      final changed = DeviceState.fromMap({...payload, entry.key: entry.value});
      expect(changed, isNot(state), reason: entry.key);
      expect({state, changed}, hasLength(2), reason: entry.key);
    }
  });

  test('missing, malformed and future optional values remain unknown', () {
    for (final bad in <Object?>[null, true, 1, [], {}, 'future']) {
      final state = DeviceState.fromMap({
        'thermalLevel': 999,
        'chargingState': bad,
        'donState': bad,
        'hingeState': bad,
        'linkState': bad,
        'compatibility': bad,
      });
      expect(state, const DeviceState(thermalLevel: ThermalLevel.unknown));
    }
    for (final bad in <Object?>[null, true, 7, '', '  ']) {
      expect(DeviceState.fromMap({'deviceId': bad}).deviceId, isNull);
    }
    for (final bad in <Object?>[null, '3', 3.5, double.nan, double.infinity]) {
      expect(
        DeviceState.fromMap({'thermalLevel': bad}).thermalLevel,
        ThermalLevel.unknown,
      );
    }
  });

  test('battery accepts integer percentages including iOS zero', () {
    for (final value in [0, 1, 100, 72.0]) {
      expect(
        DeviceState.fromMap({'batteryLevel': value}).batteryLevel,
        value.toInt(),
      );
    }
    for (final value in <Object?>[
      null,
      -1,
      101,
      0.1,
      '72',
      true,
      double.nan,
      double.infinity,
    ]) {
      expect(
        DeviceState.fromMap({'batteryLevel': value}).batteryLevel,
        isNull,
        reason: '$value',
      );
    }
  });

  test('all new enum codes round trip without relying on ordinals', () {
    for (final state in WearableChargingState.values) {
      expect(WearableChargingState.fromCode(state.code), state);
    }
    for (final state in WearableDonState.values) {
      expect(WearableDonState.fromCode(state.code), state);
    }
    for (final state in WearableHingeState.values) {
      expect(WearableHingeState.fromCode(state.code), state);
    }
  });
}
