import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_meta_wearables_dat/flutter_meta_wearables_dat.dart';

/// Owned by the diagnostics sheet, so closing it stops all polling.
class DiagnosticsController extends ChangeNotifier with WidgetsBindingObserver {
  DiagnosticsController({Future<StreamDiagnostics> Function()? load})
    : _load = load ?? MetaWearablesDat.getDiagnostics {
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _schedule();
  }

  final Future<StreamDiagnostics> Function() _load;
  Timer? _timer;
  bool _foreground = true;
  bool _disposed = false;
  bool _inFlight = false;
  int _generation = 0;
  StreamDiagnostics? snapshot;
  String? error;

  void _schedule() {
    if (!_foreground || _disposed) return;
    unawaited(_refresh());
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      unawaited(_refresh());
    });
  }

  Future<void> _refresh() async {
    if (_inFlight || !_foreground || _disposed) return;
    _inFlight = true;
    final generation = _generation;
    try {
      final result = await _load();
      if (_disposed || generation != _generation) return;
      snapshot = result;
      error = null;
    } on Exception catch (e) {
      if (_disposed || generation != _generation) return;
      error = e.toString();
    } finally {
      _inFlight = false;
    }
    if (!_disposed && generation == _generation) notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (foreground == _foreground) return;
    _foreground = foreground;
    _generation++;
    _timer?.cancel();
    _timer = null;
    _schedule();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
