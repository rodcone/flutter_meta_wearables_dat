import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_meta_wearables_dat/flutter_meta_wearables_dat.dart';

/// Owns the example's Motion subscriptions independently of the camera UI.
class MotionProvider extends ChangeNotifier {
  MotionProvider() {
    _stateSubscription = MetaWearablesDat.motionStateStream().listen(
      (state) {
        if (_disposed) return;
        _state = state;
        if (state == MotionState.stopped) _startRequested = false;
        notifyListeners();
      },
      onError: _onStreamError,
    );
    _errorSubscription = MetaWearablesDat.motionErrorStream().listen(
      (error) {
        if (_disposed) return;
        _lastError = error;
        notifyListeners();
      },
      onError: _onStreamError,
    );
    _samplesSubscription = MetaWearablesDat.motionSamplesStream().listen(
      (sample) {
        if (_disposed) return;
        _latestSample = sample;
        _sampleCount++;
        // Read every native sample; coalesce only sample-driven UI rebuilds.
        _sampleNotification ??= Timer(const Duration(milliseconds: 100), () {
          _sampleNotification = null;
          if (!_disposed) notifyListeners();
        });
      },
      onError: _onStreamError,
    );
  }

  late final StreamSubscription<MotionState> _stateSubscription;
  late final StreamSubscription<MotionError> _errorSubscription;
  late final StreamSubscription<MotionSample> _samplesSubscription;
  Timer? _sampleNotification;
  MotionState _state = MotionState.stopped;
  MotionSamplingRate _samplingRate = MotionSamplingRate.hz10;
  MotionSample? _latestSample;
  MotionError? _lastError;
  int _sampleCount = 0;
  bool _commandPending = false;
  bool _startRequested = false;
  bool _disposed = false;

  MotionState get state => _state;
  MotionSamplingRate get samplingRate => _samplingRate;
  MotionSample? get latestSample => _latestSample;
  MotionError? get lastError => _lastError;
  int get sampleCount => _sampleCount;
  bool get commandPending => _commandPending;
  bool get isActive => _startRequested || _state != MotionState.stopped;

  void setSamplingRate(MotionSamplingRate rate) {
    if (_disposed || isActive || _commandPending || rate == _samplingRate) {
      return;
    }
    _samplingRate = rate;
    notifyListeners();
  }

  Future<void> start(String? deviceId) async {
    if (_disposed || _commandPending || isActive) return;
    _commandPending = true;
    _startRequested = true;
    _latestSample = null;
    _sampleCount = 0;
    _lastError = null;
    notifyListeners();
    try {
      final started = await MetaWearablesDat.startMotion(
        deviceId,
        samplingRate: _samplingRate,
      );
      if (_disposed) return;
      if (!started) {
        _startRequested = false;
        _lastError = const MotionError(
          code: 'startFailed',
          message: 'Motion could not start. Check your glasses and try again.',
        );
      }
    } on PlatformException catch (error) {
      if (_disposed) return;
      _startRequested = false;
      _lastError = MotionError(
        code: error.code,
        message: error.message ?? 'Motion could not start.',
      );
    } catch (error) {
      if (_disposed) return;
      _startRequested = false;
      _onStreamError(error);
    } finally {
      _commandPending = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> stop() async {
    if (_disposed || _commandPending) return;
    _commandPending = true;
    notifyListeners();
    try {
      final stopped = await MetaWearablesDat.stopMotion();
      if (_disposed) return;
      if (stopped) {
        _startRequested = false;
        _state = MotionState.stopped;
      } else {
        _lastError = const MotionError(
          code: 'stopFailed',
          message: 'Motion did not confirm shutdown. Try stopping again.',
        );
      }
    } on PlatformException catch (error) {
      if (_disposed) return;
      _lastError = MotionError(
        code: error.code,
        message: error.message ?? 'Motion could not stop.',
      );
    } catch (error) {
      if (!_disposed) _onStreamError(error);
    } finally {
      _commandPending = false;
      if (!_disposed) notifyListeners();
    }
  }

  void _onStreamError(Object error) {
    if (_disposed) return;
    _lastError = MotionError(code: 'motionChannelError', message: '$error');
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sampleNotification?.cancel();
    unawaited(_stateSubscription.cancel());
    unawaited(_errorSubscription.cancel());
    unawaited(_samplesSubscription.cancel());
    // Dismissing the sheet keeps Motion alive; destroying its app owner does not.
    if (isActive || _commandPending) {
      unawaited(
        MetaWearablesDat.stopMotion().catchError((Object error) {
          debugPrint('[MetaWearablesDAT] Motion dispose failed: $error');
          return false;
        }),
      );
    }
    super.dispose();
  }
}
