import 'package:flutter/services.dart';
import 'package:flutter_meta_wearables_dat/flutter_meta_wearables_dat.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MotionSample.fromMap', () {
    test('decodes platform samples without losing timestamp precision', () {
      // Native timestamps intentionally exceed JavaScript's exact integer range.
      // ignore: avoid_js_rounded_ints
      const timestampNs = 9007199254741017;
      const wireSample = <String, Object?>{
        'timestampNs': timestampNs,
        'source': 'neuralBand',
        'accelerometer': {'x': 0, 'y': -9.81, 'z': 1},
        'gyroscope': {'x': 0.1, 'y': 0, 'z': -0.3},
        'magnetometer': {'x': 14, 'y': -5.5, 'z': 30},
        'orientation': {'x': 0, 'y': 0.5, 'z': 0, 'w': 0.866},
        'futureField': true,
      };
      const codec = StandardMessageCodec();
      final decoded = codec.decodeMessage(codec.encodeMessage(wireSample));
      final sample = MotionSample.fromMap(decoded! as Map<Object?, Object?>);

      expect(sample.timestampNs, timestampNs);
      expect(sample.source, MotionSource.neuralBand);
      expect(
        sample.accelerometer,
        const MotionVector3(x: 0, y: -9.81, z: 1),
      );
      expect(sample.gyroscope, const MotionVector3(x: 0.1, y: 0, z: -0.3));
      expect(sample.magnetometer, const MotionVector3(x: 14, y: -5.5, z: 30));
      expect(
        sample.orientation,
        const MotionQuaternion(x: 0, y: 0.5, z: 0, w: 0.866),
      );
      expect(sample.accelerometer!.x, isA<double>());
      expect(sample.orientation!.x, isA<double>());
    });

    test('leaves missing or explicitly null readings unavailable', () {
      for (final nullableReadings in [
        <String, Object?>{},
        <String, Object?>{
          'accelerometer': null,
          'gyroscope': null,
          'magnetometer': null,
          'orientation': null,
        },
      ]) {
        final sample = MotionSample.fromMap({
          'timestampNs': 12,
          'source': 'glasses',
          ...nullableReadings,
        });

        expect(sample.accelerometer, isNull);
        expect(sample.gyroscope, isNull);
        expect(sample.magnetometer, isNull);
        expect(sample.orientation, isNull);
      }
    });

    test('decodes each sensor independently', () {
      for (final field in [
        'accelerometer',
        'gyroscope',
        'magnetometer',
        'orientation',
      ]) {
        final sample = MotionSample.fromMap({
          'timestampNs': 12,
          'source': 'glasses',
          field: {'x': 1, 'y': 2, 'z': 3, if (field == 'orientation') 'w': 4},
        });
        final readings = <String, Object?>{
          'accelerometer': sample.accelerometer,
          'gyroscope': sample.gyroscope,
          'magnetometer': sample.magnetometer,
          'orientation': sample.orientation,
        };

        for (final reading in readings.entries) {
          expect(
            reading.value,
            reading.key == field ? isNotNull : isNull,
            reason: '$field must not require or fabricate ${reading.key}',
          );
        }
      }
    });

    test('keeps samples from an unknown future source', () {
      final sample = MotionSample.fromMap(const {
        'timestampNs': 12,
        'source': 'futureWearable',
      });

      expect(sample.source, MotionSource.unknown);
    });

    test('rejects missing required timestamp or source', () {
      expect(
        () => MotionSample.fromMap(const {'source': 'glasses'}),
        throwsA(isA<TypeError>()),
      );
      expect(
        () => MotionSample.fromMap(const {'timestampNs': 12}),
        throwsA(isA<TypeError>()),
      );
      expect(
        () => MotionSample.fromMap(const {
          'timestampNs': 12.5,
          'source': 'glasses',
        }),
        throwsA(isA<TypeError>()),
      );
    });
  });

  group('Motion enums', () {
    test('exposes exactly the supported sampling rates', () {
      expect(
        MotionSamplingRate.values.map((rate) => rate.value),
        [5, 10, 15, 24, 30, 60],
      );
    });

    test('maps native states including Android paused', () {
      expect(MotionState.fromCode('stopped'), MotionState.stopped);
      expect(MotionState.fromCode('starting'), MotionState.starting);
      expect(MotionState.fromCode('started'), MotionState.started);
      expect(MotionState.fromCode('stopping'), MotionState.stopping);
      expect(MotionState.fromCode('paused'), MotionState.paused);
      expect(MotionState.fromCode('futureState'), MotionState.unknown);
      expect(MotionState.fromCode(null), MotionState.unknown);
    });

    test('maps known and future sources', () {
      expect(MotionSource.fromCode('glasses'), MotionSource.glasses);
      expect(MotionSource.fromCode('neuralBand'), MotionSource.neuralBand);
      expect(MotionSource.fromCode('futureSource'), MotionSource.unknown);
      expect(MotionSource.fromCode(null), MotionSource.unknown);
    });
  });

  group('MotionError', () {
    test('identifies known failures and preserves unknown codes', () {
      for (final code in [
        'sensorUnavailable',
        'capabilityClosed',
        'deviceDisconnected',
        'futureError',
      ]) {
        final error = MotionError.fromMap({'code': code, 'message': 'Details'});

        expect(error.code, code);
        expect(error.message, 'Details');
        expect(error.isSensorUnavailable, code == 'sensorUnavailable');
        expect(error.isCapabilityClosed, code == 'capabilityClosed');
        expect(error.isDeviceDisconnected, code == 'deviceDisconnected');
      }
    });
  });
}
