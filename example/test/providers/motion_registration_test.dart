import 'package:flutter/services.dart';
import 'package:flutter_meta_wearables_dat_example/providers/device_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel('flutter_meta_wearables_dat');
  const registration = MethodChannel(
    'flutter_meta_wearables_dat/registration_state',
  );

  testWidgets('registration does not ask for camera or microphone permission', (
    tester,
  ) async {
    final methods = <String>[];
    messenger
      ..setMockMethodCallHandler(channel, (call) async {
        methods.add(call.method);
        return call.method == 'getRegistrationState' ? 1 : true;
      })
      ..setMockMethodCallHandler(registration, (call) async => null);
    final device = DeviceProvider();
    await tester.pump();
    await messenger.handlePlatformMessage(
      registration.name,
      const StandardMethodCodec().encodeSuccessEnvelope(3),
      (_) {},
    );
    await tester.pump();
    expect(device.isRegistered, isTrue);
    expect(methods, contains('restartActiveDeviceMonitoring'));
    expect(methods, isNot(contains('requestCameraPermission')));
    expect(methods, isNot(contains('requestMicrophonePermission')));
    device.dispose();
    await tester.pump();
    messenger
      ..setMockMethodCallHandler(channel, null)
      ..setMockMethodCallHandler(registration, null);
  });
}
