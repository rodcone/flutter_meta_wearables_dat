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

  group('startStreamSession audio flag', () {
    test('is false by default', () async {
      Map<Object?, Object?>? captured;
      messenger.setMockMethodCallHandler(channel, (call) async {
        captured = call.arguments as Map<Object?, Object?>;
        return 1;
      });

      await platform.startStreamSession(null);

      expect(captured?['audio'], isFalse);
    });

    test('is forwarded as a bool when requested', () async {
      Map<Object?, Object?>? captured;
      messenger.setMockMethodCallHandler(channel, (call) async {
        captured = call.arguments as Map<Object?, Object?>;
        return 1;
      });

      await platform.startStreamSession(null, audio: true);

      expect(captured?['audio'], isTrue);
    });

    test('facade forwards it to the platform', () async {
      final original = MetaWearablesDatPlatform.instance;
      addTearDown(() => MetaWearablesDatPlatform.instance = original);
      final fake = _FakePlatform();
      MetaWearablesDatPlatform.instance = fake;

      await MetaWearablesDat.startStreamSession(null, audio: true);

      expect(fake.audio, isTrue);
    });
  });

  group('microphone permission', () {
    test('request and status call their own methods', () async {
      final methods = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        methods.add(call.method);
        return true;
      });

      expect(await platform.requestMicrophonePermission(), isTrue);
      expect(await platform.getMicrophonePermissionStatus(), isTrue);
      expect(methods, [
        'requestMicrophonePermission',
        'getMicrophonePermissionStatus',
      ]);
    });

    test('a null answer reads as not granted', () async {
      messenger.setMockMethodCallHandler(channel, (call) async => null);

      expect(await platform.getMicrophonePermissionStatus(), isFalse);
      expect(await platform.requestMicrophonePermission(), isFalse);
    });
  });

  test('audioFramesStream delivers PCM bytes as they arrive', () async {
    final frames = [
      Uint8List.fromList([1, 0, 2, 0]),
      Uint8List.fromList([3, 0]),
    ];
    messenger.setMockStreamHandler(
      platform.audioFramesEventChannel,
      MockStreamHandler.inline(
        onListen: (arguments, events) {
          frames.forEach(events.success);
          events.endOfStream();
        },
      ),
    );
    addTearDown(
      () => messenger.setMockStreamHandler(
        platform.audioFramesEventChannel,
        null,
      ),
    );

    expect(await platform.audioFramesStream().toList(), frames);
  });
}

class _FakePlatform extends MetaWearablesDatPlatform {
  bool? audio;

  @override
  Future<int> startStreamSession(
    String? deviceId, {
    StreamFrameRate frameRate = StreamFrameRate.fps30,
    StreamQuality streamQuality = StreamQuality.high,
    VideoCodec videoCodec = VideoCodec.raw,
    bool audio = false,
  }) async {
    this.audio = audio;
    return 1;
  }
}
