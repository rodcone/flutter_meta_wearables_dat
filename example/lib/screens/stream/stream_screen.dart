import 'dart:ui' as ui;

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
  static const _videoFramesChannel = EventChannel(
    'flutter_meta_wearables_dat/video_frames',
  );

  @override
  Widget build(BuildContext context) {
    return Consumer3<
      DeviceProvider,
      MockDeviceProvider,
      stream_providers.StreamSessionProvider
    >(
      builder: (context, deviceProvider, mockDeviceProvider, streamProvider, child) {
        // deviceUUID is optional - use "auto" for AutoDeviceSelector if null
        final deviceUUID = mockDeviceProvider.deviceUUID ?? 'auto';

        // Use the actual active device status from the DAT SDK
        final hasActiveDevice = streamProvider.hasActiveDevice;

        return Stack(
          children: [
            // Full screen video stream or placeholder
            Positioned.fill(
              child: streamProvider.isStreaming
                  ? _VideoStreamWidget(
                      stream: _videoFramesChannel.receiveBroadcastStream({
                        'deviceUUID': deviceUUID,
                      }),
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
                    // Show Start button only when not streaming
                    if (!streamProvider.isStreaming)
                      MetaButton.text(
                        text: 'Start streaming',
                        enabled: hasActiveDevice,
                        onPressed: () async {
                          if (!hasActiveDevice) return;

                          final hasPermission = await deviceProvider
                              .ensureCameraPermission();
                          if (!hasPermission || !context.mounted) return;

                          await streamProvider.startStreamSession(fps: 45);
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

class _VideoStreamWidget extends StatefulWidget {
  final Stream<dynamic> stream;

  const _VideoStreamWidget({required this.stream});

  @override
  State<_VideoStreamWidget> createState() => _VideoStreamWidgetState();
}

class _VideoStreamWidgetState extends State<_VideoStreamWidget> {
  Uint8List? _lastFrameBytes;
  ui.Image? _decodedImage;

  @override
  void dispose() {
    _decodedImage?.dispose();
    super.dispose();
  }

  Future<void> _decodeAndSetImage(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final newImage = frame.image;

    if (mounted) {
      setState(() {
        _decodedImage?.dispose();
        _decodedImage = newImage;
        _lastFrameBytes = bytes;
      });
    } else {
      newImage.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: StreamBuilder<dynamic>(
        stream: widget.stream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Stream error: ${snapshot.error}',
                style: const TextStyle(color: Colors.white),
              ),
            );
          }

          // Decode and update frame when new data arrives
          if (snapshot.hasData) {
            final bytes = snapshot.data as Uint8List;
            // Only decode if it's a new frame (check by reference first, then by content if needed)
            if (_lastFrameBytes != bytes) {
              // Quick reference check - if different object, it's definitely a new frame
              _decodeAndSetImage(bytes);
            }
          }

          // Show decoded image if available, otherwise show waiting message
          if (_decodedImage != null) {
            // Check if image is landscape and needs rotation to portrait
            final isLandscape = _decodedImage!.width > _decodedImage!.height;
            return RepaintBoundary(
              child: isLandscape
                  ? RotatedBox(
                      quarterTurns: 1,
                      child: CustomPaint(
                        painter: _ImagePainter(_decodedImage!),
                        child: Container(),
                      ),
                    )
                  : CustomPaint(
                      painter: _ImagePainter(_decodedImage!),
                      child: Container(),
                    ),
            );
          }

          return const Center(
            child: Text(
              'Waiting for frames…',
              style: TextStyle(color: Colors.white70),
            ),
          );
        },
      ),
    );
  }
}

class _ImagePainter extends CustomPainter {
  final ui.Image image;

  _ImagePainter(this.image);

  @override
  void paint(Canvas canvas, Size size) {
    final srcRect = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );

    // Calculate aspect ratio preserving rect
    // For portrait display, we want to fit the image to fill the canvas
    // while maintaining aspect ratio
    final imageAspect = image.width / image.height;
    final canvasAspect = size.width / size.height;

    Rect targetRect;
    if (imageAspect > canvasAspect) {
      // Image is wider than canvas aspect - fit to height and center horizontally
      final width = size.height * imageAspect;
      targetRect = Rect.fromLTWH(
        (size.width - width) / 2,
        0,
        width,
        size.height,
      );
    } else {
      // Image is taller than canvas aspect - fit to width and center vertically
      final height = size.width / imageAspect;
      targetRect = Rect.fromLTWH(
        0,
        (size.height - height) / 2,
        size.width,
        height,
      );
    }

    canvas.drawImageRect(image, srcRect, targetRect, Paint());
  }

  @override
  bool shouldRepaint(_ImagePainter oldDelegate) {
    return oldDelegate.image != image;
  }
}
