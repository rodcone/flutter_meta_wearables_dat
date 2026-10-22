import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_meta_wearables_dat/flutter_meta_wearables_dat.dart';
import 'package:flutter_meta_wearables_dat/meta_wearables_dat_method_channel.dart';
import 'package:flutter_meta_wearables_dat/meta_wearables_dat_platform_interface.dart';
import 'package:flutter_meta_wearables_dat_example/providers/device_provider.dart';
import 'package:flutter_meta_wearables_dat_example/providers/mock_device_provider.dart';
import 'package:flutter_meta_wearables_dat_example/providers/stream_provider.dart';
import 'package:flutter_meta_wearables_dat_example/screens/stream/device_state_card.dart';
import 'package:flutter_meta_wearables_dat_example/screens/stream/stream_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const codec = StandardMethodCodec();
  const channels = [
    'flutter_meta_wearables_dat',
    'flutter_meta_wearables_dat/active_device',
    'flutter_meta_wearables_dat/device_state',
    'flutter_meta_wearables_dat/registration_state',
    'flutter_meta_wearables_dat/stream_session_state',
    'flutter_meta_wearables_dat/stream_session_errors',
    'flutter_meta_wearables_dat/video_stream_size',
    'flutter_meta_wearables_dat_mock_device',
  ];
  late MetaWearablesDatPlatform original;
  late DeviceProvider device;
  late MockDeviceProvider mock;
  late StreamSessionProvider stream;
  late List<String> calls;
  const snapshot = <String, Object?>{
    'deviceId': 'a',
    'linkState': 'connected',
    'compatibility': 'compatible',
    'thermalLevel': 3,
    'batteryLevel': 72,
    'chargingState': 'notCharging',
    'donState': 'donned',
    'hingeState': 'open',
  };
  Future<void> emit(String channel, Object? data) =>
      messenger.handlePlatformMessage(
        'flutter_meta_wearables_dat/$channel',
        codec.encodeSuccessEnvelope(data),
        (_) {},
      );
  setUp(() {
    calls = [];
    original = MetaWearablesDatPlatform.instance;
    MetaWearablesDatPlatform.instance = MethodChannelMetaWearablesDat();
    for (final channel in channels) {
      messenger.setMockMethodCallHandler(MethodChannel(channel), (call) async {
        calls.add(call.method);
        switch (call.method) {
          case 'getDevices':
            return [
              {'id': 'a', 'name': 'Glasses A', 'linkState': 'connected'},
              {'id': 'b', 'name': 'Glasses B', 'linkState': 'connected'},
            ];
          case 'getRegistrationState':
            return 3;
          case 'listen':
          case 'cancel':
            return null;
          default:
            return true;
        }
      });
    }
    device = DeviceProvider();
    mock = MockDeviceProvider();
    stream = StreamSessionProvider(device, mock);
  });
  tearDown(() async {
    stream.dispose();
    device.dispose();
    mock.dispose();
    await Future<void>.delayed(Duration.zero);
    for (final channel in channels) {
      messenger.setMockMethodCallHandler(MethodChannel(channel), null);
    }
    MetaWearablesDatPlatform.instance = original;
  });
  testWidgets(
    'status appears before camera start and updates every physical field',
    (tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: device),
            ChangeNotifierProvider.value(value: mock),
            ChangeNotifierProvider.value(value: stream),
          ],
          child: const MaterialApp(home: Scaffold(body: StreamScreen())),
        ),
      );
      await tester.pump();
      await stream.refreshDevices();
      await emit('device_state', snapshot);
      await tester.pump();
      expect(find.text('Monitored device: Glasses A'), findsOneWidget);
      expect(find.textContaining('Battery 72%'), findsOneWidget);
      expect(stream.isStreaming, isFalse);
      expect(calls, isNot(contains('startStreamSession')));
      await emit('device_state', {
        ...snapshot,
        'batteryLevel': 71,
        'chargingState': 'charging',
        'donState': 'doffed',
        'hingeState': 'closed',
      });
      await tester.pump();
      expect(
        find.textContaining('Battery 71% · Charging · Removed · Hinges closed'),
        findsOneWidget,
      );
      expect(stream.thermalLevel, ThermalLevel.moderate);
      stream.selectDevice('b');
      await tester.pump();
      expect(find.text('Monitored device: Glasses A'), findsOneWidget);
      expect(stream.monitoredDeviceName, 'Glasses A');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'loss clears readings and active-channel order cannot erase a new pair',
    (tester) async {
      await tester.pump();
      await emit('device_state', snapshot);
      await tester.pump();
      await emit('device_state', {'thermalLevel': 0, 'deviceId': null});
      await tester.pump();
      expect(stream.deviceState?.batteryLevel, isNull);
      expect(stream.deviceState?.deviceId, isNull);
      await emit('device_state', {
        ...snapshot,
        'deviceId': 'b',
        'batteryLevel': 31,
      });
      await emit('active_device', false);
      await tester.pump();
      expect(stream.deviceState?.deviceId, 'b');
      expect(stream.deviceState?.batteryLevel, 31);
      await emit('registration_state', 1);
      await tester.pump();
      expect(stream.deviceState, isNull);
      expect(calls, isNot(contains('startStreamSession')));
      expect(calls, isNot(contains('stopStreamSession')));
    },
  );
  testWidgets('channel errors clear readings and later events recover', (
    tester,
  ) async {
    await tester.pump();
    await emit('device_state', snapshot);
    await tester.pump();
    await messenger.handlePlatformMessage(
      'flutter_meta_wearables_dat/device_state',
      codec.encodeErrorEnvelope(
        code: 'DEVICE_STATE_ERROR',
        message: 'Unavailable',
      ),
      (_) {},
    );
    await tester.pump();
    expect(stream.deviceState, isNull);
    await emit('device_state', snapshot);
    await tester.pump();
    expect(stream.deviceState?.batteryLevel, 72);
  });
  testWidgets(
    'unknown readings are not false empty, removed or closed states',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DeviceStateCard(
              state: DeviceState(thermalLevel: ThermalLevel.unknown),
            ),
          ),
        ),
      );
      expect(find.textContaining('Battery unknown'), findsOneWidget);
      expect(find.textContaining('Wear state unknown'), findsOneWidget);
      expect(find.textContaining('Hinges unknown'), findsOneWidget);
      expect(find.textContaining('0%'), findsNothing);
      expect(find.textContaining('Removed'), findsNothing);
      expect(find.textContaining('Hinges closed'), findsNothing);
    },
  );
  testWidgets('readout handles narrow screens and enlarged text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: DeviceStateCard(
              state: DeviceState.fromMap(snapshot),
              deviceName: 'A very long name for these glasses',
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'readout does not cover idle content on a small enlarged screen',
    (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: device),
            ChangeNotifierProvider.value(value: mock),
            ChangeNotifierProvider.value(value: stream),
          ],
          child: const MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Scaffold(body: StreamScreen()),
            ),
          ),
        ),
      );
      await tester.pump();
      await emit('device_state', snapshot);
      await tester.pump();
      expect(tester.takeException(), isNull);
      final status = tester.getRect(find.byType(DeviceStateCard));
      final heading = tester.getRect(find.text('Stream Your Glasses Camera'));
      expect(status.overlaps(heading), isFalse);
      await tester.ensureVisible(find.text('Start streaming'));
      await tester.pump();
      expect(find.text('Start streaming').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
