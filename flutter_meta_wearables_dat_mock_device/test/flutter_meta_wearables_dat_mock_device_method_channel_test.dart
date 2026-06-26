import 'package:flutter/services.dart';
import 'package:flutter_meta_wearables_dat_mock_device/flutter_meta_wearables_dat_mock_device.dart';
import 'package:flutter_meta_wearables_dat_mock_device/flutter_meta_wearables_dat_mock_device_method_channel.dart';
import 'package:flutter_meta_wearables_dat_mock_device/flutter_meta_wearables_dat_mock_device_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('flutter_meta_wearables_dat_mock_device');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final platform = MethodChannelMetaWearablesDatMockDevice();

  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'pairGlasses') return 'mock-uuid';
      return true;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  group('pairGlasses', () {
    test('defaults to rayBanMeta and returns the device UUID', () async {
      final uuid = await platform.pairGlasses();
      expect(uuid, 'mock-uuid');
      expect(calls.single.method, 'pairGlasses');
      expect(calls.single.arguments, {'model': 'rayBanMeta'});
    });

    test('sends the selected model token for every GlassesModel', () async {
      for (final model in GlassesModel.values) {
        calls.clear();
        await platform.pairGlasses(model: model);
        expect(calls.single.method, 'pairGlasses');
        expect(calls.single.arguments, {'model': model.value});
      }
    });
  });

  test('unpairGlasses sends the deviceUUID', () async {
    final ok = await platform.unpairGlasses('uuid-123');
    expect(ok, isTrue);
    expect(calls.single.method, 'unpairGlasses');
    expect(calls.single.arguments, {'deviceUUID': 'uuid-123'});
  });

  test('facade delegates pairGlasses(model) to the platform instance', () async {
    final fake = _FakeMockPlatform();
    MetaWearablesDatMockDevicePlatform.instance = fake;

    final uuid = await MetaWearablesDatMockDevice.pairGlasses(
      model: GlassesModel.oakleyMetaHSTN,
    );

    expect(fake.lastModel, GlassesModel.oakleyMetaHSTN);
    expect(uuid, 'fake-uuid');
  });
}

class _FakeMockPlatform extends MetaWearablesDatMockDevicePlatform {
  GlassesModel? lastModel;

  @override
  Future<String?> pairGlasses({
    GlassesModel model = GlassesModel.rayBanMeta,
  }) async {
    lastModel = model;
    return 'fake-uuid';
  }
}
