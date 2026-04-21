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
            // Error banner at the top
            if (streamProvider.lastError != null)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red.shade900.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          streamProvider.lastError!.isThermalCritical
                              ? Icons.thermostat
                              : Icons.error_outline,
                          color: Colors.white,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            streamProvider.lastError!.message,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: streamProvider.dismissError,
                          child: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ],
                    ),
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
