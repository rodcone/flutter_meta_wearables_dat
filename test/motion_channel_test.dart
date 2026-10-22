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
  late MethodChannelMetaWearablesDat platform;

  setUp(() {
    platform = MethodChannelMetaWearablesDat();
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  group('Motion method channel', () {
    test('defaults to 10 Hz and auto-selects without a device ID', () async {
      MethodCall? received;
      messenger.setMockMethodCallHandler(channel, (call) async {
        received = call;
        return true;
      });

      expect(await platform.startMotion(null), isTrue);
      expect(received!.method, 'startMotion');
      expect(received!.arguments, {'samplingRate': 10});
    });

    test('forwards every supported rate and selected device', () async {
      Map<Object?, Object?>? arguments;
      messenger.setMockMethodCallHandler(channel, (call) async {
        arguments = call.arguments as Map<Object?, Object?>;
        return true;
      });

      for (final rate in MotionSamplingRate.values) {
        expect(
          await platform.startMotion('glasses-2', samplingRate: rate),
          isTrue,
        );
        expect(arguments, {
          'deviceId': 'glasses-2',
          'samplingRate': rate.value,
        });
      }
    });

    test('stops motion without stopping the camera', () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return true;
      });

      expect(await platform.stopMotion(), isTrue);
      expect(calls.map((call) => call.method), ['stopMotion']);
      expect(calls.single.arguments, isNull);
    });

    test('returns false for null native responses', () async {
      messenger.setMockMethodCallHandler(channel, (call) async => null);

      expect(await platform.startMotion(null), isFalse);
      expect(await platform.stopMotion(), isFalse);
    });

    test('preserves native method failures', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(
          code: 'MOTION_ACTIVE',
          message: 'Another device is active.',
          details: {'deviceId': 'other'},
        );
      });
      final failure = throwsA(
        isA<PlatformException>()
            .having((error) => error.code, 'code', 'MOTION_ACTIVE')
            .having(
              (error) => error.message,
              'message',
              'Another device is active.',
            )
            .having((error) => error.details, 'details', {'deviceId': 'other'}),
      );

      await expectLater(platform.startMotion(null), failure);
      await expectLater(platform.stopMotion(), failure);
    });
  });

  group('Motion event channels', () {
    test('decodes samples, unknown states, and error payloads', () async {
      messenger
        ..setMockStreamHandler(
          platform.motionSamplesEventChannel,
          MockStreamHandler.inline(
            onListen: (arguments, events) {
              events
                ..success({
                  'timestampNs': 9876543210,
                  'source': 'glasses',
                  'accelerometer': {'x': 1, 'y': 2.5, 'z': -3},
                  'orientation': null,
                })
                ..endOfStream();
            },
          ),
        )
        ..setMockStreamHandler(
          platform.motionStateEventChannel,
          MockStreamHandler.inline(
            onListen: (arguments, events) {
              events
                ..success('started')
                ..success('paused')
                ..success('futureState')
                ..endOfStream();
            },
          ),
        )
        ..setMockStreamHandler(
          platform.motionErrorEventChannel,
          MockStreamHandler.inline(
            onListen: (arguments, events) {
              events
                ..success({'code': 'futureError', 'message': 'SDK details'})
                ..endOfStream();
            },
          ),
        );
      addTearDown(() {
        messenger
          ..setMockStreamHandler(platform.motionSamplesEventChannel, null)
          ..setMockStreamHandler(platform.motionStateEventChannel, null)
          ..setMockStreamHandler(platform.motionErrorEventChannel, null);
      });

      final sample = await platform.motionSamplesStream().single;
      expect(sample.timestampNs, 9876543210);
      expect(sample.source, MotionSource.glasses);
      expect(sample.accelerometer, const MotionVector3(x: 1, y: 2.5, z: -3));
      expect(sample.orientation, isNull);
      expect(await platform.motionStateStream().toList(), [
        MotionState.started,
        MotionState.paused,
        MotionState.unknown,
      ]);
      final error = await platform.motionErrorStream().single;
      expect(error.code, 'futureError');
      expect(error.message, 'SDK details');
    });

    for (final kind in ['samples', 'state', 'errors']) {
      test('$kind shares one native subscription across callers', () async {
        final (eventChannel, stream, payload) = switch (kind) {
          'samples' => (
            platform.motionSamplesEventChannel,
            platform.motionSamplesStream,
            <String, Object>{'timestampNs': 42, 'source': 'glasses'},
          ),
          'state' => (
            platform.motionStateEventChannel,
            platform.motionStateStream,
            'started',
          ),
          _ => (
            platform.motionErrorEventChannel,
            platform.motionErrorStream,
            <String, Object>{'code': 'sensorUnavailable', 'message': 'Details'},
          ),
        };
        var listens = 0;
        var cancels = 0;
        late void Function(Object?) emit;
        messenger.setMockStreamHandler(
          eventChannel,
          MockStreamHandler.inline(
            onListen: (arguments, events) {
              listens++;
              emit = events.success;
            },
            onCancel: (arguments) => cancels++,
          ),
        );
        addTearDown(() => messenger.setMockStreamHandler(eventChannel, null));

        final firstEvents = <Object>[];
        final secondEvents = <Object>[];
        final firstStream = stream();
        final secondStream = stream();
        expect(firstStream, same(secondStream));
        expect(firstStream.isBroadcast, isTrue);
        final first = firstStream.listen(firstEvents.add);
        final second = secondStream.listen(secondEvents.add);
        await pumpEventQueue();

        expect(listens, 1);
        emit(payload);
        await pumpEventQueue();
        expect(firstEvents, hasLength(1));
        expect(secondEvents, hasLength(1));

        await first.cancel();
        expect(cancels, 0);
        emit(payload);
        await pumpEventQueue();
        expect(firstEvents, hasLength(1));
        expect(secondEvents, hasLength(2));

        await second.cancel();
        await pumpEventQueue();
        expect(cancels, 1);

        final resumedEvents = <Object>[];
        final resumed = stream().listen(resumedEvents.add);
        await pumpEventQueue();
        expect(listens, 2);
        emit(payload);
        await pumpEventQueue();
        expect(resumedEvents, hasLength(1));
        await resumed.cancel();
      });
    }
  });

  group('Motion facade', () {
    late MetaWearablesDatPlatform original;
    late _FakePlatform fake;

    setUp(() {
      original = MetaWearablesDatPlatform.instance;
      fake = _FakePlatform();
      MetaWearablesDatPlatform.instance = fake;
    });

    tearDown(() {
      MetaWearablesDatPlatform.instance = original;
    });

    test('forwards default and explicit start configuration', () async {
      expect(await MetaWearablesDat.startMotion(null), isTrue);
      expect(fake.deviceId, isNull);
      expect(fake.samplingRate, MotionSamplingRate.hz10);

      await MetaWearablesDat.startMotion(
        'glasses-2',
        samplingRate: MotionSamplingRate.hz60,
      );
      expect(fake.deviceId, 'glasses-2');
      expect(fake.samplingRate, MotionSamplingRate.hz60);
    });

    test('forwards stop and returns platform streams', () async {
      expect(await MetaWearablesDat.stopMotion(), isTrue);
      expect(fake.stops, 1);
      expect(MetaWearablesDat.motionSamplesStream(), same(fake.samples));
      expect(MetaWearablesDat.motionStateStream(), same(fake.states));
      expect(MetaWearablesDat.motionErrorStream(), same(fake.errors));
    });
  });
}

class _FakePlatform extends MetaWearablesDatPlatform {
  String? deviceId;
  MotionSamplingRate? samplingRate;
  int stops = 0;
  final samples = const Stream<MotionSample>.empty();
  final states = const Stream<MotionState>.empty();
  final errors = const Stream<MotionError>.empty();

  @override
  Future<bool> startMotion(
    String? deviceId, {
    MotionSamplingRate samplingRate = MotionSamplingRate.hz10,
  }) async {
    this.deviceId = deviceId;
    this.samplingRate = samplingRate;
    return true;
  }

  @override
  Future<bool> stopMotion() async {
    stops++;
    return true;
  }

  @override
  Stream<MotionSample> motionSamplesStream() => samples;

  @override
  Stream<MotionState> motionStateStream() => states;

  @override
  Stream<MotionError> motionErrorStream() => errors;
}
