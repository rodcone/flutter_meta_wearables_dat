import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_meta_wearables_dat_example/providers/mock_device_provider.dart';
import 'package:flutter_meta_wearables_dat_example/providers/stream_provider.dart'
    as stream_providers;
import 'package:flutter_meta_wearables_dat_example/shared/widgets/meta_button.dart';
import 'package:flutter_meta_wearables_dat_example/shared/widgets/sheet_handle_bar.dart';
import 'package:flutter_meta_wearables_dat_mock_device/flutter_meta_wearables_dat_mock_device.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

class MockDeviceSheet extends StatelessWidget {
  const MockDeviceSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: 0.85,
      widthFactor: 1,
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(left: 25, right: 25, bottom: 100),
        child: Consumer2<MockDeviceProvider, stream_providers.StreamSessionProvider>(
          builder: (context, mockDeviceProvider, streamProvider, child) {
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SheetHandleBar(),
                  _PairingCard(mockDeviceProvider: mockDeviceProvider),
                  if (mockDeviceProvider.deviceUUID != null)
                    _DeviceControlsCard(
                      mockDeviceProvider: mockDeviceProvider,
                      streamProvider: streamProvider,
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PairingCard extends StatelessWidget {
  const _PairingCard({required this.mockDeviceProvider});

  final MockDeviceProvider mockDeviceProvider;

  @override
  Widget build(BuildContext context) {
    final paired = mockDeviceProvider.deviceUUID != null;
    return Card(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Mock Device Kit',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                if (paired)
                  Text(
                    'Device paired',
                    style: Theme.of(context).textTheme.bodyMedium!
                        .copyWith(color: Colors.green),
                  )
                else
                  const Text('No device paired'),
              ],
            ),
            Text(
              'Only one mock device can be active at a time. Pair to unlock '
              'the device controls below.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium!.copyWith(color: Colors.grey),
            ),
            const Divider(),
            MetaButton.text(
              enabled: !paired,
              text: 'Pair RayBan Meta',
              onPressed: () {
                context.read<MockDeviceProvider>().pairMockRayBanMeta();
              },
            ),
          ],
        ),
      ),
    );
  }
}

enum _FeedMode { liveCamera, media }

class _DeviceControlsCard extends StatefulWidget {
  const _DeviceControlsCard({
    required this.mockDeviceProvider,
    required this.streamProvider,
  });

  final MockDeviceProvider mockDeviceProvider;
  final stream_providers.StreamSessionProvider streamProvider;

  @override
  State<_DeviceControlsCard> createState() => _DeviceControlsCardState();
}

class _DeviceControlsCardState extends State<_DeviceControlsCard> {
  // Feed mode is a UI concept — the user picks one of two mutually
  // exclusive ways to drive the mock feed: a physical camera facing, or a
  // media file. The underlying provider state (cameraFacing / selectedVideo
  // / selectedImage) is cleared on each switch so the startStreamSession
  // logic applies exactly one input.
  _FeedMode _mode = _FeedMode.liveCamera;

  @override
  void initState() {
    super.initState();
    final stream = widget.streamProvider;
    final mock = widget.mockDeviceProvider;
    if (stream.selectedVideo != null || stream.selectedImage != null) {
      _mode = _FeedMode.media;
    } else if (mock.cameraFacing != null) {
      _mode = _FeedMode.liveCamera;
    }
  }

  void _switchMode(_FeedMode next) {
    if (_mode == next) return;
    final stream = context.read<stream_providers.StreamSessionProvider>();
    final mock = context.read<MockDeviceProvider>();
    if (next == _FeedMode.liveCamera) {
      // Drop any media selections so the live camera is the sole feed driver.
      stream
        ..setSelectedVideo(null)
        ..setSelectedImage(null);
    } else {
      mock.clearCameraFacing();
    }
    setState(() => _mode = next);
  }

  @override
  Widget build(BuildContext context) {
    final mockDeviceProvider = widget.mockDeviceProvider;
    final streamProvider = widget.streamProvider;
    final isPoweredOn = mockDeviceProvider.isPoweredOn;

    return Card(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'RayBan Meta Glasses',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        '${mockDeviceProvider.deviceUUID}',
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall!.copyWith(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 100,
                  child: MetaButton.secondary(
                    text: 'Unpair',
                    color: Colors.red,
                    onPressed: () async {
                      final mock = context.read<MockDeviceProvider>();
                      final stream = context
                          .read<stream_providers.StreamSessionProvider>();
                      // Stop the session before unpairing: tearing down the
                      // mock device with a live session races the SDK's
                      // RemoteSessionService on a DataX IO thread and
                      // crashes with ProtocolException(INTERNAL_ERROR).
                      if (stream.isStreaming) {
                        await stream.stopStreamSession();
                      }
                      if (mock.isPoweredOn) {
                        await mock.powerOff();
                      }
                      await mock.unpairMockRayBanMeta();
                    },
                  ),
                ),
              ],
            ),
            const Divider(),
            Text(
              'Lifecycle',
              style: Theme.of(context).textTheme.labelSmall!.copyWith(
                color: Colors.grey,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: MetaButton.secondary(
                    text: isPoweredOn ? 'Powered on' : 'Power on',
                    color: isPoweredOn ? Colors.green : null,
                    enabled: !isPoweredOn,
                    onPressed: () {
                      context.read<MockDeviceProvider>().powerOn();
                    },
                  ),
                ),
                Expanded(
                  child: MetaButton.secondary(
                    text: 'Power off',
                    enabled: isPoweredOn,
                    onPressed: () {
                      context.read<MockDeviceProvider>().powerOff();
                    },
                  ),
                ),
              ],
            ),
            if (isPoweredOn) ...[
              const SizedBox(height: 12),
              Text(
                'Camera feed',
                style: Theme.of(context).textTheme.labelSmall!.copyWith(
                  color: Colors.grey,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 4),
              _FeedModeSelector(mode: _mode, onChanged: _switchMode),
              const SizedBox(height: 8),
              if (_mode == _FeedMode.liveCamera)
                _CameraFacingRow(
                  mockDeviceProvider: mockDeviceProvider,
                  enabled: true,
                )
              else ...[
                _VideoPickerRow(streamProvider: streamProvider, enabled: true),
                _ImagePickerRow(streamProvider: streamProvider, enabled: true),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _FeedModeSelector extends StatelessWidget {
  const _FeedModeSelector({required this.mode, required this.onChanged});

  final _FeedMode mode;
  final ValueChanged<_FeedMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: MetaButton.secondary(
            text: 'Live camera',
            color: mode == _FeedMode.liveCamera ? Colors.green : null,
            onPressed: () => onChanged(_FeedMode.liveCamera),
          ),
        ),
        Expanded(
          child: MetaButton.secondary(
            text: 'Media',
            color: mode == _FeedMode.media ? Colors.green : null,
            onPressed: () => onChanged(_FeedMode.media),
          ),
        ),
      ],
    );
  }
}

class _CameraFacingRow extends StatelessWidget {
  const _CameraFacingRow({
    required this.mockDeviceProvider,
    required this.enabled,
  });

  final MockDeviceProvider mockDeviceProvider;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final selected = mockDeviceProvider.cameraFacing;
    return Row(
      children: [
        Expanded(
          child: MetaButton.secondary(
            text: 'Front camera',
            enabled: enabled,
            color: selected == CameraFacing.front ? Colors.green : null,
            onPressed: () {
              context
                  .read<MockDeviceProvider>()
                  .setCameraFacing(CameraFacing.front);
            },
          ),
        ),
        Expanded(
          child: MetaButton.secondary(
            text: 'Back camera',
            enabled: enabled,
            color: selected == CameraFacing.back ? Colors.green : null,
            onPressed: () {
              context
                  .read<MockDeviceProvider>()
                  .setCameraFacing(CameraFacing.back);
            },
          ),
        ),
      ],
    );
  }
}

class _VideoPickerRow extends StatelessWidget {
  const _VideoPickerRow({required this.streamProvider, required this.enabled});

  final stream_providers.StreamSessionProvider streamProvider;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: MetaButton.secondary(
            text: 'Select video',
            enabled: enabled,
            onPressed: () async {
              final provider = context
                  .read<stream_providers.StreamSessionProvider>();
              try {
                provider.setIsLoadingVideo(true);

                // Use file_picker instead of image_picker to preserve HEVC format
                final result = await FilePicker.platform.pickFiles(
                  type: FileType.video,
                  allowCompression: false,
                );

                if (!context.mounted) return;

                if (result != null && result.files.single.path != null) {
                  provider.setSelectedVideo(result.files.single.path);
                } else {
                  provider.setSelectedVideo(null);
                }
              } catch (e) {
                debugPrint('[MetaWearablesDAT]Error picking video: $e');
                provider.setSelectedVideo(null);
              } finally {
                if (context.mounted) {
                  provider.setIsLoadingVideo(false);
                }
              }
            },
          ),
        ),
        Expanded(
          child: Center(
            child: streamProvider.isLoadingVideo
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : streamProvider.selectedVideo == null
                ? Text(
                    'No video selected',
                    style: Theme.of(context).textTheme.bodySmall,
                  )
                : Text(
                    'Has camera feed',
                    style: Theme.of(context).textTheme.bodySmall!.copyWith(
                      color: Colors.green,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _ImagePickerRow extends StatelessWidget {
  const _ImagePickerRow({required this.streamProvider, required this.enabled});

  final stream_providers.StreamSessionProvider streamProvider;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: MetaButton.secondary(
            text: 'Select image',
            enabled: enabled,
            onPressed: () async {
              final provider = context
                  .read<stream_providers.StreamSessionProvider>();
              try {
                final picker = ImagePicker();
                provider.setIsLoadingImage(true);
                final picked = await picker.pickImage(
                  source: ImageSource.gallery,
                );
                if (!context.mounted) return;
                provider.setSelectedImage(picked?.path);
              } catch (e) {
                provider.setSelectedImage(null);
              } finally {
                if (context.mounted) {
                  provider.setIsLoadingImage(false);
                }
              }
            },
          ),
        ),
        Expanded(
          child: Center(
            child: streamProvider.isLoadingImage
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : streamProvider.selectedImage == null
                ? Text(
                    'No captured image',
                    style: Theme.of(context).textTheme.bodySmall,
                  )
                : Text(
                    'Has captured image',
                    style: Theme.of(context).textTheme.bodySmall!.copyWith(
                      color: Colors.green,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}
