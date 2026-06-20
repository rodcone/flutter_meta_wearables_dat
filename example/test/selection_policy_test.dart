import 'package:flutter/services.dart';
import 'package:flutter_meta_wearables_dat_example/providers/device_provider.dart';
import 'package:flutter_meta_wearables_dat_example/providers/mock_device_provider.dart';
import 'package:flutter_meta_wearables_dat_example/providers/stream_provider.dart';
import 'package:flutter_test/flutter_test.dart';

/// Channels the providers touch on construction. Mocked to no-op so the
/// providers can be built without a real platform.
const _channels = <String>[
  'flutter_meta_wearables_dat',
  'flutter_meta_wearables_dat/active_device',
  'flutter_meta_wearables_dat/device_state',
  'flutter_meta_wearables_dat/registration_state',
  'flutter_meta_wearables_dat/stream_session_state',
  'flutter_meta_wearables_dat/stream_session_errors',
  'flutter_meta_wearables_dat/video_stream_size',
  'flutter_meta_wearables_dat/video_frames',
  'flutter_meta_wearables_dat_mock_device',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  StreamSessionProvider build() =>
      StreamSessionProvider(DeviceProvider(), MockDeviceProvider());

  setUp(() {
    for (final ch in _channels) {
      messenger.setMockMethodCallHandler(MethodChannel(ch), (_) async => null);
    }
  });

  tearDown(() {
    for (final ch in _channels) {
      messenger.setMockMethodCallHandler(MethodChannel(ch), null);
    }
  });

  test('selectDevice updates selection; null means Automatic', () {
    final sp = build();
    expect(sp.selectedDeviceId, isNull, reason: 'defaults to Automatic');

    sp.selectDevice('dev-A');
    expect(sp.selectedDeviceId, 'dev-A');

    sp.selectDevice(null);
    expect(sp.selectedDeviceId, isNull);

    sp.dispose();
  });

  test('pairing a mock pins the mock id explicitly', () {
    final sp = build()
      ..syncMockSelection(mockId: 'mock-1', previousMockId: null);
    expect(sp.selectedDeviceId, 'mock-1');
    sp.dispose();
  });

  test('unpairing the mock preserves a real-pair selection', () {
    final sp = build()
      ..syncMockSelection(mockId: 'mock-1', previousMockId: null);
    expect(sp.selectedDeviceId, 'mock-1');

    // User then picks a real pair.
    sp.selectDevice('real-B');
    expect(sp.selectedDeviceId, 'real-B');

    // Unpair the mock — selection now points at real-B, so it must stay.
    sp.syncMockSelection(mockId: null, previousMockId: 'mock-1');
    expect(sp.selectedDeviceId, 'real-B');

    sp.dispose();
  });

  test(
    'unpairing the mock clears selection only when it still points there',
    () {
      final sp = build()
        ..syncMockSelection(mockId: 'mock-2', previousMockId: null);
      expect(sp.selectedDeviceId, 'mock-2');

      sp.syncMockSelection(mockId: null, previousMockId: 'mock-2');
      expect(sp.selectedDeviceId, isNull);

      sp.dispose();
    },
  );

  test('canStartSelected reflects the selected pair connectivity', () async {
    messenger.setMockMethodCallHandler(
      const MethodChannel('flutter_meta_wearables_dat'),
      (call) async {
        if (call.method == 'getDevices') {
          return <Object?>[
            <Object?, Object?>{
              'id': 'A',
              'name': 'A',
              'deviceType': 'rayBanMeta',
              'linkState': 'connected',
              'compatibility': 'compatible',
              'supportsDisplay': false,
              'isActive': false,
              'isStreamingDevice': false,
            },
            <Object?, Object?>{
              'id': 'B',
              'name': 'B',
              'deviceType': 'rayBanMeta',
              'linkState': 'disconnected',
              'compatibility': 'compatible',
              'supportsDisplay': false,
              'isActive': false,
              'isStreamingDevice': false,
            },
          ];
        }
        return null;
      },
    );

    final sp = build();
    addTearDown(sp.dispose);
    await sp.refreshDevices();

    // No selection + no active device → Start disabled.
    expect(sp.canStartSelected, isFalse);
    // A connected pair selected → Start enabled even with no auto-active device
    // (this is the deadlock fix: you can pick a connected pair to switch to).
    sp.selectDevice('A');
    expect(sp.canStartSelected, isTrue);
    // A disconnected pair selected → Start disabled.
    sp.selectDevice('B');
    expect(sp.canStartSelected, isFalse);
  });
}
