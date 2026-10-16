import 'package:flutter_meta_wearables_dat/flutter_meta_wearables_dat.dart';

/// The frame-delivery stage at which a stall was detected.
enum StreamStallReason {
  /// No frame arrived after 10 eligible seconds in streaming state.
  firstFrameTimeout,

  /// SDK delivery stopped for more than 1.5 seconds after the first frame.
  sdkFramesStopped,

  /// SDK frames arrive but no texture submission occurred for 6 seconds.
  textureSubmissionsStopped;

  /// Unknown future native reasons decode as null.
  static StreamStallReason? fromValue(Object? value) =>
      _enumValue(values, value, (value) => value.name);
}

/// Audio port types only; excludes device names and unique identifiers.
class StreamAudioRoute {
  /// Creates an immutable route description.
  StreamAudioRoute({
    required List<String> inputs,
    required List<String> outputs,
  }) : inputs = List.unmodifiable(inputs),
       outputs = List.unmodifiable(outputs);

  /// Input port types reported by iOS.
  final List<String> inputs;

  /// Output port types reported by iOS.
  final List<String> outputs;

  /// Portable report representation.
  Map<String, Object?> toMap() => {'inputs': inputs, 'outputs': outputs};
}

/// Read-only native stream health, available without subscribing to frame bytes.
///
/// Rates use bounded 100ms buckets over approximately two seconds and decay to
/// zero when delivery stops. Before 100ms of measurement they are null.
/// Reads never reset counters, advance watchdogs or change audio routing.
/// Durations use monotonic native clocks; they are not wall-clock timestamps.
class StreamDiagnostics {
  /// Creates a diagnostics value.
  const StreamDiagnostics({
    this.sessionId,
    this.sessionState = StreamSessionState.stopped,
    this.requestedFrameRate,
    this.requestedQuality,
    this.requestedCodec,
    this.effectiveCodec,
    this.isAppInBackground = false,
    this.backgroundStreamingEnabled = false,
    this.framesReceived = 0,
    this.framesSubmitted = 0,
    this.receivedFps,
    this.submittedFps,
    this.measurementWindow,
    this.timeSinceLastFrame,
    this.timeSinceLastSubmission,
    this.waitingForFirstFrame = false,
    this.firstFrameWait,
    this.stallReason,
    this.audioRoute,
    this.queuedFrames,
    this.peakQueuedFrames,
  });

  /// Opaque identifier for this camera session; changes on restart.
  final String? sessionId;

  /// Current native camera state; stopped when idle.
  final StreamSessionState sessionState;

  /// Requested frame rate, which is not a delivery guarantee.
  final StreamFrameRate? requestedFrameRate;

  /// Requested camera quality.
  final StreamQuality? requestedQuality;

  /// Requested codec.
  final VideoCodec? requestedCodec;

  /// Codec used by the bridge. Android always uses raw.
  final VideoCodec? effectiveCodec;

  /// Whether the app is backgrounded.
  final bool isAppInBackground;

  /// Whether background streaming is enabled.
  final bool backgroundStreamingEnabled;

  /// SDK frames received during this session.
  final int framesReceived;

  /// Frames submitted to the texture; not proof of display.
  final int framesSubmitted;

  /// Approximate arrival rate over the rolling measurement window.
  final double? receivedFps;

  /// Approximate texture submission rate over the same window.
  final double? submittedFps;

  /// Rate window, up to two seconds. Null while idle.
  final Duration? measurementWindow;

  /// Time since an actual SDK arrival; null until the first frame.
  final Duration? timeSinceLastFrame;

  /// Time since an actual texture submission; null until one occurs.
  final Duration? timeSinceLastSubmission;

  /// Whether this session has yet to receive an SDK frame.
  final bool waitingForFirstFrame;

  /// Eligible first-frame wait committed at watchdog ticks (normally 1s).
  final Duration? firstFrameWait;

  /// Most recently detected, unrecovered frame stall, if any.
  final StreamStallReason? stallReason;

  /// Current iOS audio port types; null on Android. Does not change routing.
  final StreamAudioRoute? audioRoute;

  /// Frames in the iOS processing queue; null on Android.
  final int? queuedFrames;

  /// Peak iOS processing queue depth in this session.
  final int? peakQueuedFrames;

  /// Decodes a platform snapshot, tolerating absent and future optional fields.
  factory StreamDiagnostics.fromMap(Map<Object?, Object?> map) {
    final route = map['audioRoute'];
    return StreamDiagnostics(
      sessionId: map['sessionId'] is String
          ? map['sessionId']! as String
          : null,
      sessionState: StreamSessionState.fromInt(
        _integer(map['sessionState']) ?? 1,
      ),
      requestedFrameRate: _enumValue(
        StreamFrameRate.values,
        map['requestedFrameRate'],
        (value) => value.value,
      ),
      requestedQuality: _enumValue(
        StreamQuality.values,
        map['requestedQuality'],
        (value) => value.value,
      ),
      requestedCodec: _enumValue(
        VideoCodec.values,
        map['requestedCodec'],
        (value) => value.value,
      ),
      effectiveCodec: _enumValue(
        VideoCodec.values,
        map['effectiveCodec'],
        (value) => value.value,
      ),
      isAppInBackground: map['isAppInBackground'] == true,
      backgroundStreamingEnabled: map['backgroundStreamingEnabled'] == true,
      framesReceived: _integer(map['framesReceived']) ?? 0,
      framesSubmitted: _integer(map['framesSubmitted']) ?? 0,
      receivedFps: _number(map['receivedFps']),
      submittedFps: _number(map['submittedFps']),
      measurementWindow: _duration(map['measurementWindowUs']),
      timeSinceLastFrame: _duration(map['timeSinceLastFrameUs']),
      timeSinceLastSubmission: _duration(map['timeSinceLastSubmissionUs']),
      waitingForFirstFrame: map['waitingForFirstFrame'] == true,
      firstFrameWait: _duration(map['firstFrameWaitUs']),
      stallReason: StreamStallReason.fromValue(map['stallReason']),
      audioRoute: route is Map
          ? StreamAudioRoute(
              inputs: _strings(route['inputs']),
              outputs: _strings(route['outputs']),
            )
          : null,
      queuedFrames: _integer(map['queuedFrames']),
      peakQueuedFrames: _integer(map['peakQueuedFrames']),
    );
  }

  /// JSON-compatible report, with durations explicitly expressed in microseconds.
  Map<String, Object?> toMap() => {
    'sessionId': sessionId,
    'sessionState': sessionState.value,
    'requestedFrameRate': requestedFrameRate?.value,
    'requestedQuality': requestedQuality?.value,
    'requestedCodec': requestedCodec?.value,
    'effectiveCodec': effectiveCodec?.value,
    'isAppInBackground': isAppInBackground,
    'backgroundStreamingEnabled': backgroundStreamingEnabled,
    'framesReceived': framesReceived,
    'framesSubmitted': framesSubmitted,
    'receivedFps': receivedFps,
    'submittedFps': submittedFps,
    'measurementWindowUs': measurementWindow?.inMicroseconds,
    'timeSinceLastFrameUs': timeSinceLastFrame?.inMicroseconds,
    'timeSinceLastSubmissionUs': timeSinceLastSubmission?.inMicroseconds,
    'waitingForFirstFrame': waitingForFirstFrame,
    'firstFrameWaitUs': firstFrameWait?.inMicroseconds,
    'stallReason': stallReason?.name,
    'audioRoute': audioRoute?.toMap(),
    'queuedFrames': queuedFrames,
    'peakQueuedFrames': peakQueuedFrames,
  };
}

T? _enumValue<T>(List<T> values, Object? wire, Object Function(T) valueOf) {
  for (final value in values) {
    if (valueOf(value) == wire) return value;
  }
  return null;
}

double? _number(Object? value) =>
    value is num && value.isFinite && value >= 0 ? value.toDouble() : null;
int? _integer(Object? value) => value is int && value >= 0 ? value : null;
Duration? _duration(Object? value) {
  final us = _integer(value);
  return us == null ? null : Duration(microseconds: us);
}

List<String> _strings(Object? value) =>
    value is List ? value.whereType<String>().toList() : const [];
