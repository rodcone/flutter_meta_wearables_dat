import 'package:flutter/services.dart';
import 'package:flutter_meta_wearables_dat/flutter_meta_wearables_dat.dart';
import 'package:flutter_meta_wearables_dat/meta_wearables_dat_method_channel.dart';
import 'package:flutter_meta_wearables_dat/meta_wearables_dat_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('videoFramesStream sampling', () {
    late MetaWearablesDatPlatform originalPlatform;

    setUp(() {
      originalPlatform = MetaWearablesDatPlatform.instance;
    });

    tearDown(() {
      MetaWearablesDatPlatform.instance = originalPlatform;
    });

    test('facade forwards maxFramesPerSecond', () {
      final fake = _FakePlatform();
      MetaWearablesDatPlatform.instance = fake;

      MetaWearablesDat.videoFramesStream(maxFramesPerSecond: 2.5);

      expect(fake.maxFramesPerSecond, 2.5);
    });

    test('facade rejects invalid sampling rates', () {
      for (final value in <double>[
        double.nan,
        double.infinity,
        double.negativeInfinity,
        -1,
        0,
        30.1,
      ]) {
        expect(
          () => MetaWearablesDat.videoFramesStream(
            maxFramesPerSecond: value,
          ),
          throwsArgumentError,
          reason: '$value should be rejected',
        );
      }
    });

    test('method channel sends sampling rate as listen arguments', () async {
      const channelName = 'flutter_meta_wearables_dat/video_frames';
      const codec = StandardMethodCodec();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final calls = <MethodCall>[];
      messenger.setMockMessageHandler(channelName, (message) async {
        calls.add(codec.decodeMethodCall(message));
        return codec.encodeSuccessEnvelope(null);
      });
      addTearDown(() => messenger.setMockMessageHandler(channelName, null));

      final subscription = MethodChannelMetaWearablesDat()
          .videoFramesStream(maxFramesPerSecond: 2.5)
          .listen((_) {});
      await pumpEventQueue();

      expect(calls, isNotEmpty);
      expect(calls.first.method, 'listen');
      expect(
        calls.first.arguments,
        <String, dynamic>{'maxFramesPerSecond': 2.5},
      );

      await subscription.cancel();
    });

    test('method channel preserves every-frame default', () async {
      const channelName = 'flutter_meta_wearables_dat/video_frames';
      const codec = StandardMethodCodec();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final calls = <MethodCall>[];
      messenger.setMockMessageHandler(channelName, (message) async {
        calls.add(codec.decodeMethodCall(message));
        return codec.encodeSuccessEnvelope(null);
      });
      addTearDown(() => messenger.setMockMessageHandler(channelName, null));

      final subscription = MethodChannelMetaWearablesDat()
          .videoFramesStream()
          .listen((_) {});
      await pumpEventQueue();

      expect(calls, isNotEmpty);
      expect(calls.first.method, 'listen');
      expect(calls.first.arguments, isNull);

      await subscription.cancel();
    });
  });
}

class _FakePlatform extends MetaWearablesDatPlatform {
  double? maxFramesPerSecond;

  @override
  Stream<VideoFrame> videoFramesStream({double? maxFramesPerSecond}) {
    this.maxFramesPerSecond = maxFramesPerSecond;
    return const Stream<VideoFrame>.empty();
  }
}
