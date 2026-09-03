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


  /// Subscribes to the frame stream. Call before `startStreamSession` if you
  /// want the opening keyframe counted.
  void start() {
    if (_subscription != null) return;
    WidgetsBinding.instance.addObserver(this);
    _subscription = MetaWearablesDat.videoFramesStream().listen(
      (frame) {
        _totalFrames++;
        _lastCodec = frame.codec;
      },
      onError: (dynamic error) {
        debugPrint('[MetaWearablesDAT] Frame monitor stream error: $error');
      },
    );
  }

  /// Cancels the subscription and closes any open background window.
  void stop() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_subscription?.cancel());
    _subscription = null;
    _framesAtBackgroundEntry = null;
    _backgroundedAt = null;
  }

  /// Clears counters and the last window, so the next measurement starts clean.
  void reset() {
    _totalFrames = 0;
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
