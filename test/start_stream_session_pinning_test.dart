import 'package:flutter/services.dart';
import 'package:flutter_meta_wearables_dat/flutter_meta_wearables_dat.dart';
import 'package:flutter_meta_wearables_dat/meta_wearables_dat_method_channel.dart';
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

  test(
    'startStreamSession forwards deviceId under the "deviceId" key',
    () async {
      Map<Object?, Object?>? captured;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method != 'startStreamSession') return null;
        captured = call.arguments as Map<Object?, Object?>;
        return 7; // textureId
      });

      final texId = await platform.startStreamSession('dev-B');

      expect(texId, 7);
      expect(captured?['deviceId'], 'dev-B');
    },
  );

  test('startStreamSession omits deviceId when null (Automatic)', () async {
    Map<Object?, Object?>? captured;
    messenger.setMockMethodCallHandler(channel, (call) async {
      captured = call.arguments as Map<Object?, Object?>;
      return 1;
    });

    await platform.startStreamSession(null);

    expect(captured, isNotNull);
    expect(captured!.containsKey('deviceId'), isFalse);
  });

  test('startStreamSession forwards frameRate as an int under "fps"', () async {
    Map<Object?, Object?>? captured;
    messenger.setMockMethodCallHandler(channel, (call) async {
      captured = call.arguments as Map<Object?, Object?>;
      return 1;
    });

    await platform.startStreamSession(null, frameRate: StreamFrameRate.fps24);

    // The wire type matters as much as the value: Kotlin's `as? Int` does no
    // numeric coercion, so a regression to a double would make Android fall
    // back to its 30 fps default silently instead of failing.
    expect(captured?['fps'], 24);
    expect(captured?['fps'], isA<int>());
  });

  test('startStreamSession propagates a STREAM_ACTIVE PlatformException', () {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'STREAM_ACTIVE', message: 'busy');
    });

    expect(
      platform.startStreamSession('dev-B'),
      throwsA(
        isA<PlatformException>().having((e) => e.code, 'code', 'STREAM_ACTIVE'),
      ),
    );
  });
}
