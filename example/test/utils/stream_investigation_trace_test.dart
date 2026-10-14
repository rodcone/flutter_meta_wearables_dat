import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_meta_wearables_dat_example/utils/stream_investigation_trace.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('example/stream_investigation');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;

  setUp(() {
    calls = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'initialize' ? true : null;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  Future<void> flush() => Future<void>.delayed(Duration.zero);
  InvestigationTraceRecorder recorder({bool enabled = true}) =>
      InvestigationTraceRecorder(enabled: enabled, useNativeSink: true);

  List<Map<String, dynamic>> entries() => calls
      .where((call) => call.method == 'record')
      .map(
        (call) => jsonDecode(call.arguments as String) as Map<String, dynamic>,
      )
      .toList();

  test('disabled tracing never contacts native code', () async {
    final trace = recorder(enabled: false);
    await trace.initialize();
    trace.record('ignored', {});
    await flush();
    expect(calls, isEmpty);
  });

  test(
    'one handshake precedes sequenced records with original event data',
    () async {
      final trace = recorder();
      await Future.wait([trace.initialize(), trace.initialize()]);
      trace.record('teardownStarted', {'recoveryPhase': 'stopping', 'seq': 99});
      await flush();
      expect(calls.where((call) => call.method == 'initialize'), hasLength(1));
      final records = entries();
      expect(records.map((entry) => entry['seq']), [1, 2]);
      expect(records.first['event'], 'traceStarted');
      expect(records.first['sink'], 'native');
      expect(records.last['recoveryPhase'], 'stopping');
      expect(records.last['runId'], records.first['runId']);
      expect(records.last['elapsedUs'], greaterThanOrEqualTo(0));
      expect(records.last['wallTimeUs'], greaterThan(0));
    },
  );

  test('native launch opt-out does not send records', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return false;
    });
    final trace = recorder();
    await trace.initialize();
    trace.record('afterDisabledHandshake', {});
    await flush();
    expect(calls.map((call) => call.method), ['initialize']);
  });

  testWidgets('missing handshake reply cannot block startup indefinitely', (
    tester,
  ) async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) => Completer<bool>().future,
    );
    var completed = false;
    unawaited(recorder().initialize().then((_) => completed = true));
    await tester.pump(const Duration(seconds: 2));
    expect(completed, isTrue);
  });

  test(
    'missing plugin and later transport failure do not escape to the app',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw MissingPluginException(),
      );
      await recorder().initialize();
      var attempts = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'initialize') return true;
        attempts++;
        throw PlatformException(code: 'TRACE_REJECTED');
      });
      final trace = recorder();
      await trace.initialize();
      await flush();
      trace.record('afterFailure', {});
      await flush();
      expect(attempts, 1);
    },
  );

  test(
    'oversize payload becomes an explicit marker and preserves sequence',
    () async {
      final trace = recorder();
      await trace.initialize();
      trace
        ..record('oversize', {'value': 'x' * 17000})
        ..record('afterOversize', {});
      await flush();
      expect(entries().map((entry) => entry['event']), [
        'traceStarted',
        'tracePayloadRejected',
        'afterOversize',
      ]);
      expect(entries().map((entry) => entry['seq']), [1, 2, 3]);
      expect(entries()[1], isNot(contains('value')));
    },
  );

  test(
    'logging is bounded and does not await individual native replies',
    () async {
      final pending = Completer<void>();
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'initialize') return true;
        await pending.future;
        return null;
      });
      final trace = recorder();
      await trace.initialize();
      for (var i = 0; i < 2050; i++) {
        trace.record('event', {});
      }
      await flush();
      expect(entries(), hasLength(2001));
      expect(entries().last['event'], 'traceLimitReached');
      expect(entries().last['seq'], 2001);
      pending.complete();
      await flush();
    },
  );
}
