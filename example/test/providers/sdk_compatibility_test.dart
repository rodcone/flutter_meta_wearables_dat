import 'package:flutter/services.dart';
import 'package:flutter_meta_wearables_dat_example/providers/device_provider.dart';
import 'package:flutter_meta_wearables_dat_example/providers/mock_device_provider.dart';
import 'package:flutter_meta_wearables_dat_example/providers/stream_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
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
  var starts = 0;
  var stops = 0;

  setUp(() {
    starts = 0;
    stops = 0;
    for (final name in channels) {
      messenger.setMockMethodCallHandler(MethodChannel(name), (call) async {
        switch (call.method) {
          case 'startStreamSession':
            starts++;
            return 42;
          case 'stopStreamSession':
            stops++;
            return true;
          case 'getDevices':
            return <Object>[];
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
  });

  tearDown(() {
    for (final name in channels) {
      messenger.setMockMethodCallHandler(MethodChannel(name), null);
    }
  });

  for (final code in ['dwaOutOfStuRange', 'insufficientSDKVersion']) {
    testWidgets('$code follows its warning or terminal lifecycle', (
      tester,
    ) async {
      final device = DeviceProvider();
      final mock = MockDeviceProvider();
      final stream = StreamSessionProvider(device, mock);
      await tester.pump();
      await stream.startStreamSession();
      await tester.pump();
      expect(stream.textureId, 42);

      await messenger.handlePlatformMessage(
        'flutter_meta_wearables_dat/stream_session_errors',
        const StandardMethodCodec().encodeSuccessEnvelope({
          'code': code,
          'message': 'Compatibility test',
        }),
        (_) {},
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 20));

      expect(starts, 1, reason: 'Neither compatibility code should auto-retry');
      if (code == 'dwaOutOfStuRange') {
        expect(stops, 0);
        expect(stream.textureId, 42);
        expect(stream.isStreaming, isTrue);
      } else {
        expect(stops, 1);
        expect(stream.textureId, isNull);
        expect(stream.isStreaming, isFalse);
      }
      stream.dispose();
      device.dispose();
      mock.dispose();
      await tester.pump();
    });
  }
}
