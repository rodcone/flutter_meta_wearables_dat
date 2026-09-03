import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_meta_wearables_dat/meta_wearables_dat_platform_interface.dart';

/// Represents the current state of user registration with the Meta Wearables platform.
enum RegistrationState {
  /// Registration is not available, typically due to system constraints.
  unavailable(0),

  /// Registration is available and can be initiated.
  available(1),

  /// Registration process is in progress.
  registering(2),

  /// User is successfully registered with the platform.
  registered(3);

  const RegistrationState(this.value);

  /// The value of the registration state.
  final int value;

  /// Converts an integer value to a registration state.
  static RegistrationState fromInt(int value) {
    return RegistrationState.values.firstWhere(
      (state) => state.value == value,
      orElse: () => RegistrationState.unavailable,
    );
  }
}

/// Video codec to use for streaming.
enum VideoCodec {
  /// Raw decompressed video frames.
  /// iOS delivers BGRA via `CMSampleBufferGetImageBuffer`; Android delivers
  /// I420 converted to ARGB. The only codec supported on Android.
  raw('raw'),

  /// Compressed HEVC video frames (hvc1). iOS only.
  /// Decoded to BGRA via `VTDecompressionSession` (hardware). The decoder is
  /// invalidated on background entry (iOS forbids GPU access from backgrounded
  /// apps) and lazily recreated on the first frame after foreground — there's
  /// a brief keyframe-wait stall on resume. Raw hvc1 NAL bytes continue to
  /// flow on [MetaWearablesDat.videoFramesStream] while backgrounded if
  /// [MetaWearablesDat.enableBackgroundStreaming] was called.
  hvc1('hvc1');

  const VideoCodec(this.value);

  /// String value sent over the platform channel.
  final String value;
}

/// Supported streaming quality levels.
enum StreamQuality {
  /// High quality stream (best image quality, highest bandwidth/CPU).
  high('high'),

  /// Medium quality stream (balanced quality/performance).
  medium('medium'),

  /// Low quality stream (lowest bandwidth/CPU usage).
  low('low');

  const StreamQuality(this.value);

  /// String value sent over the platform channel.
  final String value;
}

/// Represents the current state of a stream session.
enum StreamSessionState {
  /// The session is in the process of stopping.
  stopping(0),

  /// The session is completely stopped.
  ///
  /// **Terminal — clear your texture id when you see this.** The native texture
  /// is unregistered alongside it, so continuing to render it shows a black or
  /// frozen frame.
  ///
  /// Since 0.9.0 this also arrives when the app is backgrounded without
  /// [MetaWearablesDat.enableBackgroundStreaming], preceded by a
  /// `stoppedForBackground` code on
  /// [MetaWearablesDat.streamSessionErrorStream]. That variant is deliberate,
  /// not a failure: do not retry it, and expect no auto-resume on foreground.
  stopped(1),

  /// The session is waiting for a device to become available.
  waitingForDevice(2),

  /// The session is in the process of starting.
  starting(3),

  /// The session is actively streaming.
  streaming(4),

  /// The session is temporarily paused.
  ///
  /// The DAT SDK both enters and leaves this state on its own. The common
  /// trigger is `thermalCritical`, which pauses the stream while the glasses
  /// cool and then returns it to [streaming]. There is no public resume because
  /// none is needed — per Meta's guidance, keep the connection and wait for
  /// [streaming] or [stopped] rather than restarting.
  ///
  /// Do **not** treat it as terminal. Tearing the session down here destroys the
  /// SDK's own recovery, and [MetaWearablesDat.startStreamSession] deliberately
  /// will not recreate a paused stream — it returns the existing texture id, so
  /// frames resume on the texture you already have.
  ///
  /// The feed does go silent while it lasts, so your `Texture` holds its last
  /// frame. Render a "paused" affordance over it instead of swapping it out.
  paused(5);

  const StreamSessionState(this.value);

  /// The integer value of the state.
  final int value;

  /// Converts an integer value to a stream session state.
  static StreamSessionState fromInt(int value) {
    return StreamSessionState.values.firstWhere(
      (state) => state.value == value,
      orElse: () => StreamSessionState.stopped,
    );
  }
}

/// Represents an error that occurred during a stream session.
class StreamSessionError {
  /// The error code identifying the type of error.
  ///
  /// **Stream-level codes** (originate from the DAT SDK's `StreamError`):
  /// `internalError`, `deviceNotFound`, `deviceNotConnected`, `timeout`,
  /// `videoStreamingError`, `permissionDenied`, `hingesClosed`,
  /// `thermalCritical`, `thermalEmergency`, `peakPowerShutdown`,
  /// `batteryCritical`. Two are **iOS only**:
  /// - `deviceNotFound` — the Android SDK's `StreamError` has no equivalent
  ///   case, so a not-found device surfaces as `videoStreamingError` there.
  /// - `thermalEmergency` — DAT 0.9.0 removed the Android SDK's
  ///   `StreamError.THERMAL_EMERGENCY`, so on Android a thermal emergency
  ///   arrives as the device-session code `deviceThermalEmergency` instead.
  ///
  /// Photo-capture failure is deliberately **not** on this channel on either
  /// platform — it resolves [MetaWearablesDat.capturePhoto] instead.
  ///
  /// **Device-session codes** (originate from the SDK's `DeviceSessionError`,
  /// surfaced on the same channel so consumers don't need a second
  /// subscription): `noEligibleDevice`, `sessionAlreadyStopped`,
  /// `sessionAlreadyExists`, `sessionIdle`, `capabilityAlreadyActive`,
  /// `capabilityNotFound`, `unexpectedError`, `deviceThermalCritical`,
  /// `deviceThermalEmergency`, `devicePeakPowerShutdown`,
  /// `deviceBatteryCritical`, `datAppOnTheGlassesUpdateRequired`,
  /// `dwaUnavailable`. Two more are **Android only** — iOS's
  /// `DeviceSessionError` is `@frozen` with no equivalent cases:
  /// `sessionEndedByDevice` (the device ended the session; the stream stops
  /// with it) and `capabilityDenied`.
  ///
  /// When this is `datAppOnTheGlassesUpdateRequired`, call
  /// [MetaWearablesDat.openDATGlassesAppUpdate] to prompt the user to update
  /// the DAT app on the glasses — streaming won't work until they do.
  final String code;

  /// A human-readable description of the error.
  final String message;

  const StreamSessionError({required this.code, required this.message});

  /// Returns true if the device's thermal state has reached a critical level.
  bool get isThermalCritical => code == 'thermalCritical';

  /// Returns true if the glasses were folded shut **or taken off**.
  ///
  /// Since DAT 0.9.0 taking the glasses off (doff) raises this too, so treat it
  /// as "the glasses are no longer being worn" rather than specifically as a
  /// hinge event. The SDK does not auto-resume — the user has to put them back
  /// on and the app has to start a new session.
  bool get isHingesClosed => code == 'hingesClosed';

  /// Returns true if camera permission was denied.
  bool get isPermissionDenied => code == 'permissionDenied';

  @override
  String toString() => 'StreamSessionError($code): $message';
}

/// Per-device thermal state reported by the DAT SDK.
///
/// Values escalate from [none] (cool) up to [shutdown] (the device is forced
/// off). Streaming-affecting transitions also surface as
/// [StreamSessionError]s (`thermalCritical` / `thermalEmergency` / etc.) on
/// [MetaWearablesDat.streamSessionErrorStream] — use this stream when you
/// want to react *before* streaming has to stop (e.g. show a "device is
/// getting hot" hint at [moderate] or [severe]).
enum ThermalLevel {
  /// State not yet known (no reading from the device).
  unknown(0),

  /// Cool — no thermal concerns.
  none(1),

  /// Slightly warm. Safe.
  light(2),

  /// Warming up. Still safe but worth surfacing in UI.
  moderate(3),

  /// Hot. Streaming may degrade soon.
  severe(4),

  /// Critical — DAT will pause streaming shortly.
  critical(5),

  /// Emergency — streaming has already been stopped to protect the device.
  emergency(6),

  /// Device has shut down due to thermal overload.
  shutdown(7);

  const ThermalLevel(this.value);

  /// Integer value sent over the platform channel.
  final int value;

  /// Converts an integer value to a thermal level.
  static ThermalLevel fromInt(int value) {
    return ThermalLevel.values.firstWhere(
      (level) => level.value == value,
      orElse: () => ThermalLevel.unknown,
    );
  }
}

/// Snapshot of per-device state emitted by
/// [MetaWearablesDat.deviceStateStream].
///
/// Currently carries only [thermalLevel]; this is a value type rather than a
/// raw `ThermalLevel` so additional state fields can be added later without
/// breaking the public API.
@immutable
class DeviceState {
  const DeviceState({required this.thermalLevel});

  /// Current thermal level of the active device.
  final ThermalLevel thermalLevel;

  @override
  String toString() => 'DeviceState(thermalLevel: $thermalLevel)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeviceState && other.thermalLevel == thermalLevel;

  @override
  int get hashCode => thermalLevel.hashCode;
}

/// Hardware model of a paired Meta wearable, as reported by the DAT SDK.
///
/// Note that two pairs of the *same* model both report the same value here
/// (e.g. two Ray-Ban Meta both report [rayBanMeta]) — use
/// [WearableDevice.name] or [WearableDevice.id] to tell them apart.
enum WearableDeviceType {
  rayBanMeta('rayBanMeta'),
  oakleyMetaHSTN('oakleyMetaHSTN'),
  oakleyMetaVanguard('oakleyMetaVanguard'),
  metaRayBanDisplay('metaRayBanDisplay'),
  rayBanMetaOptics('rayBanMetaOptics'),
  metaGlasses('metaGlasses'),

  /// Model not reported, or a newer model this plugin version predates.
  unknown('unknown');

  const WearableDeviceType(this.code);

  /// Canonical code sent over the platform channel (identical on iOS/Android).
  final String code;

  /// Converts a platform code to a [WearableDeviceType], defaulting to
  /// [unknown] for missing/unrecognized values.
  static WearableDeviceType fromCode(String? code) {
    return WearableDeviceType.values.firstWhere(
      (t) => t.code == code,
      orElse: () => WearableDeviceType.unknown,
    );
  }
}

/// BLE link state of a paired wearable.
enum WearableLinkState {
  disconnected('disconnected'),
  connecting('connecting'),
  connected('connected'),

  /// Link state not reported (e.g. SDK metadata not yet available).
  unknown('unknown');

  const WearableLinkState(this.code);

  /// Canonical code sent over the platform channel.
  final String code;

  /// Converts a platform code to a [WearableLinkState], defaulting to
  /// [unknown] for missing/unrecognized values.
  static WearableLinkState fromCode(String? code) {
    return WearableLinkState.values.firstWhere(
      (s) => s.code == code,
      orElse: () => WearableLinkState.unknown,
    );
  }
}

/// SDK/device compatibility for a paired wearable.
enum WearableCompatibility {
  /// Compatibility not yet determined.
  undefined('undefined'),
  compatible('compatible'),

  /// The on-device DAT app/firmware must be updated before use.
  deviceUpdateRequired('deviceUpdateRequired'),

  /// The host app's bundled DAT SDK must be updated before use.
  sdkUpdateRequired('sdkUpdateRequired');

  const WearableCompatibility(this.code);

  /// Canonical code sent over the platform channel.
  final String code;

  /// Converts a platform code to a [WearableCompatibility], defaulting to
  /// [undefined] for missing/unrecognized values.
  static WearableCompatibility fromCode(String? code) {
    return WearableCompatibility.values.firstWhere(
      (c) => c.code == code,
      orElse: () => WearableCompatibility.undefined,
    );
  }
}

/// A paired Meta wearable (glasses) known to the DAT SDK, returned by
/// [MetaWearablesDat.getDevices].
///
/// Distinguishing two pairs of the same model: the model ([type]) is identical
/// for both, so rely on [name] (the user-assigned name from the Meta AI app)
/// or [id] (the stable identifier). [isStreamingDevice] tells you which pair
/// the *current* stream is actually using; [isActive] tells you which pair the
/// shared auto-selector would bind a *new* stream to — these can differ when
/// more than one pair is connected.
@immutable
class WearableDevice {
  const WearableDevice({
    required this.id,
    required this.name,
    required this.type,
    required this.linkState,
    required this.compatibility,
    required this.supportsDisplay,
    required this.isActive,
    required this.isStreamingDevice,
    this.firmwareInfo,
  });

  /// Builds a [WearableDevice] from a platform-channel map.
  ///
  /// Throws [ArgumentError] when `id` is missing or blank — identity is never
  /// fabricated. All other fields tolerate missing/null values and fall back
  /// to sensible defaults ([name] → [id], enums → their `unknown`/`undefined`
  /// case, bools → `false`).
  factory WearableDevice.fromMap(Map<String, dynamic> map) {
    final id = (map['id'] as String?)?.trim() ?? '';
    if (id.isEmpty) {
      throw ArgumentError.value(
        map['id'],
        'id',
        'WearableDevice requires a non-empty id',
      );
    }
    final name = map['name'] as String?;
    return WearableDevice(
      id: id,
      name: (name == null || name.isEmpty) ? id : name,
      type: WearableDeviceType.fromCode(map['deviceType'] as String?),
      linkState: WearableLinkState.fromCode(map['linkState'] as String?),
      compatibility: WearableCompatibility.fromCode(
        map['compatibility'] as String?,
      ),
      supportsDisplay: (map['supportsDisplay'] as bool?) ?? false,
      isActive: (map['isActive'] as bool?) ?? false,
      isStreamingDevice: (map['isStreamingDevice'] as bool?) ?? false,
      firmwareInfo: map['firmwareInfo'] as String?,
    );
  }

  /// Stable identifier (`DeviceIdentifier`). Tells two pairs of the same model
  /// apart, and is the value a future release will use to pin streaming to a
  /// specific pair.
  final String id;

  /// User-assigned name from the Meta AI app (e.g. "Gautier's glasses").
  /// Falls back to [id] when the SDK hasn't surfaced a name.
  final String name;

  /// Hardware model.
  final WearableDeviceType type;

  /// Current BLE link state.
  final WearableLinkState linkState;

  /// SDK/device compatibility.
  final WearableCompatibility compatibility;

  /// Whether this device exposes a display (e.g. Meta Ray-Ban Display).
  final bool supportsDisplay;

  /// Whether this is the device the shared auto-selector currently treats as
  /// active — i.e. the pair a *new* stream session would bind to. Can differ
  /// from [isStreamingDevice] when more than one pair is connected.
  final bool isActive;

  /// Whether this device is the one the *current* stream session is actively
  /// streaming from. `false` for every device when nothing is streaming.
  final bool isStreamingDevice;

  /// Firmware version string. Currently Android-only; `null` on iOS.
  final String? firmwareInfo;

  @override
  String toString() =>
      'WearableDevice(id: $id, name: $name, type: ${type.code}, '
      'linkState: ${linkState.code}, isActive: $isActive, '
      'isStreamingDevice: $isStreamingDevice)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WearableDevice &&
          other.id == id &&
          other.name == name &&
          other.type == type &&
          other.linkState == linkState &&
          other.compatibility == compatibility &&
          other.supportsDisplay == supportsDisplay &&
          other.isActive == isActive &&
          other.isStreamingDevice == isStreamingDevice &&
          other.firmwareInfo == firmwareInfo;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    type,
    linkState,
    compatibility,
    supportsDisplay,
    isActive,
    isStreamingDevice,
    firmwareInfo,
  );
}

/// Dimensions of the active video stream, reported from the native layer
/// when a new stream starts or the underlying frame size changes.
///
/// Use [aspectRatio] when sizing the `Texture` widget so landscape or
/// portrait frames aren't stretched into a hardcoded container.
class VideoStreamSize {
  const VideoStreamSize({required this.width, required this.height});

  final int width;
  final int height;

  double get aspectRatio => height == 0 ? 1 : width / height;

  @override
  String toString() => 'VideoStreamSize(${width}x$height)';
}

/// Supported photo capture formats.
enum PhotoCaptureFormat {
  /// HEIC format — better compression than JPEG.
  heic('heic'),

  /// JPEG format — widely supported.
  jpeg('jpeg');

  const PhotoCaptureFormat(this.value);

  /// String value sent over the platform channel.
  final String value;
}

/// Supported pixel formats for captured stream frames.
///
/// These map to Flutter's [ui.ImageByteFormat] values internally.
enum FrameFormat {
  /// Raw RGBA pixel data (4 bytes per pixel, pre-multiplied alpha).
  /// Best for ML inference and image processing pipelines.
  rawRgba,

  /// Raw RGBA pixel data with straight (non-pre-multiplied) alpha.
  rawStraightRgba,

  /// PNG-encoded image data.
  /// Larger than raw formats but widely compatible.
  png,
}

/// Exception thrown when a camera permission request fails.
class CameraPermissionException implements Exception {
  /// The error code from the native SDK.
  final String code;

  /// The error message describing what went wrong.
  final String message;

  /// Additional error details (e.g., errorType).
  final Map<String, dynamic>? details;

  const CameraPermissionException({
    required this.code,
    required this.message,
    this.details,
  });

  /// Returns true when the request failed because no Ray-Ban Meta device was
  /// reachable (powered off, out of Bluetooth range, or the Meta AI app
  /// reports no connection).
  bool get isDeviceDisconnected => code == 'DEVICE_DISCONNECTED';

  /// Reserved for cases where the SDK surfaces a denial as an exception.
  /// In the current SDK a user denying the prompt is *not* an error — it
  /// returns `false` from [MetaWearablesDat.requestCameraPermission].
  /// Treat a `false` return as denial; this predicate stays for forward
  /// compatibility.
  bool get isPermissionDenied => code == 'PERMISSION_DENIED';

  /// Returns true for any other SDK-side failure (request already in
  /// progress, timeout, Meta AI app not installed, generic internal error,
  /// or an unrecognized error type).
  bool get isInternalError => code == 'INTERNAL_ERROR';

  @override
  String toString() => details == null
      ? 'CameraPermissionException($code): $message'
      : 'CameraPermissionException($code): $message $details';
}

/// Represents a photo captured from a Meta Wearables device.
class CapturedPhoto {
  /// The bytes of the captured photo.
  final Uint8List bytes;

  /// The format of the captured photo.
  final String format;

  const CapturedPhoto({required this.bytes, required this.format});

  String get fileExtension => format == 'heic' ? 'heic' : 'jpg';

  String get mimeType => format == 'heic' ? 'image/heic' : 'image/jpeg';
}

/// A single video frame captured from an active stream session's Flutter
/// texture.
///
/// [CapturedFrame] is captured silently on the Dart side by rasterizing the
/// Flutter texture. The pixel data is suitable for OCR, ML inference, or any
/// image processing that needs raw frame access.
class CapturedFrame {
  /// The raw pixel data of the captured frame.
  ///
  /// The encoding depends on the [format] used during capture:
  /// - [FrameFormat.rawRgba] / [FrameFormat.rawStraightRgba]: 4 bytes per
  ///   pixel (R, G, B, A), total size = [width] * [height] * 4.
  /// - [FrameFormat.png]: PNG-encoded image data.
  final Uint8List bytes;

  /// The width of the captured frame in pixels.
  final int width;

  /// The height of the captured frame in pixels.
  final int height;

  /// The pixel format of [bytes].
  final FrameFormat format;

  const CapturedFrame({
    required this.bytes,
    required this.width,
    required this.height,
    required this.format,
  });
}

/// Notification shown by the Android foreground service that keeps the
/// stream alive while the app is backgrounded. Required on Android; ignored
/// on iOS.
class BackgroundNotification {
  const BackgroundNotification({
    required this.title,
    required this.text,
    required this.channelId,
    required this.channelName,
    this.iconResourceName,
  });

  /// Notification title (bold line).
  final String title;

  /// Notification body.
  final String text;

  /// Unique notification channel id. Reuse the same value across calls to
  /// avoid re-creating the channel.
  final String channelId;

  /// User-visible channel name shown in Android settings.
  final String channelName;

  /// Drawable resource name for the small icon, e.g. `"ic_stat_recording"`.
  /// When null, the app's launcher icon is used.
  final String? iconResourceName;

  Map<String, dynamic> toMap() => <String, dynamic>{
    'title': title,
    'text': text,
    'channelId': channelId,
    'channelName': channelName,
    if (iconResourceName != null) 'iconResourceName': iconResourceName,
  };
}

/// A single video frame delivered over the platform channel.
///
/// Emitted by [MetaWearablesDat.videoFramesStream] in both foreground and
/// background once [MetaWearablesDat.enableBackgroundStreaming] has been
/// called. For preview rendering you still want the zero-copy `Texture`
/// returned by [MetaWearablesDat.startStreamSession] — this stream is meant
/// for recording or custom processing.
class VideoFrame {
  const VideoFrame({
    required this.codec,
    required this.bytes,
    required this.width,
    required this.height,
    required this.presentationTimestampUs,
    required this.isKeyframe,
    this.bytesPerRow,
  });

  /// The codec the bytes are in.
  ///
  /// - [VideoCodec.raw] — platform-specific decoded pixel layout:
  ///   - **iOS**: 32-bit BGRA, length `bytesPerRow * height` (may contain
  ///     row padding — use [bytesPerRow] when iterating rows).
  ///   - **Android**: I420 planar YUV (3 planes: Y, U, V) at
  ///     `width * height * 3 / 2` bytes. This is the SDK's native frame
  ///     format — forwarded as-is for zero-overhead recording. Convert
  ///     on the Dart side or feed directly into an encoder that accepts
  ///     YUV (FFmpeg, MediaCodec, etc.).
  /// - [VideoCodec.hvc1] — HEVC (`hvc1`) compressed sample. Parameter sets
  ///   (VPS/SPS/PPS) are carried on keyframes (`isKeyframe == true`).
  ///   Ready to be written into an `mp4` track as-is, or decoded by
  ///   VideoToolbox / MediaCodec. iOS only.
  final VideoCodec codec;

  /// The frame bytes. Ownership transfers to the listener; the plugin
  /// does not retain the buffer after emission.
  final Uint8List bytes;
  final int width;
  final int height;

  /// Monotonic presentation timestamp in microseconds. Stable across the
  /// lifetime of a single stream session.
  final int presentationTimestampUs;

  /// Always `true` for [VideoCodec.raw]. For [VideoCodec.hvc1] indicates
  /// whether this frame carries parameter sets and can be decoded without
  /// prior frames — safe to use as the first frame of a recording or a
  /// decode burst.
  ///
  /// A frame qualifies when it opens on an IRAP picture (or the SDK flags it
  /// as a keyframe) *and* the VPS/SPS/PPS trio either travels with it or was
  /// prepended by the plugin. An IRAP that could not be made self-decodable —
  /// no parameter sets have been observed yet on this session — reports
  /// `false` rather than pointing a recorder at an undecodable segment start.
  final bool isKeyframe;

  /// Number of bytes per row for [VideoCodec.raw] frames on iOS — may be
  /// larger than `width * 4` due to row alignment. `null` on Android and
  /// for [VideoCodec.hvc1].
  final int? bytesPerRow;
}

/// The main class for the Meta Wearables DAT.
class MetaWearablesDat {
  /// Requests the Android runtime permissions required by the DAT SDK
  /// (Bluetooth, Internet). Returns true if all permissions are granted.
  /// No-op on iOS.
  static Future<bool> requestAndroidPermissions() {
    return MetaWearablesDatPlatform.instance.requestAndroidPermissions();
  }

  /// Requests camera permission from the connected glasses (shows the Meta AI
  /// camera-access prompt when not already granted).
  ///
  /// On a grant, the call waits briefly (bounded) for the glasses to surface in
  /// the SDK device flow before returning, so an immediately-following
  /// [startStreamSession] or [getDevices] does not race device discovery and
  /// hit `noEligibleDevice` / an empty list. Returns as soon as a device
  /// resolves; otherwise after a short timeout. A `false` return means the user
  /// denied the request.
  static Future<bool> requestCameraPermission() {
    return MetaWearablesDatPlatform.instance.requestCameraPermission();
  }

  /// Returns whether camera permission is currently granted.
  static Future<bool> getCameraPermissionStatus() {
    return MetaWearablesDatPlatform.instance.getCameraPermissionStatus();
  }

  /// Starts the registration process.
  static Future<bool> startRegistration() {
    return MetaWearablesDatPlatform.instance.startRegistration();
  }

  /// Handles a URL.
  static Future<bool> handleUrl(String url) {
    return MetaWearablesDatPlatform.instance.handleUrl(url);
  }

  /// Starts the unregistration (disconnect) process.
  /// Opens the Meta AI app where the user completes the flow; the callback
  /// URL must be passed to [handleUrl] to complete unregistration.
  static Future<bool> disconnect() {
    return MetaWearablesDatPlatform.instance.disconnect();
  }

  /// Starts a stream session.
  ///
  /// Pass a [WearableDevice.id] (from [getDevices]) as [deviceId] to stream
  /// from that specific pair; pass `null` to let the SDK auto-select the
  /// active device. Returns a texture ID for rendering via the Flutter
  /// `Texture` widget — frames are pushed native→GPU (no encoding, no byte
  /// copying, no Dart-side decoding).
  ///
  /// Throws a `PlatformException` with code `STREAM_ACTIVE` if a stream is
  /// already running on a *different* device — stop it first, then start.
  static Future<int> startStreamSession(
    String? deviceId, {
    double fps = 30.0,
    StreamQuality streamQuality = StreamQuality.high,
    VideoCodec videoCodec = VideoCodec.raw,
  }) {
    if (kDebugMode) {
      debugPrint(
        '[MetaWearablesDAT] Starting stream session with deviceId: $deviceId, FPS: $fps, Stream quality: $streamQuality, Video codec: $videoCodec',
      );
    }
    return MetaWearablesDatPlatform.instance.startStreamSession(
      deviceId,
      fps: fps,
      streamQuality: streamQuality,
      videoCodec: videoCodec,
    );
  }

  /// Stops the active stream session. [deviceId] is accepted for call symmetry
  /// but isn't required — there is a single active session.
  ///
  /// Since 0.9.1 this ends the whole device session, not just the stream, on
  /// both platforms — the glasses play their stream-ended tone, which they
  /// previously only did when the app was backgrounded or killed. The
  /// trade-off is that the next [startStreamSession] is a full session
  /// reconnect rather than a fast capability re-attach, so restarting takes
  /// noticeably longer than it did on 0.9.0.
  ///
  /// The returned future resolves once the stop handshake with the glasses has
  /// completed. That is normally quick, but is bounded by backstops of a few
  /// seconds each for a dead device or wedged SDK — do not assume it resolves
  /// instantly.
  static Future<bool> stopStreamSession(String? deviceId) {
    return MetaWearablesDatPlatform.instance.stopStreamSession(deviceId);
  }

  /// Captures a photo from the active stream session. [deviceId] is accepted
  /// for call symmetry; the capture targets the active session.
  ///
  /// On failure throws a `PlatformException`. Codes:
  /// - `SESSION_NOT_FOUND` — no active stream session.
  /// - `CAPTURE_NOT_READY` — the request was rejected synchronously (no
  ///   high-bandwidth BTC/WiFi lease, or a capture already in progress).
  /// - `CAPTURE_PHOTO_FAILED` — the capture failed or timed out. `details`
  ///   carries a granular reason string.
  ///
  /// The granular `details` reasons differ per platform because the two SDKs
  /// report capture failure differently:
  /// - Android: `deviceDisconnected`, `notStreaming`, `captureInProgress`,
  ///   `captureFailed` (from the SDK's typed `CaptureError`).
  /// - iOS: `photoCaptureFailed` — reported by the SDK, usually within
  ///   milliseconds, and typically means the glasses are out of storage.
  ///   `photoCaptureTimeout` is the backstop for a capture that is accepted and
  ///   then goes silent, so this `Future` always resolves.
  ///
  /// Capture failures surface only here, never on [streamSessionErrorStream] —
  /// on both platforms.
  static Future<CapturedPhoto> capturePhoto(
    String? deviceId, {
    PhotoCaptureFormat format = PhotoCaptureFormat.jpeg,
  }) {
    if (kDebugMode) {
      debugPrint(
        '[MetaWearablesDAT] Capturing photo with deviceId: '
        '${deviceId ?? 'null (automatic — targets the active session)'}, '
        'format: $format',
      );
    }
    return MetaWearablesDatPlatform.instance.capturePhoto(
      deviceId,
      format: format,
    );
  }

  /// Captures a single frame from an active stream session's Flutter texture.
  ///
  /// This is a **Dart-side** operation that rasterizes the texture identified
  /// by [textureId] (returned by [startStreamSession]) into pixel data.
  /// No native code is invoked and the capture is near-instantaneous.
  ///
  /// Use this when you need raw frame bytes for OCR, ML inference, computer
  /// vision, or any processing that requires direct pixel access.
  ///
  /// **Note:** Raw RGBA at the default 720x1280 resolution is ~3.7 MB per
  /// frame. This method is intended for on-demand captures (e.g., every
  /// 200-500 ms), not continuous per-frame processing.
  ///
  /// Returns a [CapturedFrame] containing the pixel data, or `null` if the
  /// capture failed (e.g., texture not available).
  static Future<CapturedFrame?> captureStreamFrame(
    int textureId, {
    int width = 720,
    int height = 1280,
    FrameFormat format = FrameFormat.rawRgba,
  }) async {
    final builder = ui.SceneBuilder()
      ..addTexture(
        textureId,
        width: width.toDouble(),
        height: height.toDouble(),
        freeze: true,
        filterQuality: ui.FilterQuality.high,
      );
    final scene = builder.build();
    try {
      final image = await scene.toImage(width, height);
      try {
        final imageByteFormat = switch (format) {
          FrameFormat.rawRgba => ui.ImageByteFormat.rawRgba,
          FrameFormat.rawStraightRgba => ui.ImageByteFormat.rawStraightRgba,
          FrameFormat.png => ui.ImageByteFormat.png,
        };
        final byteData = await image.toByteData(format: imageByteFormat);
        if (byteData == null) return null;
        return CapturedFrame(
          bytes: byteData.buffer.asUint8List(),
          width: width,
          height: height,
          format: format,
        );
      } finally {
        image.dispose();
      }
    } finally {
      scene.dispose();
    }
  }

  /// Stream of stream session state changes.
  ///
  /// Emits state transitions such as `stopped`, `waitingForDevice`,
  /// `streaming`, `paused`, etc. Subscribe to this stream to update your
  /// UI based on the current session state.
  static Stream<StreamSessionState> streamSessionStateStream() {
    return MetaWearablesDatPlatform.instance.streamSessionStateStream();
  }

  /// Stream of stream session errors.
  ///
  /// Emits errors such as `thermalCritical` (device overheating),
  /// `hingesClosed`, `permissionDenied`, etc. Subscribe to this stream
  /// to handle errors during an active stream session.
  static Stream<StreamSessionError> streamSessionErrorStream() {
    return MetaWearablesDatPlatform.instance.streamSessionErrorStream();
  }

  /// Gets the current registration state.
  static Future<RegistrationState> getRegistrationState() async {
    final registrationState = await MetaWearablesDatPlatform.instance
        .getRegistrationState();
    if (kDebugMode) {
      debugPrint('[MetaWearablesDAT] Registration state: $registrationState');
    }
    return registrationState;
  }

  /// Stream of registration state changes.
  static Stream<RegistrationState> registrationStateStream() {
    final registrationStateStream = MetaWearablesDatPlatform.instance
        .registrationStateStream();
    return registrationStateStream;
  }

  /// Stream of active device availability changes.
  /// Returns true when an active device is available, false otherwise.
  static Stream<bool> activeDeviceStream() {
    return MetaWearablesDatPlatform.instance.activeDeviceStream();
  }

  /// Returns the paired Meta wearables currently known to the DAT SDK, with
  /// their names, models, link state, and which pair (if any) is actively
  /// streaming ([WearableDevice.isStreamingDevice]) or auto-selected
  /// ([WearableDevice.isActive]).
  ///
  /// This is a one-shot snapshot; call it again to refresh. Devices only
  /// appear after registration completes and camera permission is granted —
  /// before that the list is empty.
  ///
  /// **Android:** throws a `PlatformException` with code `NOT_INITIALIZED` if
  /// called before [requestAndroidPermissions] has granted Bluetooth
  /// permissions (the SDK can't enumerate devices until then). iOS returns an
  /// empty list instead.
  static Future<List<WearableDevice>> getDevices() {
    return MetaWearablesDatPlatform.instance.getDevices();
  }

  /// Stream of video frame dimensions for the active stream session.
  ///
  /// Emits once shortly after `startStreamSession` and again if the
  /// underlying source changes resolution. Use [VideoStreamSize.aspectRatio]
  /// with an `AspectRatio` widget wrapping the `Texture` so landscape
  /// footage isn't crammed into a portrait box (or vice versa).
  static Stream<VideoStreamSize> videoStreamSizeStream() {
    return MetaWearablesDatPlatform.instance.videoStreamSizeStream();
  }

  /// Restarts active device monitoring.
  /// Call after registration completes so the plugin re-subscribes
  /// to the device flow and picks up newly available devices.
  ///
  /// On Android this re-subscribes the native device-flow listener. On iOS
  /// it relaunches the active-device and device-state event loops plus the
  /// plugin's internal availability watchdog — the SDK terminates those
  /// streams on unregistration, so without this call streaming could not
  /// resume after a disconnect/re-register cycle without an app restart.
  static Future<bool> restartActiveDeviceMonitoring() {
    return MetaWearablesDatPlatform.instance.restartActiveDeviceMonitoring();
  }

  /// Enables background streaming.
  ///
  /// Call this BEFORE [startStreamSession] if you want the stream to survive
  /// the host app being backgrounded, the screen being locked, or the user
  /// switching apps.
  ///
  /// **Without this, backgrounding stops the session.** Since 0.9.0 a true
  /// background transition tears the session down, emits `stoppedForBackground`
  /// on [streamSessionErrorStream] followed by a terminal
  /// [StreamSessionState.stopped], and releases the texture. Nothing resumes on
  /// foreground — the plugin never reactivates the glasses camera on its own.
  ///
  /// Cannot be enabled *while* already backgrounded: iOS refuses to activate an
  /// audio session and Android forbids starting a foreground service from the
  /// background on API 31+. Call it before you background.
  ///
  /// **Frame rate on Bluetooth Classic (iOS).** Enabling this has *no
  /// measurable effect on frame rate.* Earlier releases of this plugin said it
  /// did; that was wrong, and the correction matters because it changes what
  /// you should do about slow streams.
  ///
  /// Measured on hardware (Ray-Ban Display, Bluetooth Classic, medium quality,
  /// 24 fps target), mean of ~15 samples per condition:
  ///
  /// | condition | mean |
  /// | --- | --- |
  /// | keep-alive enabled | 14.6 fps |
  /// | keep-alive disabled | 15.7 fps |
  ///
  /// The difference is well inside the run-to-run noise on this link. The real
  /// finding is the second row: **with no keep-alive at all, a 24 fps request
  /// still delivers about 15 fps.** The shortfall belongs to the Bluetooth
  /// Classic transport, not to this API.
  ///
  /// So asking for more than ~15 fps on Bluetooth Classic at medium quality
  /// does not get you more than ~15 fps, whether or not background streaming is
  /// on. Use the Wi-Fi camera transport if you need the full rate. Android is
  /// unaffected either way — its keep-alive is a foreground service.
  ///
  /// One real side effect does remain, and it is not about throughput: on iOS
  /// the keep-alive session adopts the glasses as a Bluetooth A2DP *output*
  /// while it is active, so audio your app plays may route to the glasses. The
  /// plugin logs the route on activation and on every change
  /// (`[MWDAT-ROUTE]`); see the README's troubleshooting section.
  ///
  /// Safe to call again to reconfigure the Android notification; safe to call
  /// after [startStreamSession] too — the keep-alive mechanism engages
  /// immediately.
  ///
  /// **iOS** — activates an `AVAudioSession` in `.playAndRecord` /
  /// `.videoRecording` mode to keep the process scheduled while backgrounded.
  /// The hardware HEVC decoder is invalidated on background entry (iOS forbids
  /// GPU access from backgrounded apps) and lazily recreated on the first frame
  /// after foreground, so resume incurs a brief keyframe-wait stall. The host
  /// app's `Info.plist` must declare these `UIBackgroundModes`: `audio`,
  /// `bluetooth-central`, `bluetooth-peripheral` (plus `external-accessory` if
  /// you use the Bluetooth Classic camera transport).
  ///
  /// **Android** — starts a foreground service with the given
  /// [androidNotification] and acquires a `PARTIAL_WAKE_LOCK`. The plugin
  /// manifest merges `FOREGROUND_SERVICE`,
  /// `FOREGROUND_SERVICE_CONNECTED_DEVICE`, and `WAKE_LOCK` into your
  /// `AndroidManifest.xml`. [androidNotification] must be provided on
  /// Android; passing `null` on Android throws.
  static Future<void> enableBackgroundStreaming({
    BackgroundNotification? androidNotification,
  }) {
    return MetaWearablesDatPlatform.instance.enableBackgroundStreaming(
      androidNotification: androidNotification,
    );
  }

  /// Disables background streaming.
  ///
  /// Deactivates the `AVAudioSession` on iOS and stops the foreground
  /// service / releases the wake lock on Android. Safe to call multiple
  /// times. Does NOT stop the active stream session; use
  /// [stopStreamSession] for that.
  ///
  /// Since 0.9.1 the returned future resolves only once the deactivation has
  /// actually landed (it runs off the main thread on iOS). Await it before
  /// letting the app background if you are relying on the keep-alive being
  /// gone.
  ///
  /// Worth calling when you observe a terminal [StreamSessionState.stopped] and
  /// do not intend to restart: the keep-alive is not tied to the stream, so an
  /// Android foreground service otherwise keeps showing a "streaming"
  /// notification over a held wake lock with nothing streaming. The plugin does
  /// not do this for you — an app that stops between captures still wants the
  /// keep-alive, and on API 31+ it could not restart the service from the
  /// background if the plugin had dropped it.
  static Future<void> disableBackgroundStreaming() {
    return MetaWearablesDatPlatform.instance.disableBackgroundStreaming();
  }

  /// Whether background streaming is currently enabled, read from the native
  /// side rather than from Dart state.
  ///
  /// The flag lives natively — an active `AVAudioSession` on iOS, a running
  /// foreground service on Android — so a Dart-side mirror drifts. The common
  /// case is a hot restart: the isolate resets to `false` while the audio
  /// session or service is still very much alive, and the app then renders a
  /// toggle that disagrees with reality. Seed your UI from this instead.
  ///
  /// Returns `false` on a cold launch, correctly: neither keep-alive survives
  /// process death, so background streaming really is off until you enable it
  /// again. Do not persist the toggle across launches — you would be showing
  /// `true` for something that is not running.
  static Future<bool> isBackgroundStreamingEnabled() {
    return MetaWearablesDatPlatform.instance.isBackgroundStreamingEnabled();
  }

  /// Stream of per-frame [VideoFrame] events. Emitted whenever a Dart
  /// subscriber is attached — the native side short-circuits serialization
  /// when no listener is present, so there is zero per-frame cost for apps
  /// that don't need the feed.
  ///
  /// Use this when you want to record the stream to disk or run custom
  /// per-frame processing. For preview rendering, the zero-copy `Texture`
  /// returned by [startStreamSession] is always the right choice — it
  /// bypasses the platform channel.
  ///
  /// On iOS, frames keep flowing while the app is backgrounded only if
  /// [enableBackgroundStreaming] has been called (iOS otherwise suspends
  /// the underlying capture). On Android, [enableBackgroundStreaming] is
  /// what keeps the OS from killing the streaming process once the app
  /// leaves the foreground.
  static Stream<VideoFrame> videoFramesStream() {
    return MetaWearablesDatPlatform.instance.videoFramesStream();
  }

  /// Opens the Meta AI app to the DAT-app-update screen on the connected
  /// glasses. Call this in response to a
  /// `datAppOnTheGlassesUpdateRequired` error code on
  /// [streamSessionErrorStream] — streaming won't work until the user
  /// updates the on-device DAT app.
  ///
  /// Returns `true` if the navigation succeeded. Throws a `PlatformException`
  /// with code `metaAINotInstalled` if the Meta AI app isn't installed, or
  /// `notRegistered` if the app hasn't completed registration.
  static Future<bool> openDATGlassesAppUpdate() {
    return MetaWearablesDatPlatform.instance.openDATGlassesAppUpdate();
  }

  /// Stream of [DeviceState] snapshots for the active device.
  ///
  /// Currently emits whenever the device's [ThermalLevel] changes. Subscribe
  /// to drive thermal warnings in your UI — by the time a critical-level
  /// thermal error reaches [streamSessionErrorStream] the stream has already
  /// stopped, so reacting to [ThermalLevel.moderate] / [ThermalLevel.severe]
  /// gives you a chance to warn the user before that happens.
  ///
  /// The stream switches its underlying subscription automatically when the
  /// active device changes.
  static Stream<DeviceState> deviceStateStream() {
    return MetaWearablesDatPlatform.instance.deviceStateStream();
  }
}
