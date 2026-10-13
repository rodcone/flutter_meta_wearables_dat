import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_meta_wearables_dat_example/providers/device_provider.dart';
import 'package:flutter_meta_wearables_dat_example/providers/mock_device_provider.dart';
import 'package:flutter_meta_wearables_dat_example/providers/stream_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channels = [
    'flutter_meta_wearables_dat',
    'flutter_meta_wearables_dat/active_device',
    'flutter_meta_wearables_dat/device_state',
    'flutter_meta_wearables_dat/registration_state',
    'flutter_meta_wearables_dat/stream_session_state',
    'flutter_meta_wearables_dat/stream_session_errors',
    'flutter_meta_wearables_dat/video_stream_size',
    'flutter_meta_wearables_dat_mock_device',
  ];
  late DeviceProvider device;
  late MockDeviceProvider mock;
  late StreamSessionProvider stream;
  var starts = 0;
  var stops = 0;
  Future<int> Function()? startReplacement;
  Completer<bool>? pendingStop;
  var disposed = false;

  Future<void> event(String channel, Object value) =>
      messenger.handlePlatformMessage(
        'flutter_meta_wearables_dat/$channel',
        const StandardMethodCodec().encodeSuccessEnvelope(value),
        (_) {},
      );
  Future<void> error([String code = 'videoStreamingError']) =>
      event('stream_session_errors', {'code': code, 'message': 'Test failure'});
  Future<void> begin(WidgetTester tester) async {
    await tester.pump();
    await stream.startStreamSession();
    await event('stream_session_state', 4);
    await tester.pump();
  }

  setUp(() {
    starts = 0;
    stops = 0;
    startReplacement = null;
    pendingStop = null;
    disposed = false;
    for (final name in channels) {
      messenger.setMockMethodCallHandler(MethodChannel(name), (call) async {
        switch (call.method) {
          case 'startStreamSession':
            starts++;
            if (starts > 1 && startReplacement != null)
              return startReplacement!();
            return 40 + starts;
          case 'stopStreamSession':
            stops++;
            return pendingStop?.future ?? true;
          case 'getDevices':
            return <Object>[];
          case 'getRegistrationState':
            return 3;
          case 'listen':
          case 'cancel':
            return null;
          default:
            return true;
        }
      });
    }
    device = DeviceProvider();
    mock = MockDeviceProvider();
    stream = StreamSessionProvider(device, mock);
  });

  tearDown(() {
    if (!disposed) stream.dispose();
    device.dispose();
    mock.dispose();
    for (final name in channels) {
      messenger.setMockMethodCallHandler(MethodChannel(name), null);
    }
  });

  testWidgets('nine errors share one backoff and one fresh-session attempt', (
    tester,
  ) async {
    await begin(tester);
    for (var i = 0; i < 9; i++) {
      await error();
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(stream.isRecovering, isTrue);
    expect(stream.lastError, isNull);
    expect(starts, 1);
    expect(stops, 0);
    // The old session's repeated STREAMING notification is not recovery.
    await event('stream_session_state', 4);
    await tester.pump(const Duration(milliseconds: 310));
    expect(starts, 2);
    expect(stops, 1);
    expect(stream.textureId, 42);
    await event('stream_session_state', 4);
    await tester.pump(const Duration(seconds: 12));
    expect(stream.isRecovering, isFalse);
    expect(starts, 2);
    expect(stops, 1);
  });

  testWidgets('replacement errors coalesce until its start completes', (
    tester,
  ) async {
    await begin(tester);
    final pending = Completer<int>();
    startReplacement = () => pending.future;
    await error();
    await tester.pump(const Duration(milliseconds: 400));
    expect(starts, 2);
    await event('stream_session_state', 4);
    for (var i = 0; i < 9; i++) {
      await error();
    }
    await tester.pump(const Duration(seconds: 2));
    expect(starts, 2);
    expect(stream.isRecovering, isTrue);
    pending.complete(42);
    await tester.pump();
    startReplacement = null;
    await tester.pump(const Duration(milliseconds: 799));
    expect(starts, 2);
    await tester.pump(const Duration(milliseconds: 1));
    expect(starts, 3);
    await event('stream_session_state', 4);
    await tester.pump();
    expect(stream.isRecovering, isFalse);
    expect(stream.textureId, 43);
  });

  testWidgets('Stop while teardown is pending prevents the replacement', (
    tester,
  ) async {
    await begin(tester);
    pendingStop = Completer<bool>();
    await error();
    await tester.pump(const Duration(milliseconds: 400));
    expect(stops, 1);
    expect(starts, 1);
    var stopCompleted = false;
    final manualStop = stream.stopStreamSession().then((_) {
      stopCompleted = true;
    });
    await tester.pump();
    expect(stopCompleted, isFalse);
    expect(stops, 1);
    // A queued old state must not resurrect the cleared texture or start work.
    await event('stream_session_state', 4);
    expect(await stream.startStreamSession(), isFalse);
    pendingStop!.complete(true);
    await tester.pump(const Duration(seconds: 20));
    await manualStop;
    expect(stopCompleted, isTrue);
    expect(starts, 1);
    expect(stream.textureId, isNull);
    expect(stream.isRecovering, isFalse);
    pendingStop = null;
    expect(await stream.startStreamSession(), isTrue);
    expect(stream.textureId, 42);
  });

  testWidgets('slow teardown leaves a full replacement startup window', (
    tester,
  ) async {
    await begin(tester);
    pendingStop = Completer<bool>();
    await error();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(seconds: 11));
    expect(stream.isRecovering, isTrue);
    expect(starts, 1);
    pendingStop!.complete(true);
    await tester.pump();
    expect(starts, 2);
    await tester.pump(const Duration(seconds: 9));
    expect(stream.isRecovering, isTrue);
    await event('stream_session_state', 4);
    await tester.pump(const Duration(seconds: 12));
    expect(stream.isRecovering, isFalse);
    expect(stream.textureId, 42);
    expect(stream.lastError, isNull);
    expect(stops, 1);
  });

  testWidgets('teardown timeout blocks new work until late cleanup completes', (
    tester,
  ) async {
    await begin(tester);
    await event('active_device', true);
    pendingStop = Completer<bool>();
    await error();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(seconds: 19));
    expect(stream.isRecovering, isTrue);
    await tester.pump(const Duration(seconds: 1));
    expect(stream.isRecovering, isFalse);
    expect(stream.lastError?.code, 'recoveryTeardownTimeout');
    expect(stream.textureId, isNull);
    expect(stream.canStartSelected, isFalse);
    expect(await stream.startStreamSession(), isFalse);
    expect(stops, 1, reason: 'Deadline must reuse the unresolved stop');
    await tester.pump(const Duration(seconds: 30));
    expect(starts, 1);
    pendingStop!.complete(true);
    await tester.pump();
    expect(starts, 1, reason: 'Late cleanup cannot revive cancelled intent');
    expect(stream.canStartSelected, isTrue);
    expect(await stream.startStreamSession(), isTrue);
    await event('stream_session_state', 4);
    await tester.pump(const Duration(seconds: 30));
    expect(stream.textureId, 42);
    expect(stops, 1);
  });

  testWidgets('duplicate errors and streaming cannot extend pending start', (
    tester,
  ) async {
    await begin(tester);
    final pending = Completer<int>();
    startReplacement = () => pending.future;
    await error();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(seconds: 9));
    await event('stream_session_state', 4);
    for (var i = 0; i < 9; i++) {
      await error();
    }
    pendingStop = Completer<bool>();
    await tester.pump(const Duration(seconds: 1));
    expect(stream.isRecovering, isFalse);
    expect(stream.lastError?.code, 'videoStreamingError');
    expect(await stream.startStreamSession(), isFalse);
    expect(stops, 2);
    pending.complete(99);
    await tester.pump();
    expect(stops, 2, reason: 'Late start shares pending timeout cleanup');
    expect(stream.textureId, isNull);
    pendingStop!.complete(true);
    await tester.pump();
    expect(starts, 2);
    startReplacement = null;
    expect(await stream.startStreamSession(), isTrue);
  });

  testWidgets('a returned texture still needs streaming before the deadline', (
    tester,
  ) async {
    await begin(tester);
    await error();
    await tester.pump(const Duration(milliseconds: 400));
    expect(stream.textureId, 42);
    await tester.pump(const Duration(seconds: 9));
    await event('stream_session_state', 3);
    await tester.pump(const Duration(seconds: 1));
    expect(stream.isRecovering, isFalse);
    expect(stream.textureId, isNull);
    expect(starts, 2);
    expect(stops, 2);
  });

  for (final phase in [
    'backoff',
    'stopping',
    'starting',
    'awaitingStreaming',
  ]) {
    for (final cancellation in ['stop', 'optOut', 'dispose', 'terminal']) {
      // Old camera subscriptions are deliberately detached during stopping;
      // native terminal events from that old session cannot target recovery.
      if (phase == 'stopping' && cancellation == 'terminal') continue;
      testWidgets('$cancellation cancels the $phase recovery phase', (
        tester,
      ) async {
        await begin(tester);
        await stream.setBackgroundStreamingEnabled(true);
        final pendingStart = Completer<int>();
        if (phase == 'starting') {
          startReplacement = () => pendingStart.future;
        }
        if (phase == 'stopping') pendingStop = Completer<bool>();
        await error();
        await tester.pump();
        if (phase != 'backoff') {
          await tester.pump(const Duration(milliseconds: 400));
        }
        Future<void>? stop;
        switch (cancellation) {
          case 'stop':
            stop = stream.stopStreamSession();
          case 'optOut':
            await stream.setBackgroundStreamingEnabled(false);
          case 'dispose':
            stream.dispose();
            disposed = true;
          case 'terminal':
            await error('insufficientSDKVersion');
        }
        await tester.pump();
        pendingStop?.complete(true);
        if (phase == 'starting') pendingStart.complete(99);
        await tester.pump();
        if (stop != null) await stop;
        await tester.pump(const Duration(seconds: 40));
        expect(starts, phase == 'backoff' || phase == 'stopping' ? 1 : 2);
        expect(stream.isRecovering, isFalse);
        if (!disposed) {
          expect(stream.isStreaming, isFalse);
          expect(stream.textureId, isNull);
        }
      });
    }
  }

  testWidgets(
    'watchdog stops an unresolved start and rejects its late texture',
    (tester) async {
      await begin(tester);
      final pending = Completer<int>();
      startReplacement = () => pending.future;
      await error();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(seconds: 10));
      expect(stream.isRecovering, isFalse);
      expect(stream.lastError?.code, 'videoStreamingError');
      pending.complete(99);
      await tester.pump();
      expect(stream.textureId, isNull);
      expect(stream.isStreaming, isFalse);
      startReplacement = null;
      expect(await stream.startStreamSession(), isTrue);
      expect(stream.textureId, 43);
      await tester.pump(const Duration(seconds: 20));
      expect(stream.textureId, 43);
      expect(starts, 3);
    },
  );

  for (final failure in ['throw', 'event']) {
    testWidgets(
      'persistent $failure failures stop after three actual retries',
      (tester) async {
        await begin(tester);
        if (failure == 'throw') {
          startReplacement = () async =>
              throw PlatformException(code: 'FAILED');
        }
        await error();
        for (var attempt = 1; attempt <= 3; attempt++) {
          await tester.pump(Duration(milliseconds: 400 * attempt));
          expect(starts, attempt + 1);
          if (failure == 'event') {
            for (var i = 0; i < 9; i++) {
              await error();
            }
            await tester.pump();
          }
        }
        await tester.pump(const Duration(seconds: 20));
        expect(starts, 4);
        expect(stream.isRecovering, isFalse);
        expect(stream.isStreaming, isFalse);
        expect(stream.textureId, isNull);
        expect(stream.lastError?.code, 'videoStreamingError');
      },
    );
  }

  for (final cancellation in ['stop', 'terminal', 'background']) {
    for (final inFlight in [false, true]) {
      testWidgets('$cancellation cancels recovery (in flight: $inFlight)', (
        tester,
      ) async {
        await begin(tester);
        final pending = Completer<int>();
        startReplacement = () => pending.future;
        await error();
        await tester.pump();
        if (inFlight) await tester.pump(const Duration(milliseconds: 400));
        switch (cancellation) {
          case 'stop':
            await stream.stopStreamSession();
          case 'terminal':
            await error('insufficientSDKVersion');
          case 'background':
            await error('stoppedForBackground');
            await event('stream_session_state', 1);
        }
        await tester.pump();
        if (inFlight) {
          // Do not overlap a new manual start with an unresolved native start.
          expect(await stream.startStreamSession(), isFalse);
          pending.complete(99);
          await tester.pump();
        }
        await tester.pump(const Duration(seconds: 20));
        expect(starts, inFlight ? 2 : 1);
        expect(stream.isRecovering, isFalse);
        expect(stream.isStreaming, isFalse);
        expect(stream.textureId, isNull);
        if (cancellation == 'terminal') {
          expect(stream.pendingUserAction?.code, 'insufficientSDKVersion');
        }
      });
    }
  }
}
