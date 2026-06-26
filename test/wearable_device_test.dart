import 'package:flutter_meta_wearables_dat/flutter_meta_wearables_dat.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WearableDeviceType.fromCode', () {
    test('maps known codes', () {
      expect(
        WearableDeviceType.fromCode('rayBanMeta'),
        WearableDeviceType.rayBanMeta,
      );
      expect(
        WearableDeviceType.fromCode('oakleyMetaHSTN'),
        WearableDeviceType.oakleyMetaHSTN,
      );
      expect(
        WearableDeviceType.fromCode('metaRayBanDisplay'),
        WearableDeviceType.metaRayBanDisplay,
      );
      expect(
        WearableDeviceType.fromCode('rayBanMetaOptics'),
        WearableDeviceType.rayBanMetaOptics,
      );
      expect(
        WearableDeviceType.fromCode('metaGlasses'),
        WearableDeviceType.metaGlasses,
      );
    });

    test('falls back to unknown for null/unrecognized', () {
      expect(WearableDeviceType.fromCode(null), WearableDeviceType.unknown);
      expect(WearableDeviceType.fromCode('nope'), WearableDeviceType.unknown);
    });
  });

  group('WearableLinkState.fromCode', () {
    test('maps known codes', () {
      expect(
        WearableLinkState.fromCode('connected'),
        WearableLinkState.connected,
      );
      expect(
        WearableLinkState.fromCode('connecting'),
        WearableLinkState.connecting,
      );
      expect(
        WearableLinkState.fromCode('disconnected'),
        WearableLinkState.disconnected,
      );
    });

    test('falls back to unknown for null/unrecognized', () {
      expect(WearableLinkState.fromCode(null), WearableLinkState.unknown);
      expect(WearableLinkState.fromCode('bogus'), WearableLinkState.unknown);
    });
  });

  group('WearableCompatibility.fromCode', () {
    test('maps known codes', () {
      expect(
        WearableCompatibility.fromCode('compatible'),
        WearableCompatibility.compatible,
      );
      expect(
        WearableCompatibility.fromCode('deviceUpdateRequired'),
        WearableCompatibility.deviceUpdateRequired,
      );
      expect(
        WearableCompatibility.fromCode('sdkUpdateRequired'),
        WearableCompatibility.sdkUpdateRequired,
      );
    });

    test('falls back to undefined (not unknown) for null/unrecognized', () {
      expect(
        WearableCompatibility.fromCode(null),
        WearableCompatibility.undefined,
      );
      expect(
        WearableCompatibility.fromCode('???'),
        WearableCompatibility.undefined,
      );
    });
  });

  group('WearableDevice.fromMap', () {
    test('parses a complete map', () {
      final device = WearableDevice.fromMap(const <String, dynamic>{
        'id': 'dev-1',
        'name': "Gautier's glasses",
        'deviceType': 'rayBanMeta',
        'linkState': 'connected',
        'compatibility': 'compatible',
        'supportsDisplay': false,
        'isActive': true,
        'isStreamingDevice': true,
        'firmwareInfo': '1.2.3',
      });
      expect(device.id, 'dev-1');
      expect(device.name, "Gautier's glasses");
      expect(device.type, WearableDeviceType.rayBanMeta);
      expect(device.linkState, WearableLinkState.connected);
      expect(device.compatibility, WearableCompatibility.compatible);
      expect(device.supportsDisplay, false);
      expect(device.isActive, true);
      expect(device.isStreamingDevice, true);
      expect(device.firmwareInfo, '1.2.3');
    });

    test('tolerates a minimal map (only id) with sensible defaults', () {
      final device = WearableDevice.fromMap(
        const <String, dynamic>{'id': 'dev-2'},
      );
      expect(device.id, 'dev-2');
      expect(device.name, 'dev-2', reason: 'name falls back to id');
      expect(device.type, WearableDeviceType.unknown);
      expect(device.linkState, WearableLinkState.unknown);
      expect(device.compatibility, WearableCompatibility.undefined);
      expect(device.supportsDisplay, false);
      expect(device.isActive, false);
      expect(device.isStreamingDevice, false);
      expect(device.firmwareInfo, isNull);
    });

    test('tolerates explicit null fields', () {
      final device = WearableDevice.fromMap(const <String, dynamic>{
        'id': 'dev-3',
        'name': null,
        'deviceType': null,
        'linkState': null,
        'compatibility': null,
        'supportsDisplay': null,
        'isActive': null,
        'isStreamingDevice': null,
        'firmwareInfo': null,
      });
      expect(device.name, 'dev-3');
      expect(device.type, WearableDeviceType.unknown);
      expect(device.firmwareInfo, isNull);
    });

    test('throws ArgumentError when id is missing', () {
      expect(
        () => WearableDevice.fromMap(const <String, dynamic>{'name': 'x'}),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError when id is blank', () {
      expect(
        () => WearableDevice.fromMap(const <String, dynamic>{'id': '   '}),
        throwsArgumentError,
      );
    });

    test('equality and hashCode are value-based', () {
      Map<String, dynamic> sample() => <String, dynamic>{
        'id': 'dev-4',
        'name': 'A',
        'deviceType': 'rayBanMeta',
        'linkState': 'connected',
        'compatibility': 'compatible',
        'supportsDisplay': false,
        'isActive': false,
        'isStreamingDevice': false,
      };
      expect(
        WearableDevice.fromMap(sample()),
        WearableDevice.fromMap(sample()),
      );
      expect(
        WearableDevice.fromMap(sample()).hashCode,
        WearableDevice.fromMap(sample()).hashCode,
      );
    });
  });
}
