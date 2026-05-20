import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_meta_wearables_dat/flutter_meta_wearables_dat.dart';
import 'package:flutter_meta_wearables_dat_example/providers/device_provider.dart';
import 'package:flutter_meta_wearables_dat_example/providers/mock_device_provider.dart';
import 'package:flutter_meta_wearables_dat_example/providers/stream_provider.dart'
    as stream_providers;
import 'package:flutter_meta_wearables_dat_example/shared/widgets/meta_button.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

class StreamScreen extends StatefulWidget {
  const StreamScreen({super.key});

  @override
  State<StreamScreen> createState() => _StreamScreenState();
}

class _StreamScreenState extends State<StreamScreen> {
  stream_providers.StreamSessionProvider? _streamProvider;
  StreamSessionError? _shownError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _streamProvider = context.read<stream_providers.StreamSessionProvider>();
      _streamProvider!.addListener(_onStreamProviderChanged);
      _onStreamProviderChanged();
    });
  }

  @override
  void dispose() {
    _streamProvider?.removeListener(_onStreamProviderChanged);
    super.dispose();
  }

  void _onStreamProviderChanged() {
    final error = _streamProvider?.lastError;
    if (error == null || identical(error, _shownError)) return;
    _shownError = error;
    _showErrorSnackBar(error);
    _streamProvider?.clearError();
  }

  void _showErrorSnackBar(StreamSessionError error) {
    if (!mounted) return;

    final isDatUpdate = error.code == 'datAppOnTheGlassesUpdateRequired';
    final isTransient = error.code == 'noEligibleDevice';

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                error.isThermalCritical
                    ? Icons.thermostat
                    : isDatUpdate
                        ? Icons.system_update
                        : Icons.error_outline,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(error.message),
              ),
            ],
          ),
          backgroundColor: Colors.red.shade900,
          duration: isTransient
              ? const Duration(seconds: 3)
              : isDatUpdate
                  ? const Duration(seconds: 10)
                  : const Duration(seconds: 6),
          action: isDatUpdate
              ? SnackBarAction(
                  label: 'Update',
                  textColor: Colors.white,
                  onPressed: () {
                    unawaited(_streamProvider?.openDATGlassesAppUpdate());
                  },
                )
              : null,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer3<
      DeviceProvider,
      MockDeviceProvider,
      stream_providers.StreamSessionProvider
    >(
      builder: (context, deviceProvider, mockDeviceProvider, streamProvider, child) {
        // Use the actual active device status from the DAT SDK
        final hasActiveDevice = streamProvider.hasActiveDevice;

        return Stack(
          children: [
            // Full screen video stream or placeholder
            Positioned.fill(
              child: streamProvider.isStreaming
                  ? _TextureStreamWidget(
                      textureId: streamProvider.textureId!,
                      videoStreamSize: streamProvider.videoStreamSize,
                    )
                  : ColoredBox(
                      color: Colors.black,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Image.asset(
                              'assets/images/cameraAccessIcon.png',
                              width: 120,
                              color: Colors.white,
                              colorBlendMode: BlendMode.srcIn,
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Stream Your Glasses Camera',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child: Text(
                                'Tap the Start streaming button to stream video from your glasses or use the camera button to take a photo from your glasses.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 15,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
            // Thermal indicator (top-left) while streaming. Hidden for
            // unknown/none levels since those aren't actionable for the user.
            if (streamProvider.isStreaming &&
                streamProvider.thermalLevel != null &&
                streamProvider.thermalLevel != ThermalLevel.unknown &&
                streamProvider.thermalLevel != ThermalLevel.none)
              Positioned(
                top: 0,
                left: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: _ThermalChip(level: streamProvider.thermalLevel!),
                  ),
                ),
              ),
            // Controls overlay at the bottom
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Session state label
                    if (streamProvider.sessionState != null &&
                        streamProvider.sessionState != StreamSessionState.streaming &&
                        streamProvider.sessionState != StreamSessionState.stopped)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 5),
                        child: Text(
                          _sessionStateLabel(streamProvider.sessionState!),
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white.withOpacity(0.7),
                          ),
                        ),
                      ),
                    // Show "Waiting for an active device" message when no device is available
                    // Always render it but control visibility with opacity (like native sample app)
                    Opacity(
                      opacity: hasActiveDevice ? 0.0 : 1.0,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 5),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.hourglass_empty,
                              size: 16,
                              color: Colors.white.withOpacity(0.7),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Waiting for an active device',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.white.withOpacity(0.7),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Show Start button only when not streaming
                    if (!streamProvider.isStreaming)
                      MetaButton.text(
                        text: 'Start streaming',
                        enabled: hasActiveDevice,
                        onPressed: () async {
                          unawaited(HapticFeedback.mediumImpact());

                          if (!hasActiveDevice) return;

                          final hasPermission = await deviceProvider
                              .ensureCameraPermission();
                          if (!hasPermission || !context.mounted) return;

                          await streamProvider.startStreamSession();
                        },
                      ),
                    // Show Stop button only when streaming
                    if (streamProvider.isStreaming)
                      Row(
                        children: [
                          Expanded(
                            child: MetaButton.text(
                              text: 'Stop streaming',
                              onPressed: () {
                                streamProvider.stopStreamSession();
                              },
                              color: Colors.red,
                            ),
                          ),
                          MetaButton.icon(
                            icon: const Icon(Icons.camera_alt),
                            onPressed: () async {
                              unawaited(HapticFeedback.mediumImpact());

                              final photo = await streamProvider.capturePhoto();
                              if (photo == null || !context.mounted) {
                                return;
                              }
                              final box =
                                  context.findRenderObject() as RenderBox?;
                              final shareOrigin = box == null
                                  ? null
                                  : box.localToGlobal(Offset.zero) & box.size;
                              await SharePlus.instance.share(
                                ShareParams(
                                  files: [
                                    XFile.fromData(
                                      photo.bytes,
                                      mimeType: photo.mimeType,
                                    ),
                                  ],
                                  fileNameOverrides: [
                                    'captured_photo.${photo.fileExtension}',
                                  ],
                                  sharePositionOrigin: shareOrigin,
                                ),
                              );
                            },
                            color: Colors.blue,
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

String _sessionStateLabel(StreamSessionState state) {
  return switch (state) {
    StreamSessionState.stopping => 'Stopping...',
    StreamSessionState.waitingForDevice => 'Waiting for device...',
    StreamSessionState.starting => 'Starting...',
    StreamSessionState.paused => 'Paused',
    _ => '',
  };
}

/// Compact thermal-level indicator shown while streaming. Color escalates
/// from amber → red as the SDK reports hotter readings, mirroring the
/// `ThermalLevel` enum from `MetaWearablesDat.deviceStateStream()`.
class _ThermalChip extends StatelessWidget {
  final ThermalLevel level;

  const _ThermalChip({required this.level});

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(level);
    final label = _labelFor(level);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.85),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.thermostat, color: Colors.white, size: 14),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Color _colorFor(ThermalLevel level) {
    return switch (level) {
      ThermalLevel.unknown ||
      ThermalLevel.none ||
      ThermalLevel.light =>
        Colors.green.shade700,
      ThermalLevel.moderate => Colors.amber.shade800,
      ThermalLevel.severe => Colors.orange.shade800,
      ThermalLevel.critical => Colors.red.shade700,
      ThermalLevel.emergency || ThermalLevel.shutdown => Colors.red.shade900,
    };
  }

  String _labelFor(ThermalLevel level) {
    return switch (level) {
      ThermalLevel.unknown => 'Thermal: unknown',
      ThermalLevel.none => 'Cool',
      ThermalLevel.light => 'Warm',
      ThermalLevel.moderate => 'Warming',
      ThermalLevel.severe => 'Hot',
      ThermalLevel.critical => 'Critical',
      ThermalLevel.emergency => 'Emergency',
      ThermalLevel.shutdown => 'Shutdown',
    };
  }
}

/// Renders the video stream using Flutter's Texture API (zero-copy).
/// The native side pushes CVPixelBuffer / SurfaceTexture frames directly —
/// no JPEG encoding, no byte copying, no Dart-side decoding.
///
/// The aspect ratio is driven by the native frame dimensions surfaced via
/// `videoStreamSizeStream`. Until the first size arrives we fall back to a
/// 9:16 portrait frame, which matches the Ray-Ban Meta's default stream
/// orientation.
class _TextureStreamWidget extends StatelessWidget {
  final int textureId;
  final VideoStreamSize? videoStreamSize;

  const _TextureStreamWidget({
    required this.textureId,
    required this.videoStreamSize,
  });

  @override
  Widget build(BuildContext context) {
    final aspectRatio = videoStreamSize?.aspectRatio ?? 9 / 16;
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: AspectRatio(
          aspectRatio: aspectRatio,
          child: Texture(textureId: textureId),
        ),
      ),
    );
  }
}
