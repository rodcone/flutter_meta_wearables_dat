import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_meta_wearables_dat/flutter_meta_wearables_dat.dart';
import 'package:flutter_meta_wearables_dat_example/providers/device_provider.dart';
import 'package:flutter_meta_wearables_dat_example/providers/mock_device_provider.dart';
import 'package:flutter_meta_wearables_dat_mock_device/flutter_meta_wearables_dat_mock_device.dart';

/// Provider to manage streaming state and active device monitoring.
/// Depends on DeviceProvider for registration state and permissions.
/// Depends on MockDeviceProvider for mock device UUID.
class StreamSessionProvider extends ChangeNotifier {
  final DeviceProvider deviceProvider;
  final MockDeviceProvider mockDeviceProvider;

  StreamSubscription<bool>? _activeDeviceSubscription;
  StreamSubscription<StreamSessionState>? _sessionStateSubscription;
  StreamSubscription<StreamSessionError>? _sessionErrorSubscription;
  StreamSubscription<VideoStreamSize>? _videoStreamSizeSubscription;
  StreamSubscription<DeviceState>? _deviceStateSubscription;
  VideoStreamSize? _videoStreamSize;
  bool _hasActiveDevice = false;
  bool _isStreaming = false;
  double _fps = 15;
  StreamQuality _streamQuality = StreamQuality.medium;
  VideoCodec _videoCodec = VideoCodec.raw;
  StreamSessionState? _sessionState;
  StreamSessionError? _lastError;
  ThermalLevel? _thermalLevel;
  String? _selectedVideo;
  String? _selectedImage;
  bool _isLoadingVideo = false;
  bool _isLoadingImage = false;
  int? _textureId;
  bool _backgroundStreamingEnabled = false;

  // --- Transparent recovery from transient mid-stream errors -------------
  // The DAT SDK auto-stops the stream when it hits certain errors ("The
  // session automatically stops when an error occurs" — SDK docs). The most
  // common trigger in practice is locking the phone while streaming: the app
  // is suspended, the pipeline breaks, and the SDK emits `videoStreamingError`
  // (and transitions the stream to `stopped`). Rather than dead-ending on a
  // red banner the user can only clear by manually stopping + starting, we
  // restart the session automatically a few times.
  static const Set<String> _recoverableStreamErrors = {
    'videoStreamingError',
    'timeout',
    'internalError',
    'deviceNotConnected',
    'deviceNotFound',
  };
  static const int _maxRecoveryAttempts = 3;
  static const Duration _recoveryWatchdog = Duration(seconds: 10);

  // --- Terminal errors: the stream is dead and will not come back ---------
  // The SDK does not auto-resume after these, so retrying is pointless — the
  // user has to act (put the glasses back on, let them cool down, charge them).
  // Left untouched, every one of these freezes the `Texture` widget on its last
  // frame, because `_isStreaming`/`_textureId` stay set while no frame ever
  // arrives again. Tearing the session down instead swaps the texture for the
  // placeholder and re-enables Start.
  //
  // The device-session variants matter as much as the stream-level ones: since
  // DAT 0.9.0 removed `StreamError.THERMAL_EMERGENCY`, a thermal emergency on
  // Android arrives *only* as `deviceThermalEmergency`. And on iOS the plugin
  // detaches the state handler before stopping the stream, so there is no
  // terminal `stopped` event to fall back on.
  //
  // Deliberately excluded: `thermalCritical` / `deviceThermalCritical`. Those
  // pause the stream rather than ending it, and the UI already renders the
  // `paused` state.
  static const Set<String> _terminalStreamErrors = {
    // stream-level
    'hingesClosed',
    'permissionDenied',
    'peakPowerShutdown',
    'batteryCritical',
    // iOS-only: on Android this arrives as `deviceThermalEmergency`
    'thermalEmergency',
    // device-session-level
    'deviceThermalEmergency',
    'deviceBatteryCritical',
    'devicePeakPowerShutdown',
    // Android-only: the stream auto-stops when the session ends externally
    'sessionEndedByDevice',
  };

  // True between a user-initiated start and stop — i.e. the user wants the
  // stream up. Gates auto-recovery so we never fight a deliberate stop.
  bool _streamingIntended = false;
  bool _isRecovering = false;

  // --- "Fix something first" latch ----------------------------------------
  // Terminal errors need a physical action before a restart can succeed: put
  // the glasses back on, let them cool, charge them. Leaving Start enabled
  // means the user taps it and just gets the same error back.
  //
  // The SDK exposes no wear/don state (`hingesClosed` only arrives *after* the
  // fact), so there's no clean signal for "ready again" and this is the app's
  // own latch. It clears on any of three paths so it can never strand the
  // button: the device signalling availability again, an explicit Stop, or
  // [_userActionGrace] elapsing — the last one is the backstop for doff, where
  // the link often stays up and no device event ever fires.
  StreamSessionError? _pendingUserAction;
  Timer? _pendingUserActionTimer;
  static const Duration _userActionGrace = Duration(seconds: 15);
  // Guards [_teardownSession] against re-entry: it awaits a platform call, and
  // a second terminal error arriving during that await would otherwise start a
  // concurrent teardown.
  bool _isTearingDown = false;
  int _recoveryAttempts = 0;
  Timer? _recoveryBackoffTimer;
  Timer? _recoveryWatchdogTimer;

  List<WearableDevice> _devices = <WearableDevice>[];
  bool _devicesLoading = false;
  String? _devicesError;
  bool _refreshingDevices = false;
  bool _pendingDevicesRefresh = false;

  // Device the user picked to stream from (a WearableDevice.id), or null for
  // Automatic. Sole source of truth — null is reserved exclusively for
  // Automatic, so the mock is pinned explicitly (see [syncMockSelection]).
  String? _selectedDeviceId;
  // Tracks the mock's UUID across pair/unpair so the selection can be
  // reconciled without clobbering a real-pair choice.
  String? _lastMockUUID;

  StreamSessionProvider(this.deviceProvider, this.mockDeviceProvider) {
    _lastMockUUID = mockDeviceProvider.deviceUUID;
    mockDeviceProvider.addListener(_onMockDeviceChanged);
    _initializeActiveDeviceMonitoring();
    _initializeDeviceStateMonitoring();
  }

  bool get hasActiveDevice => _hasActiveDevice;
  bool get isStreaming => _isStreaming;
  double get fps => _fps;
  StreamQuality get streamQuality => _streamQuality;
  VideoCodec get videoCodec => _videoCodec;
  StreamSessionState? get sessionState => _sessionState;
  StreamSessionError? get lastError => _lastError;
  String? get selectedVideo => _selectedVideo;
  String? get selectedImage => _selectedImage;
  bool get isLoadingVideo => _isLoadingVideo;
  bool get isLoadingImage => _isLoadingImage;
  int? get textureId => _textureId;
  VideoStreamSize? get videoStreamSize => _videoStreamSize;
  bool get supportsHvc1 => Platform.isIOS;
  bool get backgroundStreamingEnabled => _backgroundStreamingEnabled;

  /// True while the provider is transparently restarting a stream that hit a
  /// transient error (e.g. after the phone was locked and the app suspended).
  /// The UI shows a "Reconnecting…" affordance instead of a hard error while
  /// this is set.
  bool get isRecovering => _isRecovering;

  /// Set when the stream ended for a reason the user has to fix physically
  /// (glasses taken off or folded, overheated, flat battery). Start is disabled
  /// while this is non-null; the UI should show [pendingUserActionHint].
  StreamSessionError? get pendingUserAction => _pendingUserAction;

  /// Short instruction matching [pendingUserAction], or null when not blocked.
  String? get pendingUserActionHint {
    final error = _pendingUserAction;
    if (error == null) return null;
    return switch (error.code) {
      'hingesClosed' => 'Put your glasses back on to start streaming again.',
      'permissionDenied' =>
        'Camera access was denied. Grant it again to keep streaming.',
      'thermalEmergency' || 'deviceThermalEmergency' =>
        'Your glasses are too hot. Let them cool down before streaming again.',
      'batteryCritical' || 'deviceBatteryCritical' =>
        'Your glasses are out of battery. Charge them to stream again.',
      'peakPowerShutdown' || 'devicePeakPowerShutdown' =>
        'Your glasses shut the stream down to protect themselves. '
            'Give them a moment.',
      _ => 'Streaming stopped. Reconnect your glasses to try again.',
    };
  }

  /// Snapshot of paired devices from the last [refreshDevices] call.
  List<WearableDevice> get devices => _devices;

  /// Number of connected (active) paired devices from the last
  /// [refreshDevices] snapshot. Used to decide whether the paired-devices
  /// picker is worth surfacing — switching only makes sense with 2+ connected.
  int get connectedDeviceCount =>
      _devices.where((d) => d.linkState == WearableLinkState.connected).length;

  /// True while a [refreshDevices] call is in flight.
  bool get devicesLoading => _devicesLoading;

  /// Human-readable error from the last [refreshDevices] call, or null.
  String? get devicesError => _devicesError;

  /// The pair the next [startStreamSession] pins to (a [WearableDevice.id]),
  /// or `null` for Automatic (SDK auto-selects).
  String? get selectedDeviceId => _selectedDeviceId;

  /// Whether "Start" should be enabled for the current selection. In Automatic
  /// mode (`selectedDeviceId == null`) this mirrors [hasActiveDevice]; with a
  /// specific pair selected it reflects that pair's connectivity from the last
  /// [refreshDevices] snapshot — so the user can switch to a connected pair
  /// even while a previously pinned pair is gone (the native selector re-pins
  /// on the next [startStreamSession], which is what makes that pair active).
  bool get canStartSelected {
    // A terminal error left the glasses in a state no restart can fix until the
    // user acts. Device connectivity below can't see that — doff usually keeps
    // the link up — so the latch has to gate this first.
    if (_pendingUserAction != null) return false;
    final id = _selectedDeviceId;
    if (id == null) return _hasActiveDevice;
    final match = _devices.where((d) => d.id == id);
    if (match.isEmpty) return _hasActiveDevice;
    return match.first.linkState == WearableLinkState.connected;
  }

  /// Selects the device to stream from on the next start. `null` = Automatic.
  void selectDevice(String? id) {
    if (_selectedDeviceId == id) return;
    _selectedDeviceId = id;
    notifyListeners();
  }

  void _onMockDeviceChanged() {
    final current = mockDeviceProvider.deviceUUID;
    if (current == _lastMockUUID) return;
    syncMockSelection(mockId: current, previousMockId: _lastMockUUID);
    _lastMockUUID = current;
  }

  /// Reconciles the selection when the mock device is paired/unpaired. Pinning
  /// the mock explicitly keeps targeting deterministic (`null` stays reserved
  /// for Automatic); unpairing only clears the selection when it still points
  /// at the mock, so a real-pair selection made afterward is preserved.
  @visibleForTesting
  void syncMockSelection({
    required String? mockId,
    required String? previousMockId,
  }) {
    if (mockId == previousMockId) return;
    if (mockId != null) {
      selectDevice(mockId);
    } else if (_selectedDeviceId == previousMockId) {
      selectDevice(null);
    }
  }

  /// Current thermal level of the active device, or `null` if no device is
  /// active or the SDK hasn't reported a level yet. Updated live via
  /// [MetaWearablesDat.deviceStateStream].
  ThermalLevel? get thermalLevel => _thermalLevel;

  void _initializeActiveDeviceMonitoring() {
    _activeDeviceSubscription = MetaWearablesDat.activeDeviceStream().listen(
      (hasActiveDevice) {
        final reappeared = hasActiveDevice && !_hasActiveDevice;
        _hasActiveDevice = hasActiveDevice;
        // Reset thermal readout when device goes away so the UI doesn't show
        // stale data; the next active device will repopulate it.
        if (!hasActiveDevice) {
          _thermalLevel = null;
        }
        // The device coming back is the one trustworthy "user fixed it" signal
        // we get — it fires on power-on and on re-entering range.
        if (reappeared) _clearPendingUserAction();
        // Losing the active device mid-stream (glasses powered off, walked out
        // of range) is the one freeze the error-code path can't catch: both
        // native sides detach error and state forwarding *before* stopping the
        // stream, so neither an error nor a terminal `stopped` ever reaches
        // Dart. This listener is the only signal left, so drive the same
        // teardown from here with a synthesised error.
        if (!hasActiveDevice && _isStreaming) {
          unawaited(
            _endSessionWithError(
              const StreamSessionError(
                code: 'deviceNotConnected',
                message: 'The glasses disconnected — streaming stopped.',
              ),
            ),
          );
          unawaited(refreshDevices());
          return;
        }
        notifyListeners();
        // Refresh on both attach and detach so an open paired-devices sheet
        // reflects connection / active-device changes.
        unawaited(refreshDevices());
      },
      onError: (dynamic error) {
        debugPrint('[MetaWearablesDAT] Error in active device stream: $error');
        _hasActiveDevice = false;
        _thermalLevel = null;
        notifyListeners();
      },
    );
  }

  void _initializeDeviceStateMonitoring() {
    _deviceStateSubscription = MetaWearablesDat.deviceStateStream().listen(
      (state) {
        if (_thermalLevel != state.thermalLevel) {
          _thermalLevel = state.thermalLevel;
          notifyListeners();
        }
      },
      onError: (dynamic error) {
        debugPrint('[MetaWearablesDAT] Device state stream error: $error');
      },
    );
  }

  /// Fetches the current paired-device list via [MetaWearablesDat.getDevices]
  /// and notifies listeners. Safe to call repeatedly: while a call is in
  /// flight, a concurrent call is coalesced into a single follow-up run so the
  /// latest transition is never dropped.
  Future<void> refreshDevices() async {
    if (_refreshingDevices) {
      _pendingDevicesRefresh = true;
      return;
    }
    _refreshingDevices = true;
    _devicesLoading = true;
    _devicesError = null;
    notifyListeners();
    try {
      final list = await MetaWearablesDat.getDevices();
      // Android returns an unordered Set, so sort for stable UI.
      list.sort((a, b) {
        final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        return byName != 0 ? byName : a.id.compareTo(b.id);
      });
      _devices = list;
      _devicesError = null;
    } on PlatformException catch (e) {
      _devicesError = e.code == 'NOT_INITIALIZED'
          ? 'Grant Bluetooth permission and register first.'
          : (e.message ?? 'Failed to load devices.');
    } catch (e) {
      _devicesError = 'Failed to load devices.';
    } finally {
      _devicesLoading = false;
      _refreshingDevices = false;
      notifyListeners();
      if (_pendingDevicesRefresh) {
        _pendingDevicesRefresh = false;
        unawaited(refreshDevices());
      }
    }
  }

  /// Opens the Meta AI app to the DAT-app-update screen on the connected
  /// glasses when the SDK reports `datAppOnTheGlassesUpdateRequired`.
  Future<bool> openDATGlassesAppUpdate() async {
    unawaited(HapticFeedback.mediumImpact());
    try {
      return await MetaWearablesDat.openDATGlassesAppUpdate();
    } catch (e) {
      debugPrint('[MetaWearablesDAT] openDATGlassesAppUpdate failed: $e');
      return false;
    }
  }

  @override
  void dispose() {
    mockDeviceProvider.removeListener(_onMockDeviceChanged);
    _activeDeviceSubscription?.cancel();
    _sessionStateSubscription?.cancel();
    _sessionErrorSubscription?.cancel();
    _videoStreamSizeSubscription?.cancel();
    _deviceStateSubscription?.cancel();
    _recoveryBackoffTimer?.cancel();
    _recoveryWatchdogTimer?.cancel();
    _pendingUserActionTimer?.cancel();
    super.dispose();
  }

  void setSelectedVideo(String? path) {
    _selectedVideo = path;
    notifyListeners();
  }

  void setSelectedImage(String? path) {
    _selectedImage = path;
    notifyListeners();
  }

  void setIsLoadingVideo(bool value) {
    _isLoadingVideo = value;
    notifyListeners();
  }

  void setIsLoadingImage(bool value) {
    _isLoadingImage = value;
    notifyListeners();
  }

  void setFps(double fps) {
    HapticFeedback.lightImpact();

    if (_fps != fps) {
      _fps = fps;
      notifyListeners();
    }
  }

  void setStreamQuality(StreamQuality quality) {
    HapticFeedback.lightImpact();

    if (_streamQuality != quality) {
      _streamQuality = quality;
      notifyListeners();
    }
  }

  void setVideoCodec(VideoCodec codec) {
    HapticFeedback.lightImpact();

    if (_videoCodec != codec) {
      _videoCodec = codec;
      notifyListeners();
    }
  }

  /// Clears the pending error after the UI has shown it (e.g. via SnackBar).
  void clearError() {
    if (_lastError == null) return;
    _lastError = null;
    notifyListeners();
  }

  Future<void> _setError(StreamSessionError error) async {
    // A terminal error has already told the user what to do. The SDK keeps
    // emitting teardown noise while that stop converges, and letting it through
    // would swap the actionable message ("put your glasses back on") for a
    // generic one — while the placeholder still shows the original instruction.
    // Meta's own CameraAccess sample suppresses the same window.
    if (_pendingUserAction != null &&
        !_terminalStreamErrors.contains(error.code)) {
      debugPrint(
        '[MetaWearablesDAT] suppressing "${error.code}" during teardown',
      );
      return;
    }

    // Transient mid-stream failures (notably `videoStreamingError`, which the
    // SDK emits when the pipeline breaks — e.g. after the phone is locked and
    // the app is suspended) auto-stop the stream. Rather than dead-ending on a
    // red banner the user can only clear by manually restarting, transparently
    // restart the session a few times before surfacing the error.
    final isRecoverable = _recoverableStreamErrors.contains(error.code);
    if (_streamingIntended &&
        isRecoverable &&
        _recoveryAttempts < _maxRecoveryAttempts) {
      _scheduleRecovery(error);
      return;
    }
    // Two ways the stream is dead for good: a terminal error, or a recoverable
    // one whose retry budget is spent. Both leave a frozen texture if we only
    // raise a banner, so tear the session down as well.
    //
    // Everything else keeps the old banner-only behaviour — notably
    // `thermalCritical`, which pauses rather than ends the stream (the UI
    // renders the `paused` state), and pre-stream failures like
    // `noEligibleDevice`, which arrive with nothing to tear down.
    if (_terminalStreamErrors.contains(error.code)) {
      // Needs a physical fix — latch Start off until the user has done it.
      await _endSessionWithError(error, needsUserAction: true);
      return;
    }
    if (isRecoverable && _isStreaming) {
      // Retry budget spent. The stream is dead, but nothing is physically
      // wrong, so tear down without blocking an immediate manual restart.
      await _endSessionWithError(error);
      return;
    }
    _cancelRecovery();
    _lastError = error;
    notifyListeners();
  }

  /// Surfaces [error] and tears the session down in one shot, so the UI never
  /// observes "streaming" and a terminal error at the same time.
  ///
  /// Exactly one [notifyListeners] fires, at the end: [clearError] runs the
  /// moment the screen is notified, so an intermediate notify would consume the
  /// error before the teardown finished.
  Future<void> _endSessionWithError(
    StreamSessionError error, {
    bool needsUserAction = false,
  }) async {
    _cancelRecovery();
    _streamingIntended = false;
    await _teardownSession(preserveError: true);
    if (needsUserAction) _latchUserAction(error);
    _lastError = error;
    notifyListeners();
  }

  /// Blocks Start until the user has fixed whatever ended the stream. See the
  /// field declaration for why this is a latch rather than a live signal.
  void _latchUserAction(StreamSessionError error) {
    _pendingUserAction = error;
    _pendingUserActionTimer?.cancel();
    // Backstop: on doff the link often stays up, so no device event ever
    // arrives to clear this. Re-enable Start rather than strand the user — if
    // they still aren't ready, the next start fails and re-latches.
    _pendingUserActionTimer = Timer(_userActionGrace, _clearPendingUserAction);
  }

  void _clearPendingUserAction() {
    _pendingUserActionTimer?.cancel();
    _pendingUserActionTimer = null;
    if (_pendingUserAction == null) return;
    _pendingUserAction = null;
    notifyListeners();
  }

  void _scheduleRecovery(StreamSessionError error) {
    _recoveryAttempts++;
    _isRecovering = true;
    // Suppress the error banner while we retry; the UI shows a lightweight
    // "Reconnecting…" state driven by [isRecovering] instead.
    notifyListeners();
    debugPrint(
      '[MetaWearablesDAT] transient stream error "${error.code}" — '
      'auto-recovery attempt $_recoveryAttempts/$_maxRecoveryAttempts',
    );

    _recoveryBackoffTimer?.cancel();
    _recoveryBackoffTimer = Timer(
      Duration(milliseconds: 400 * _recoveryAttempts),
      () => unawaited(_runRecovery(error)),
    );

    // Safety net: if the stream never gets back to `streaming` and no further
    // error arrives (e.g. the device is genuinely gone), stop pretending to
    // reconnect and surface the error.
    _recoveryWatchdogTimer?.cancel();
    _recoveryWatchdogTimer = Timer(_recoveryWatchdog, () {
      if (!_isRecovering) return;
      // Same reasoning as the give-up branch in [_setError]: a stream that never
      // came back leaves a frozen texture unless the session is torn down.
      unawaited(_endSessionWithError(error));
    });
  }

  Future<void> _runRecovery(StreamSessionError error) async {
    if (!_streamingIntended) {
      _cancelRecovery();
      notifyListeners();
      return;
    }
    // Reuse the normal start path: the native side tears down the auto-stopped
    // stream and mints a fresh texture, and [startStreamSession] re-subscribes
    // the state/error streams. Success is confirmed asynchronously when the
    // state stream reaches `streaming` (see the state subscription), which
    // clears the recovery flags; a fresh async error re-enters [_setError] and
    // drives the next attempt.
    final started = await startStreamSession();
    if (started || !_streamingIntended) return;

    // Synchronous failure with no error event (e.g. the device session could
    // not be started): retry or give up.
    if (_recoveryAttempts >= _maxRecoveryAttempts) {
      _cancelRecovery();
      _lastError = error;
      notifyListeners();
    } else {
      _scheduleRecovery(error);
    }
  }

  void _cancelRecovery() {
    _recoveryBackoffTimer?.cancel();
    _recoveryBackoffTimer = null;
    _recoveryWatchdogTimer?.cancel();
    _recoveryWatchdogTimer = null;
    _isRecovering = false;
  }

  /// Starts (or, during recovery, restarts) the stream session. Returns true
  /// once a texture is obtained. A user-initiated start (i.e. not an internal
  /// recovery restart, which runs while [_isRecovering]) refreshes the
  /// recovery budget and marks intent to keep streaming.
  Future<bool> startStreamSession() async {
    if (!_isRecovering) _recoveryAttempts = 0;
    _streamingIntended = true;
    try {
      // Set camera feed if video is selected (only for mock devices)
      if (_selectedVideo != null && mockDeviceProvider.deviceUUID != null) {
        await MetaWearablesDatMockDevice.setCameraFeed(
          mockDeviceProvider.deviceUUID!,
          _selectedVideo,
        );
      }

      // Set captured image if image is selected (only for mock devices)
      if (_selectedImage != null && mockDeviceProvider.deviceUUID != null) {
        await MetaWearablesDatMockDevice.setCapturedImage(
          mockDeviceProvider.deviceUUID!,
          _selectedImage,
        );
      }

      // Subscribe to session state and error streams
      unawaited(_sessionStateSubscription?.cancel());
      _sessionStateSubscription = MetaWearablesDat.streamSessionStateStream()
          .listen(
            (state) {
              _sessionState = state;
              if (state == StreamSessionState.stopped) {
                _isStreaming = false;
                _textureId = null;
              } else if (state == StreamSessionState.streaming) {
                // A (re)established stream confirms recovery succeeded: clear
                // the in-flight recovery and refresh the retry budget.
                _recoveryAttempts = 0;
                _cancelRecovery();
              }
              notifyListeners();
              // Keep an open paired-devices sheet's "Streaming" badge in sync as
              // the session moves through streaming / paused / stopped.
              unawaited(refreshDevices());
            },
            onError: (dynamic error) {
              debugPrint(
                '[MetaWearablesDAT] Session state stream error: $error',
              );
            },
          );

      unawaited(_sessionErrorSubscription?.cancel());
      _sessionErrorSubscription = MetaWearablesDat.streamSessionErrorStream()
          .listen(
            _setError,
            onError: (dynamic error) {
              debugPrint(
                '[MetaWearablesDAT] Session error stream error: $error',
              );
            },
          );

      unawaited(_videoStreamSizeSubscription?.cancel());
      _videoStreamSize = null;
      _videoStreamSizeSubscription = MetaWearablesDat.videoStreamSizeStream()
          .listen(
            (size) {
              _videoStreamSize = size;
              notifyListeners();
            },
            onError: (dynamic error) {
              debugPrint('[MetaWearablesDAT] Video size stream error: $error');
            },
          );

      // Start the stream session - deviceUUID is optional (uses AutoDeviceSelector if null).
      // Returns a texture ID for zero-copy rendering via the Flutter Texture widget.
      final textureId = await MetaWearablesDat.startStreamSession(
        _selectedDeviceId,
        fps: _fps,
        streamQuality: _streamQuality,
        videoCodec: _videoCodec,
      );

      // A terminal error (or an explicit stop) can land while the start above is
      // still in flight. Without this check we'd re-mark the session as
      // streaming right after it was torn down, resurrecting the frozen texture.
      if (!_streamingIntended) {
        unawaited(MetaWearablesDat.stopStreamSession(_selectedDeviceId));
        return false;
      }

      _textureId = textureId;
      _isStreaming = true;
      notifyListeners();
    } catch (e) {
      debugPrint('[MetaWearablesDAT] Error starting stream session: $e');
      _isStreaming = false;
      notifyListeners();
    }
    return _isStreaming;
  }

  Future<void> stopStreamSession() async {
    unawaited(HapticFeedback.mediumImpact());

    // An explicit stop cancels any in-flight auto-recovery and clears intent
    // so a queued restart never fights the user's decision to stop.
    _streamingIntended = false;
    _recoveryAttempts = 0;
    _cancelRecovery();
    // A deliberate stop supersedes whatever the latch was waiting for.
    _clearPendingUserAction();

    await _teardownSession();
    notifyListeners();
  }

  /// Drops every trace of the current session: subscriptions, texture, stream
  /// state. Set [preserveError] to keep [lastError] intact for a caller that is
  /// about to publish its own error.
  ///
  /// **Clears local state before calling the platform, not after.** Both native
  /// sides throw `SESSION_NOT_FOUND` when no stream is attached, and both tear
  /// the stream down on their own when the device session stops or the active
  /// device disappears. Those are exactly the cases this method is called in, so
  /// doing the platform call first would let the throw skip all the clearing and
  /// leave the frozen texture on screen — the bug this exists to prevent.
  ///
  /// Never notifies: callers own that, so a caller can pair the cleared state
  /// with an error in a single notification.
  Future<void> _teardownSession({bool preserveError = false}) async {
    if (_isTearingDown) return;
    _isTearingDown = true;
    try {
      unawaited(_sessionStateSubscription?.cancel());
      _sessionStateSubscription = null;
      unawaited(_sessionErrorSubscription?.cancel());
      _sessionErrorSubscription = null;
      unawaited(_videoStreamSizeSubscription?.cancel());
      _videoStreamSizeSubscription = null;
      _sessionState = null;
      _textureId = null;
      _videoStreamSize = null;
      _isStreaming = false;
      if (!preserveError) _lastError = null;

      try {
        await MetaWearablesDat.stopStreamSession(_selectedDeviceId);
      } catch (e) {
        // `SESSION_NOT_FOUND` is the expected outcome whenever the native side
        // already tore the stream down.
        debugPrint('[MetaWearablesDAT] Error stopping stream session: $e');
      }
    } finally {
      _isTearingDown = false;
    }
  }

  Future<void> setBackgroundStreamingEnabled(bool enabled) async {
    if (_backgroundStreamingEnabled == enabled) return;
    try {
      if (enabled) {
        await MetaWearablesDat.enableBackgroundStreaming(
          androidNotification: const BackgroundNotification(
            title: 'Streaming from your glasses',
            text: 'Keeps the camera stream alive in the background.',
            channelId: 'mwdat_example.streaming',
            channelName: 'Stream Session',
          ),
        );
      } else {
        await MetaWearablesDat.disableBackgroundStreaming();
      }
      _backgroundStreamingEnabled = enabled;
      notifyListeners();
    } catch (e) {
      debugPrint('[MetaWearablesDAT] Background streaming toggle failed: $e');
    }
  }

  Future<CapturedPhoto?> capturePhoto() async {
    try {
      final photo = await MetaWearablesDat.capturePhoto(
        _selectedDeviceId,
      );
      return photo;
    } on PlatformException catch (e) {
      debugPrint('[MetaWearablesDAT] Error capturing photo: $e');
      // Capture failures arrive only here, never on the error stream, so
      // surface them explicitly — otherwise a failed capture looks like
      // nothing happened at all.
      _lastError = StreamSessionError(
        code: e.code,
        message: e.message ?? 'Photo capture failed.',
      );
      notifyListeners();
      return null;
    } catch (e) {
      debugPrint('[MetaWearablesDAT] Error capturing photo: $e');
      return null;
    }
  }
}
