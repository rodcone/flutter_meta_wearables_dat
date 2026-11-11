import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_meta_wearables_dat/flutter_meta_wearables_dat.dart';
import 'package:flutter_meta_wearables_dat/meta_wearables_dat_platform_interface.dart';
import 'package:flutter_meta_wearables_dat_example/providers/motion_provider.dart';
import 'package:flutter_meta_wearables_dat_example/screens/motion/motion_sheet.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _MotionPlatform extends MetaWearablesDatPlatform {
  final states = StreamController<MotionState>.broadcast(sync: true);
  final errors = StreamController<MotionError>.broadcast(sync: true);
  final samples = StreamController<MotionSample>.broadcast(sync: true);
  String? startedDevice;
  MotionSamplingRate? startedRate;
  PlatformException? startError;
  PlatformException? stopError;
  int starts = 0;
  int stops = 0;

  @override
  Stream<MotionState> motionStateStream() => states.stream;

  @override
  Stream<MotionError> motionErrorStream() => errors.stream;

  @override
  Stream<MotionSample> motionSamplesStream() => samples.stream;

  @override
  Future<bool> startMotion(
    String? deviceId, {
    MotionSamplingRate samplingRate = MotionSamplingRate.hz10,
  }) async {
    starts++;
    if (startError != null) throw startError!;
    startedDevice = deviceId;
    startedRate = samplingRate;
    states
      ..add(MotionState.starting)
      ..add(MotionState.started);
    return true;
  }

  @override
  Future<bool> stopMotion() async {
    stops++;
    if (stopError != null) throw stopError!;
    states.add(MotionState.stopped);
    return true;
  }

  Future<void> close() async {
    await states.close();
    await errors.close();
    await samples.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MetaWearablesDatPlatform original;
  late _MotionPlatform platform;
  late MotionProvider motion;

  setUp(() {
    original = MetaWearablesDatPlatform.instance;
    platform = _MotionPlatform();
    MetaWearablesDatPlatform.instance = platform;
  });

  tearDown(() async {
    motion.dispose();
    await platform.close();
    MetaWearablesDatPlatform.instance = original;
  });

  testWidgets('starts selected Motion without camera and stops independently', (
    tester,
  ) async {
    motion = MotionProvider()..setSamplingRate(MotionSamplingRate.hz60);
    await motion.start('glasses-2');
    expect(platform.startedDevice, 'glasses-2');
    expect(platform.startedRate, MotionSamplingRate.hz60);
    expect(motion.state, MotionState.started);
    expect(motion.isActive, isTrue);
    // Camera/permission APIs remain unimplemented in the fake: calling one fails.
    motion.setSamplingRate(MotionSamplingRate.hz5);
    expect(motion.samplingRate, MotionSamplingRate.hz60);
    await motion.stop();
    expect(platform.stops, 1);
    expect(motion.state, MotionState.stopped);
    expect(motion.isActive, isFalse);
    motion.setSamplingRate(MotionSamplingRate.hz5);
    expect(motion.samplingRate, MotionSamplingRate.hz5);
  });

  testWidgets('counts every nullable sample while coalescing notifications', (
    tester,
  ) async {
    motion = MotionProvider();
    await motion.start(null);
    var notifications = 0;
    motion.addListener(() => notifications++);
    for (var i = 0; i < 60; i++) {
      platform.samples.add(
        MotionSample(
          timestampNs: i,
          source: MotionSource.glasses,
          orientation: const MotionQuaternion(x: 0, y: 0, z: 0, w: 1),
        ),
      );
    }
    expect(motion.sampleCount, 60);
    expect(motion.latestSample?.timestampNs, 59);
    expect(motion.latestSample?.accelerometer, isNull);
    expect(notifications, 0);
    await tester.pump(const Duration(milliseconds: 99));
    expect(notifications, 0);
    await tester.pump(const Duration(milliseconds: 1));
    expect(notifications, 1);
  });

  testWidgets('start failures remain visible and allow a corrected retry', (
    tester,
  ) async {
    motion = MotionProvider();
    platform.startError = PlatformException(
      code: 'DEVICE_IN_USE',
      message: 'Another pair already has an active session.',
    );
    await motion.start('other');
    expect(motion.lastError?.code, 'DEVICE_IN_USE');
    expect(motion.commandPending, isFalse);
    expect(motion.isActive, isFalse);
    platform.startError = null;
    await motion.start(null);
    expect(motion.lastError, isNull);
    expect(motion.state, MotionState.started);

    platform.states.add(MotionState.paused);
    platform.errors.add(
      const MotionError(
        code: 'deviceDisconnected',
        message: 'Reconnect your glasses.',
      ),
    );
    expect(motion.state, MotionState.paused);
    expect(motion.lastError?.isDeviceDisconnected, isTrue);
    expect(
      platform.starts,
      2,
      reason: 'Errors must not trigger hidden retries.',
    );
  });

  testWidgets('failed stop preserves activity and permits another stop', (
    tester,
  ) async {
    motion = MotionProvider();
    await motion.start(null);
    platform.stopError = PlatformException(code: 'STOP_TIMEOUT');
    await motion.stop();
    expect(motion.isActive, isTrue);
    expect(motion.lastError?.code, 'STOP_TIMEOUT');
    expect(motion.commandPending, isFalse);
    platform.stopError = null;
    await motion.stop();
    expect(motion.isActive, isFalse);
  });

  testWidgets(
    'dispose cancels subscriptions and a queued sample notification',
    (
      tester,
    ) async {
      motion = MotionProvider();
      final extra = MotionProvider();
      await extra.start(null);
      var notifications = 0;
      extra.addListener(() => notifications++);
      platform.samples.add(
        const MotionSample(timestampNs: 1, source: MotionSource.glasses),
      );
      extra.dispose();
      await tester.pump(const Duration(milliseconds: 150));
      expect(notifications, 0);
      expect(platform.stops, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Motion sheet starts without camera and renders missing fields', (
    tester,
  ) async {
    motion = MotionProvider();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: motion,
        child: const MaterialApp(
          home: Scaffold(body: MotionSheet(deviceId: 'selected-glasses')),
        ),
      ),
    );
    expect(find.text('Start Motion'), findsOneWidget);
    await tester.tap(find.text('Start Motion'));
    await tester.pump();
    expect(platform.startedDevice, 'selected-glasses');
    expect(find.text('Stop Motion'), findsOneWidget);
    platform.samples.add(
      const MotionSample(
        timestampNs: 123456789,
        source: MotionSource.glasses,
        orientation: MotionQuaternion(x: 0, y: 0, z: 0, w: 1),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Samples received: 1'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Orientation (quaternion)'),
      200,
    );
    expect(find.textContaining('w 1.000'), findsOneWidget);
    expect(find.text('Unavailable'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(
      platform.stops,
      0,
      reason: 'Closing the sheet keeps Motion running.',
    );
  });
}
