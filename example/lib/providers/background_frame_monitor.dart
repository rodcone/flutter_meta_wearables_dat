import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_meta_wearables_dat/flutter_meta_wearables_dat.dart';

/// One backgrounded interval, and how many frames arrived during it.
@immutable
class BackgroundWindow {
  const BackgroundWindow({
    required this.frames,
    required this.duration,
    required this.codec,
    required this.backgroundStreamingEnabled,
  });

  final int frames;
  final Duration duration;
  final VideoCodec? codec;
  final bool backgroundStreamingEnabled;

  /// Average frames per second across the window. Zero-length windows report 0
  /// rather than infinity.
  double get fps {
    final seconds = duration.inMilliseconds / 1000.0;
    if (seconds <= 0) return 0;
    return frames / seconds;
  }

  /// Whether the stream kept delivering frames for the whole window. A window
  /// that starts with frames and then goes quiet still reads as `true` here —
  /// compare [fps] against the configured target to catch that case.
  bool get deliveredFrames => frames > 0;

  String get summary {
    final secs = (duration.inMilliseconds / 1000).toStringAsFixed(1);
    if (frames == 0) {
      return 'No frames in ${secs}s backgrounded';
    }
    return '$frames frames in ${secs}s — ${fps.toStringAsFixed(1)} fps';
  }
}

/// Counts frames delivered on [MetaWearablesDat.videoFramesStream], and in
/// particular how many arrive while the app is backgrounded.
///
/// The platform `Texture` cannot render while backgrounded, so a frozen preview
/// on return tells you nothing about whether the stream survived. Counting the
/// frames Dart still receives is the only way to tell "alive but invisible"
/// apart from "stopped".
///
/// Counts are held in memory and surfaced in the UI rather than logged, because
/// the question matters most in release builds, where console output is not
/// available. Listeners are notified only on window boundaries, never per
/// frame — at 30 fps a per-frame notify would rebuild the UI 30 times a second.
class BackgroundFrameMonitor extends ChangeNotifier
    with WidgetsBindingObserver {
  StreamSubscription<VideoFrame>? _subscription;

  int _totalFrames = 0;
  VideoCodec? _lastCodec;

  /// Whether the background-streaming keep-alive was enabled when the current
  /// window opened. Stamped onto each [BackgroundWindow] so a result can be
  /// read later without remembering how the toggle was set.
  bool backgroundStreamingEnabled = false;

  int? _framesAtBackgroundEntry;
  DateTime? _backgroundedAt;

  BackgroundWindow? _lastWindow;

  /// The most recent completed background interval, or null if the app has not
  /// been backgrounded since monitoring started.
  BackgroundWindow? get lastWindow => _lastWindow;

  /// Total frames received since [start], across foreground and background.
  int get totalFrames => _totalFrames;

  /// True while a background interval is open.
  bool get isBackgrounded => _backgroundedAt != null;

  // --- Rolling live frame rate -------------------------------------------
  // Timestamps of recent frames, trimmed to [_fpsWindow]. A rolling window
  // rather than a running average: the interesting behaviour is a stream that
  // holds and then collapses, which an average since start would smear away.
  static const Duration _fpsWindow = Duration(seconds: 3);
  static const Duration _fpsPublishInterval = Duration(milliseconds: 500);
  final List<DateTime> _recentFrames = <DateTime>[];
  DateTime? _lastFpsPublish;
  double _liveFps = 0;

  /// Frames per second over the last [_fpsWindow], or 0 if nothing is arriving.
  /// Published at most twice a second so the UI is readable and cheap.
  double get liveFps => _liveFps;

  /// Subscribes to the frame stream. Call before `startStreamSession` if you
  /// want the opening keyframe counted.
  void start() {
    if (_subscription != null) return;
    WidgetsBinding.instance.addObserver(this);
    _subscription = MetaWearablesDat.videoFramesStream().listen(
      (frame) {
        _totalFrames++;
        _lastCodec = frame.codec;
        _recordForFps();
      },
      onError: (dynamic error) {
        debugPrint('[MetaWearablesDAT] Frame monitor stream error: $error');
      },
    );
    // A stall produces no frames, so the rolling rate has to be recomputed on a
    // timer as well — otherwise a frozen stream keeps displaying the last good
    // number forever, which is the opposite of what a tester needs to see.
    _fpsTicker = Timer.periodic(_fpsPublishInterval, (_) => _publishFps());
  }

  Timer? _fpsTicker;

  void _recordForFps() {
    _recentFrames.add(DateTime.now());
    _publishFps();
  }

  void _publishFps() {
    final now = DateTime.now();
    _recentFrames.removeWhere((t) => now.difference(t) > _fpsWindow);

    final last = _lastFpsPublish;
    if (last != null && now.difference(last) < _fpsPublishInterval) return;
    _lastFpsPublish = now;

    // Measure across the frames actually held, not the nominal window: right
    // after start the window is only partly filled and dividing by 3s would
    // under-report badly.
    final double fps;
    if (_recentFrames.length < 2) {
      fps = 0;
    } else {
      final span =
          _recentFrames.last.difference(_recentFrames.first).inMilliseconds /
          1000.0;
      fps = span > 0 ? (_recentFrames.length - 1) / span : 0;
    }

    if ((fps - _liveFps).abs() < 0.05) return;
    _liveFps = fps;
    notifyListeners();
  }

  /// Cancels the subscription and closes any open background window.
  void stop() {
    WidgetsBinding.instance.removeObserver(this);
    _fpsTicker?.cancel();
    _fpsTicker = null;
    unawaited(_subscription?.cancel());
    _subscription = null;
    _recentFrames.clear();
    _liveFps = 0;
    _framesAtBackgroundEntry = null;
    _backgroundedAt = null;
  }

  /// Clears counters and the last window, so the next measurement starts clean.
  void reset() {
    _totalFrames = 0;
    _recentFrames.clear();
    _liveFps = 0;
    _lastWindow = null;
    _framesAtBackgroundEntry = null;
    _backgroundedAt = null;
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
        // Open a window. `paused` is the genuine background transition on both
        // platforms; `inactive` also fires for Control Center, the app
        // switcher and call banners, none of which stop a stream.
        if (_backgroundedAt == null) {
          _framesAtBackgroundEntry = _totalFrames;
          _backgroundedAt = DateTime.now();
        }
      case AppLifecycleState.resumed:
        _closeWindow();
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        break;
    }
  }

  void _closeWindow() {
    final enteredAt = _backgroundedAt;
    final framesAtEntry = _framesAtBackgroundEntry;
    if (enteredAt == null || framesAtEntry == null) return;

    _lastWindow = BackgroundWindow(
      frames: _totalFrames - framesAtEntry,
      duration: DateTime.now().difference(enteredAt),
      codec: _lastCodec,
      backgroundStreamingEnabled: backgroundStreamingEnabled,
    );
    _backgroundedAt = null;
    _framesAtBackgroundEntry = null;
    notifyListeners();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
