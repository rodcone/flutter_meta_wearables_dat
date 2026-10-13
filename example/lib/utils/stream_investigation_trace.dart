import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Bounded release logging, enabled with --dart-define=MWDAT_INVESTIGATION=true.
/// Native tracing has its own launch-time environment switch. Wall-clock/elapsed
/// pairs correlate the two clocks; their monotonic origins are not identical.
abstract final class StreamInvestigationTrace {
  static const enabled = bool.fromEnvironment('MWDAT_INVESTIGATION');
  static final _clock = Stopwatch()..start();
  static int _sequence = 0;

  static void record(String event, Map<String, Object?> fields) {
    if (!enabled || _sequence > 2000) return;
    final limited = _sequence == 2000;
    _sequence++;
    debugPrintSynchronously(
      '[MWDAT-TRACE-DART] ${jsonEncode({
        if (!limited) ...fields,
        'event': limited ? 'traceLimitReached' : event,
        'seq': _sequence,
        'elapsedUs': _clock.elapsedMicroseconds,
        'wallTimeUs': DateTime.now().toUtc().microsecondsSinceEpoch,
      })}',
      wrapWidth: null,
    );
  }
}
