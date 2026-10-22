import 'package:flutter/services.dart';
import 'package:flutter_meta_wearables_dat/flutter_meta_wearables_dat.dart';
import 'package:flutter_meta_wearables_dat/meta_wearables_dat_method_channel.dart';
import 'package:flutter_meta_wearables_dat/meta_wearables_dat_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const name = 'flutter_meta_wearables_dat/device_state';
  const codec = StandardMethodCodec();
  late List<String> calls;
  late MetaWearablesDatPlatform original;

  setUp(() {
    calls = [];
    original = MetaWearablesDatPlatform.instance;
    MetaWearablesDatPlatform.instance = MethodChannelMetaWearablesDat();
    messenger.setMockMessageHandler(name, (message) async {
      calls.add(codec.decodeMethodCall(message).method);
      return codec.encodeSuccessEnvelope(null);
    });
  });
  tearDown(() {
    MetaWearablesDatPlatform.instance = original;
    messenger.setMockMessageHandler(name, null);
  });

  Future<void> emit(Object? event) => messenger.handlePlatformMessage(
    name,
    codec.encodeSuccessEnvelope(event),
    (_) {},
  );

  test(
    'separate callers share one subscription and cancel independently',
    () async {
      final a = <DeviceState>[];
      final b = <DeviceState>[];
      final first = MetaWearablesDat.deviceStateStream().listen(a.add);
      final second = MetaWearablesDat.deviceStateStream().listen(b.add);
      await pumpEventQueue();
      expect(calls, ['listen']);
      await emit({'thermalLevel': 2, 'deviceId': 'a', 'batteryLevel': 80});
      await pumpEventQueue();
      expect(a.single.batteryLevel, 80);
      expect(b, a);
      await first.cancel();
      await pumpEventQueue();
      expect(calls, ['listen']);
      await emit({'thermalLevel': 2, 'deviceId': 'a', 'batteryLevel': 79});
      await pumpEventQueue();
      expect(a, hasLength(1));
      expect(b.last.batteryLevel, 79);
      await second.cancel();
      await pumpEventQueue();
      expect(calls, ['listen', 'cancel']);

      final next = <DeviceState>[];
      final third = MetaWearablesDat.deviceStateStream().listen(next.add);
      await pumpEventQueue();
      expect(calls, ['listen', 'cancel', 'listen']);
      expect(
        next,
        isEmpty,
        reason: 'The Dart stream does not replay cached readings',
      );
      await emit({'thermalLevel': 0, 'deviceId': null});
      await pumpEventQueue();
      expect(next.single.deviceId, isNull);
      expect(next.single.batteryLevel, isNull);
      await third.cancel();
    },
  );

  test(
    'channel errors propagate and a subsequent snapshot still arrives',
    () async {
      final errors = <Object>[];
      final events = <DeviceState>[];
      final sub = MetaWearablesDat.deviceStateStream().listen(
        events.add,
        onError: errors.add,
      );
      await pumpEventQueue();
      await messenger.handlePlatformMessage(
        name,
        codec.encodeErrorEnvelope(
          code: 'DEVICE_STATE_ERROR',
          message: 'Unavailable',
        ),
        (_) {},
      );
      await emit({'thermalLevel': 1});
      await pumpEventQueue();
      expect(
        errors.single,
        isA<PlatformException>().having(
          (e) => e.code,
          'code',
          'DEVICE_STATE_ERROR',
        ),
      );
      expect(events.single.thermalLevel, ThermalLevel.none);
      await sub.cancel();
    },
  );
}
