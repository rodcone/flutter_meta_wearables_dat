import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Bounded release logging, enabled with --dart-define=MWDAT_INVESTIGATION=true.
/// Native tracing has its own launch-time environment switch. Wall-clock/elapsed
/// pairs correlate the two clocks; their monotonic origins are not identical.
abstract final class StreamInvestigationTrace {
  static const enabled = bool.fromEnvironment('MWDAT_INVESTIGATION');
  static final _recorder = InvestigationTraceRecorder(
    enabled: enabled,
    useNativeSink: !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS,
  );

  static Future<void> initialize() => _recorder.initialize();

  static void record(String event, Map<String, Object?> fields) =>
      _recorder.record(event, fields);
}

/// Separate instance state allows transport failure/opt-out tests without
/// resetting the app's global tracing state. No stream operation awaits logging.
class InvestigationTraceRecorder {
  InvestigationTraceRecorder({
    required this.enabled,
    required this.useNativeSink,
  });

  final bool enabled;
  final bool useNativeSink;
  static const _channel = MethodChannel('example/stream_investigation');
  static const _maximumRecords = 2000;
  static const int _maximumBytes = 16 * 1024;
  final _clock = Stopwatch();
  late final _runId =
      '${DateTime.now().microsecondsSinceEpoch}-${identityHashCode(this)}';
  int _sequence = 0;
  bool _nativeReady = false;
  bool _nativeFailed = false;
  Future<void>? _initialization;

  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    if (!enabled) return;
    _clock.start();
    if (useNativeSink) {
      try {
        _nativeReady =
            await _channel
                .invokeMethod<bool>('initialize')
                .timeout(const Duration(seconds: 2)) ??
            false;
      } on Exception {
        _nativeFailed = true;
      }
    }
    record('traceStarted', {
      'sink': useNativeSink && _nativeReady ? 'native' : 'console',
      'nativeRequested': useNativeSink,
    });
  }

  void record(String event, Map<String, Object?> fields) {
    if (!enabled || _sequence > _maximumRecords) return;
    final limited = _sequence == _maximumRecords;
    _sequence++;
    final metadata = {
      'event': limited ? 'traceLimitReached' : event,
      'seq': _sequence,
      'runId': _runId,
      'elapsedUs': _clock.elapsedMicroseconds,
      'wallTimeUs': DateTime.now().toUtc().microsecondsSinceEpoch,
    };
    var json = jsonEncode({if (!limited) ...fields, ...metadata});
    if (utf8.encode(json).length > _maximumBytes) {
      json = jsonEncode({...metadata, 'event': 'tracePayloadRejected'});
    }
    if (useNativeSink && _nativeReady && !_nativeFailed) {
      unawaited(_send(json));
    } else {
      debugPrintSynchronously('[MWDAT-TRACE-DART] $json');
    }
  }

  Future<void> _send(String json) async {
    try {
      await _channel.invokeMethod<void>('record', json);
    } on Exception {
      // Preserve a fallback for ordinary consoles without leaking error text.
      // The collector requires native forwarding, so fallback cannot pass its
      // startup gate. At most 2,001 bounded calls can be outstanding per run.
      _nativeFailed = true;
      debugPrintSynchronously('[MWDAT-TRACE-DART] $json');
    }
  }
}
