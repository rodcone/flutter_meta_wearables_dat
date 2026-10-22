import 'package:flutter/foundation.dart';

/// Sampling rates supported by the DAT motion capability.
enum MotionSamplingRate {
  hz5(5),
  hz10(10),
  hz15(15),
  hz24(24),
  hz30(30),
  hz60(60);

  const MotionSamplingRate(this.value);

  /// The requested number of samples per second.
  final int value;
}

/// The lifecycle state of a motion capability.
enum MotionState {
  stopped('stopped'),
  starting('starting'),
  started('started'),
  stopping('stopping'),

  /// Motion is temporarily paused, as reported by Android.
  paused('paused'),

  /// A state this plugin version does not recognize.
  unknown('unknown');

  const MotionState(this.code);

  /// The canonical state code sent over the platform channel.
  final String code;

  /// Converts a platform code, preserving unrecognized states as [unknown].
  static MotionState fromCode(String? code) {
    return MotionState.values.firstWhere(
      (state) => state.code == code,
      orElse: () => MotionState.unknown,
    );
  }
}

/// The wearable that produced a motion sample.
enum MotionSource {
  glasses('glasses'),
  neuralBand('neuralBand'),

  /// A source this plugin version does not recognize.
  unknown('unknown');

  const MotionSource(this.code);

  /// The canonical source code sent over the platform channel.
  final String code;

  /// Converts a platform code, preserving unrecognized sources as [unknown].
  static MotionSource fromCode(String? code) {
    return MotionSource.values.firstWhere(
      (source) => source.code == code,
      orElse: () => MotionSource.unknown,
    );
  }
}

/// Three sensor components in the coordinate system reported by DAT.
///
/// The units depend on the sensor field containing this vector.
@immutable
class MotionVector3 {
  const MotionVector3({required this.x, required this.y, required this.z});

  /// Creates a vector from integer or floating-point platform components.
  factory MotionVector3.fromMap(Map<Object?, Object?> map) {
    return MotionVector3(
      x: (map['x']! as num).toDouble(),
      y: (map['y']! as num).toDouble(),
      z: (map['z']! as num).toDouble(),
    );
  }

  final double x;
  final double y;
  final double z;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MotionVector3 && other.x == x && other.y == y && other.z == z;

  @override
  int get hashCode => Object.hash(x, y, z);

  @override
  String toString() => 'MotionVector3(x: $x, y: $y, z: $z)';
}

/// An orientation quaternion in the reference frame reported by DAT.
///
/// [x], [y], and [z] are the vector components; [w] is the scalar component.
@immutable
class MotionQuaternion {
  const MotionQuaternion({
    required this.x,
    required this.y,
    required this.z,
    required this.w,
  });

  /// Creates a quaternion from integer or floating-point platform components.
  factory MotionQuaternion.fromMap(Map<Object?, Object?> map) {
    return MotionQuaternion(
      x: (map['x']! as num).toDouble(),
      y: (map['y']! as num).toDouble(),
      z: (map['z']! as num).toDouble(),
      w: (map['w']! as num).toDouble(),
    );
  }

  final double x;
  final double y;
  final double z;
  final double w;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MotionQuaternion &&
          other.x == x &&
          other.y == y &&
          other.z == z &&
          other.w == w;

  @override
  int get hashCode => Object.hash(x, y, z, w);

  @override
  String toString() => 'MotionQuaternion(x: $x, y: $y, z: $z, w: $w)';
}

/// A timestamped set of independently optional readings from a wearable.
///
/// A `null` reading means that sensor data was unavailable for this sample.
/// Readings retain the SDK's coordinate system and orientation reference frame.
@immutable
class MotionSample {
  const MotionSample({
    required this.timestampNs,
    required this.source,
    this.accelerometer,
    this.gyroscope,
    this.magnetometer,
    this.orientation,
  });

  /// Creates a sample from a platform-channel map.
  ///
  /// [timestampNs] and [source] must be present. Unknown source codes become
  /// [MotionSource.unknown]; missing or null sensor readings remain `null`.
  factory MotionSample.fromMap(Map<Object?, Object?> map) {
    final accelerometer = map['accelerometer'] as Map<Object?, Object?>?;
    final gyroscope = map['gyroscope'] as Map<Object?, Object?>?;
    final magnetometer = map['magnetometer'] as Map<Object?, Object?>?;
    final orientation = map['orientation'] as Map<Object?, Object?>?;
    return MotionSample(
      timestampNs: map['timestampNs']! as int,
      source: MotionSource.fromCode(map['source']! as String),
      accelerometer: accelerometer == null
          ? null
          : MotionVector3.fromMap(accelerometer),
      gyroscope: gyroscope == null ? null : MotionVector3.fromMap(gyroscope),
      magnetometer: magnetometer == null
          ? null
          : MotionVector3.fromMap(magnetometer),
      orientation: orientation == null
          ? null
          : MotionQuaternion.fromMap(orientation),
    );
  }

  /// The device-monotonic timestamp in nanoseconds, not a wall-clock time.
  final int timestampNs;

  /// The wearable that produced these readings.
  final MotionSource source;

  /// Acceleration including gravity, in meters per second squared.
  final MotionVector3? accelerometer;

  /// Angular velocity in radians per second.
  final MotionVector3? gyroscope;

  /// Magnetic field in microteslas.
  final MotionVector3? magnetometer;

  /// Orientation as a quaternion with scalar component [MotionQuaternion.w].
  final MotionQuaternion? orientation;
}

/// An asynchronous motion capability or device-session failure.
@immutable
class MotionError {
  const MotionError({required this.code, required this.message});

  /// Creates an error from its platform-channel representation.
  factory MotionError.fromMap(Map<Object?, Object?> map) {
    return MotionError(
      code: map['code']! as String,
      message: map['message']! as String,
    );
  }

  /// The SDK or plugin code, preserved even when this version does not know it.
  final String code;

  /// A human-readable description of the failure.
  final String message;

  /// Whether the requested sensor is unavailable.
  bool get isSensorUnavailable => code == 'sensorUnavailable';

  /// Whether the motion capability has closed.
  bool get isCapabilityClosed => code == 'capabilityClosed';

  /// Whether the wearable disconnected.
  bool get isDeviceDisconnected => code == 'deviceDisconnected';

  @override
  String toString() => 'MotionError($code): $message';
}
