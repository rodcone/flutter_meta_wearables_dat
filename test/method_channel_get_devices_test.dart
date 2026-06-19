import 'package:flutter/services.dart';
import 'package:flutter_meta_wearables_dat/flutter_meta_wearables_dat.dart';
import 'package:flutter_meta_wearables_dat/meta_wearables_dat_method_channel.dart';
import 'package:flutter_meta_wearables_dat/meta_wearables_dat_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('flutter_meta_wearables_dat');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final platform = MethodChannelMetaWearablesDat();

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('getDevices decodes a list of device maps', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'getDevices') return null;
      return <Object?>[
        <Object?, Object?>{
          'id': 'a',
          'name': 'Glasses A',
          'deviceType': 'rayBanMeta',
          'linkState': 'connected',
          'compatibility': 'compatible',
          'supportsDisplay': false,
          'isActive': true,
          'isStreamingDevice': true,
          'firmwareInfo': '1.0',
        },
        <Object?, Object?>{
          'id': 'b',
          'name': 'Glasses B',
          'deviceType': 'oakleyMetaVanguard',
          'linkState': 'disconnected',
          'compatibility': 'deviceUpdateRequired',
          'supportsDisplay': true,
          'isActive': false,
          'isStreamingDevice': false,
          'firmwareInfo': null,
        },
      ];
    });

    final devices = await platform.getDevices();
    expect(devices, hasLength(2));
    expect(devices[0].id, 'a');
    expect(devices[0].isStreamingDevice, isTrue);
    expect(devices[0].isActive, isTrue);
    expect(devices[1].type, WearableDeviceType.oakleyMetaVanguard);
    expect(devices[1].linkState, WearableLinkState.disconnected);
    expect(devices[1].supportsDisplay, isTrue);
    expect(devices[1].firmwareInfo, isNull);
  });

  test('getDevices returns an empty list when native returns null', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    expect(await platform.getDevices(), isEmpty);
  });

  test('getDevices propagates a PlatformException', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'NOT_INITIALIZED', message: 'nope');
    });
    expect(
      platform.getDevices(),
      throwsA(
        isA<PlatformException>().having(
          (e) => e.code,
          'code',
          'NOT_INITIALIZED',
        ),
      ),
    );
  });

  test('facade delegates getDevices to the platform instance', () async {
    final fake = _FakePlatform();
    MetaWearablesDatPlatform.instance = fake;

    final result = await MetaWearablesDat.getDevices();

    expect(fake.called, isTrue);
    expect(result, hasLength(1));
    expect(result.first.id, 'fake-1');
  });
}

class _FakePlatform extends MetaWearablesDatPlatform {
  bool called = false;

  @override
  Future<List<WearableDevice>> getDevices() async {
    called = true;
    return const [
      WearableDevice(
        id: 'fake-1',
        name: 'Fake',
        type: WearableDeviceType.rayBanMeta,
        linkState: WearableLinkState.connected,
        compatibility: WearableCompatibility.compatible,
        supportsDisplay: false,
        isActive: false,
        isStreamingDevice: false,
      ),
    ];
  }
}
