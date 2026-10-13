import 'package:flutter/services.dart';
import 'package:flutter_meta_wearables_dat/flutter_meta_wearables_dat.dart';
import 'package:flutter_meta_wearables_dat/meta_wearables_dat_method_channel.dart';
import 'package:flutter_meta_wearables_dat/meta_wearables_dat_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('idle and malformed optional fields remain safe', () {
    final idle = StreamDiagnostics.fromMap(const {});
    expect(idle.sessionState, StreamSessionState.stopped);
    expect(idle.sessionId, isNull);
    expect(idle.framesReceived, 0);
    expect(idle.receivedFps, isNull);
    expect(idle.measurementWindow, isNull);
    expect(idle.waitingForFirstFrame, isFalse);
    final unknown = StreamDiagnostics.fromMap({
      'requestedCodec': 'future',
      'stallReason': 'future',
      'receivedFps': double.nan,
      'submittedFps': -1,
      'timeSinceLastFrameUs': -50,
      'framesReceived': 'five',
      'audioRoute': {
        'inputs': [1, 'BluetoothHFP'],
        'outputs': null,
      },
    });
    expect(unknown.requestedCodec, isNull);
    expect(unknown.stallReason, isNull);
    expect(unknown.receivedFps, isNull);
    expect(unknown.submittedFps, isNull);
    expect(unknown.timeSinceLastFrame, isNull);
    expect(unknown.framesReceived, 0);
    expect(unknown.audioRoute!.inputs, ['BluetoothHFP']);
    expect(() => unknown.audioRoute!.inputs.add('x'), throwsUnsupportedError);
  });

  test('typed snapshot preserves units and Android codec fallback', () {
    final value = StreamDiagnostics.fromMap({
      'sessionId': 's1',
      'sessionState': 4,
      'requestedFrameRate': 2,
      'requestedQuality': 'low',
      'requestedCodec': 'hvc1',
      'effectiveCodec': 'raw',
      'framesReceived': 5,
      'framesSubmitted': 3,
      'receivedFps': 2,
      'measurementWindowUs': 2000000,
      'timeSinceLastFrameUs': 123456,
      'firstFrameWaitUs': 10000000,
      'stallReason': 'sdkFramesStopped',
    });
    expect(value.sessionState, StreamSessionState.streaming);
    expect(value.requestedFrameRate, StreamFrameRate.fps2);
    expect(value.requestedCodec, VideoCodec.hvc1);
    expect(value.effectiveCodec, VideoCodec.raw);
    expect(value.receivedFps, 2.0);
    expect(value.timeSinceLastFrame, const Duration(microseconds: 123456));
    expect(value.stallReason, StreamStallReason.sdkFramesStopped);
    expect(value.audioRoute, isNull);
    expect(StreamDiagnostics.fromMap(value.toMap()).toMap(), value.toMap());
  });

  test('facade reads one diagnostics method with no side effects', () async {
    final original = MetaWearablesDatPlatform.instance;
    final platform = MethodChannelMetaWearablesDat();
    MetaWearablesDatPlatform.instance = platform;
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform.methodChannel, (call) async {
          calls.add(call);
          return {'sessionId': 'native', 'framesReceived': 12};
        });
    addTearDown(() {
      MetaWearablesDatPlatform.instance = original;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(platform.methodChannel, null);
    });
    expect((await MetaWearablesDat.getDiagnostics()).framesReceived, 12);
    expect(calls.map((c) => c.method), ['getDiagnostics']);
    expect(calls.single.arguments, isNull);
  });

  test('old and enriched stall error payloads both decode', () async {
    final platform = MethodChannelMetaWearablesDat();
    final channel = platform.streamSessionErrorEventChannel;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          ..setMockMethodCallHandler(
            MethodChannel(channel.name),
            (_) async => null,
          );
    final values = <StreamSessionError>[];
    final sub = platform.streamSessionErrorStream().listen(values.add);
    await Future<void>.delayed(Duration.zero);
    for (final payload in [
      {'code': 'frameStalled', 'message': 'legacy'},
      {
        'code': 'frameStalled',
        'message': 'timeout',
        'stallReason': 'firstFrameTimeout',
        'diagnostics': {
          'sessionId': 'failed',
          'framesReceived': 0,
          'firstFrameWaitUs': 10000000,
        },
      },
    ]) {
      await messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeSuccessEnvelope(payload),
        (_) {},
      );
    }
    expect(values.first.stallReason, isNull);
    expect(values.first.diagnostics, isNull);
    expect(values.last.stallReason, StreamStallReason.firstFrameTimeout);
    expect(values.last.diagnostics!.sessionId, 'failed');
    await sub.cancel();
    messenger.setMockMethodCallHandler(MethodChannel(channel.name), null);
  });
}
