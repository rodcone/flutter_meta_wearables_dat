import 'package:flutter/services.dart';
import 'package:flutter_meta_wearables_dat/flutter_meta_wearables_dat.dart';
import 'package:flutter_meta_wearables_dat/meta_wearables_dat_method_channel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_meta_wearables_dat');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late MethodChannelMetaWearablesDat platform;
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    platform = MethodChannelMetaWearablesDat();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'startCameraStream' ? 42 : true;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('connect does not issue camera or texture calls', () async {
    expect(await platform.startDeviceSession('glasses'), isTrue);
    expect(calls.map((call) => call.method), ['startDeviceSession']);
    expect(calls.single.arguments, {'deviceId': 'glasses'});
  });
  test('camera stop and device stop use distinct native operations', () async {
    await platform.stopCameraStream(null);
    await platform.stopDeviceSession(null);
    expect(calls.map((call) => call.method), [
      'stopCameraStream',
      'stopDeviceSession',
    ]);
    expect(calls.every((call) => (call.arguments as Map).isEmpty), isTrue);
  });
  test('reattach forwards configuration and returns a new texture', () async {
    await platform.startDeviceSession(null);
    expect(
      await platform.startCameraStream(
        null,
        frameRate: StreamFrameRate.fps7,
        streamQuality: StreamQuality.medium,
        videoCodec: VideoCodec.hvc1,
      ),
      42,
    );
    expect(calls.last.arguments, {
      'fps': 7,
      'streamQuality': 'medium',
      'videoCodec': 'hvc1',
    });
    await platform.stopCameraStream(null);
    expect(await platform.startCameraStream(null), 42);
    expect(
      calls.where((call) => call.method == 'startDeviceSession').length,
      1,
    );
  });
  test('missing texture and native errors are surfaced to callers', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    await expectLater(
      platform.startCameraStream(null),
      throwsA(isA<PlatformException>()),
    );
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'DEVICE_SESSION_NOT_READY');
    });
    await expectLater(
      platform.startCameraStream(null),
      throwsA(
        isA<PlatformException>().having(
          (e) => e.code,
          'code',
          'DEVICE_SESSION_NOT_READY',
        ),
      ),
    );
  });
  test(
    'parent states remain observable without a camera subscription',
    () async {
      const name = 'flutter_meta_wearables_dat/device_session_state';
      const codec = StandardMethodCodec();
      messenger.setMockMessageHandler(
        name,
        (_) async => codec.encodeSuccessEnvelope(null),
      );
      addTearDown(() => messenger.setMockMessageHandler(name, null));
      final states = <DeviceSessionState>[];
      final sub = platform.deviceSessionStateStream().listen(states.add);
      await pumpEventQueue();
      for (final state in ['started', 'paused', 'stopped']) {
        await messenger.handlePlatformMessage(
          name,
          codec.encodeSuccessEnvelope(state),
          (_) {},
        );
      }
      await pumpEventQueue();
      expect(states, [
        DeviceSessionState.started,
        DeviceSessionState.paused,
        DeviceSessionState.stopped,
      ]);
      expect(calls, isEmpty);
      await sub.cancel();
    },
  );
}
