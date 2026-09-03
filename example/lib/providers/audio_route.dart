import 'dart:io';

import 'package:flutter/services.dart';

/// A snapshot of the process-wide `AVAudioSession` route on iOS.
///
/// The plugin logs this as `[MWDAT-ROUTE]`, but a console is not always
/// reachable — release builds on a wirelessly-connected device, iOS versions
/// whose syslog relay no longer carries third-party `NSLog`, a tester with no
/// Mac. The diagnostic exists to be read in exactly those conditions, so the
/// example reads it over a method channel and shows it on screen instead.
class AudioRoute {
  const AudioRoute({
    required this.inputs,
    required this.outputs,
    required this.category,
    required this.mode,
    required this.usesBluetooth,
    required this.otherAudioPlaying,
  });

  final List<String> inputs;
  final List<String> outputs;
  final String category;
  final String mode;

  /// True when a Bluetooth port appears on either side — i.e. the keep-alive is
  /// sharing the radio the Bluetooth Classic camera transport needs.
  final bool usesBluetooth;
  final bool otherAudioPlaying;

  static const MethodChannel _channel = MethodChannel(
    'mwdat_example/diagnostics',
  );

  /// Reads the current route, or null on a platform or build where the
  /// diagnostics channel is not registered.
  static Future<AudioRoute?> read() async {
    if (!Platform.isIOS) return null;
    try {
      final map = await _channel.invokeMapMethod<String, dynamic>(
        'getAudioRoute',
      );
      if (map == null) return null;
      return AudioRoute(
        inputs: (map['inputs'] as List<dynamic>? ?? <dynamic>[]).cast<String>(),
        outputs: (map['outputs'] as List<dynamic>? ?? <dynamic>[])
            .cast<String>(),
        category: map['category'] as String? ?? '?',
        mode: map['mode'] as String? ?? '?',
        usesBluetooth: map['usesBluetooth'] as bool? ?? false,
        otherAudioPlaying: map['otherAudioPlaying'] as bool? ?? false,
      );
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Short form matching the plugin's own `[MWDAT-ROUTE]` log line, so a
  /// screenshot and a console line can be compared directly.
  String get summary => 'in=[${inputs.join(',')}] out=[${outputs.join(',')}]';
}
