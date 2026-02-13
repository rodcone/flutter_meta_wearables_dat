import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
            // Controls overlay at the bottom
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
                    // FPS and quality settings (only when not streaming)
                    if (!streamProvider.isStreaming)
                      _StreamSettingsRow(
                        fps: streamProvider.fps,
                        highQuality: streamProvider.highQuality,
                        onFpsChanged: streamProvider.setFps,
                        onHighQualityChanged: streamProvider.setHighQuality,
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

                          await streamProvider.startStreamSession(
                            fps: streamProvider.fps,
                            streamQuality: streamProvider.streamQuality,
                          );
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

class _StreamSettingsRow extends StatelessWidget {
  final double fps;
  final bool highQuality;
  final ValueChanged<double> onFpsChanged;
  final ValueChanged<bool> onHighQualityChanged;

  const _StreamSettingsRow({
    required this.fps,
    required this.highQuality,
    required this.onFpsChanged,
    required this.onHighQualityChanged,
  });

  static const List<(double, IconData)> _fpsOptions = [
    (30.0, Icons.thirty_fps_select),
    (60.0, Icons.sixty_fps_select),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 50, right: 50),
      child: Row(
        children: [
          // FPS selection
          ..._fpsOptions.map(
            (option) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: _FpsIconButton(
                fps: option.$1,
                icon: option.$2,
                selected: fps == option.$1,
                onTap: () => onFpsChanged(option.$1),
              ),
            ),
          ),
          const Spacer(),
          // Quality toggle (high = filled, medium = outlined)
          _QualityIconButton(
            highQuality: highQuality,
            onTap: () => onHighQualityChanged(!highQuality),
          ),
        ],
      ),
    );
  }
}

class _FpsIconButton extends StatelessWidget {
  final double fps;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _FpsIconButton({
    required this.fps,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? Colors.white : Colors.white.withOpacity(0.5);
    return Tooltip(
      message: '${fps.toInt()} fps',
      child: Material(
        color: selected
            ? Colors.white.withOpacity(0.15)
            : Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(icon, size: 24, color: color),
          ),
        ),
      ),
    );
  }
}

class _QualityIconButton extends StatelessWidget {
  final bool highQuality;
  final VoidCallback onTap;

  const _QualityIconButton({
    required this.highQuality,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = highQuality ? Colors.white : Colors.white.withOpacity(0.5);
    return Tooltip(
      message: highQuality ? 'High quality' : 'Medium quality',
      child: Material(
        color: highQuality
            ? Colors.white.withOpacity(0.15)
            : Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(
              highQuality ? Icons.high_quality : Icons.high_quality_outlined,
              size: 24,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

/// Renders the video stream using Flutter's Texture API (zero-copy).
/// The native side pushes CVPixelBuffer / SurfaceTexture frames directly —
/// no JPEG encoding, no byte copying, no Dart-side decoding.
class _TextureStreamWidget extends StatelessWidget {
  final int textureId;

  const _TextureStreamWidget({required this.textureId});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: 720,
            height: 1280,
            child: Texture(textureId: textureId),
          ),
        ),
      ),
    );
  }
}
