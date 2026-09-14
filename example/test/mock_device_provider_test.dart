import 'package:flutter/services.dart';
import 'package:flutter_meta_wearables_dat_example/providers/mock_device_provider.dart';
import 'package:flutter_test/flutter_test.dart';

/// Drives [MockDeviceProvider] against a stubbed mock-device channel so the
/// pairing, power and unpair bookkeeping can be checked without glasses or a
/// phone. Mirrors the first steps of doc/MOCK_DEVICE_VALIDATION.md.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_meta_wearables_dat_mock_device');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> calls;
  var nextUuid = 0;

  setUp(() {
    calls = [];
    nextUuid = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'pairGlasses') return 'mock-${nextUuid++}';
      return true;
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('pairing appends a device per call and stops at the cap', () async {
    final mp = MockDeviceProvider();
    for (var i = 0; i < maxMockDevices + 1; i++) {
      await mp.pairMockGlasses();
    }
    expect(mp.devices.length, maxMockDevices);
    expect(mp.canPairMore, isFalse);
    expect(
      calls.where((c) => c.method == 'pairGlasses').length,
      maxMockDevices,
    );
    expect(mp.deviceUUIDs, {'mock-0', 'mock-1', 'mock-2'});
  });

  test('power on dons the device and only that device', () async {
    final mp = MockDeviceProvider();
    await mp.pairMockGlasses();
    await mp.pairMockGlasses();

    await mp.powerOn('mock-1');

    expect(mp.devices[0].isPoweredOn, isFalse);
    expect(mp.devices[1].isPoweredOn, isTrue);
    expect(mp.devices[1].isDonned, isTrue);
    expect(
      calls.map((c) => '${c.method}:${(c.arguments as Map?)?['deviceUUID']}'),
      containsAllInOrder(['powerOn:mock-1', 'don:mock-1']),
    );

    await mp.powerOff('mock-1');
    expect(mp.devices[1].isPoweredOn, isFalse);
    expect(mp.devices[1].isDonned, isFalse);
  });

  test('unpairing removes only the named device and reopens the cap', () async {
    final mp = MockDeviceProvider();
    for (var i = 0; i < maxMockDevices; i++) {
      await mp.pairMockGlasses();
    }

    await mp.unpairMockGlasses('mock-1');

    expect(mp.deviceUUIDs, {'mock-0', 'mock-2'});
    expect(mp.canPairMore, isTrue);
    await mp.unpairMockGlasses('not-paired');
    expect(mp.devices.length, 2);
  });
}
