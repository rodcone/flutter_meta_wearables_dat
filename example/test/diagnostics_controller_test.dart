import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_meta_wearables_dat/flutter_meta_wearables_dat.dart';
import 'package:flutter_meta_wearables_dat_example/providers/diagnostics_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('polls only while visible and foreground, never overlaps', (
    tester,
  ) async {
    var calls = 0;
    final pending = <Completer<StreamDiagnostics>>[];
    final controller = DiagnosticsController(
      load: () {
        calls++;
        final request = Completer<StreamDiagnostics>();
        pending.add(request);
        return request.future;
      },
    );
    expect(calls, 1);
    await tester.pump(const Duration(seconds: 3));
    expect(calls, 1);
    controller.didChangeAppLifecycleState(AppLifecycleState.paused);
    pending[0].complete(const StreamDiagnostics(sessionId: 'stale'));
    await tester.pump();
    expect(controller.snapshot, isNull);
    await tester.pump(const Duration(seconds: 3));
    expect(calls, 1);
    controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(calls, 2);
    pending[1].complete(const StreamDiagnostics(sessionId: 'current'));
    await tester.pump();
    expect(controller.snapshot!.sessionId, 'current');
    await tester.pump(const Duration(seconds: 1));
    expect(calls, 3);
    controller.dispose();
    pending[2].complete(const StreamDiagnostics(sessionId: 'closed'));
    await tester.pump(const Duration(seconds: 4));
    expect(calls, 3);
    expect(controller.snapshot!.sessionId, 'current');
  });

  testWidgets('read failures are shown and the next poll can recover', (
    tester,
  ) async {
    var calls = 0;
    final controller = DiagnosticsController(
      load: () async {
        if (calls++ == 0) throw Exception('unavailable');
        return const StreamDiagnostics(sessionId: 'ok');
      },
    );
    await tester.pump();
    expect(controller.error, contains('unavailable'));
    await tester.pump(const Duration(seconds: 1));
    expect(controller.snapshot!.sessionId, 'ok');
    expect(controller.error, isNull);
    controller.dispose();
  });
}
