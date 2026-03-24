import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_meta_wearables_dat_example/providers/mock_device_provider.dart';
import 'package:flutter_meta_wearables_dat_example/providers/stream_provider.dart'
    as stream_providers;
import 'package:flutter_meta_wearables_dat_example/shared/widgets/meta_button.dart';
import 'package:flutter_meta_wearables_dat_example/shared/widgets/sheet_handle_bar.dart';
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
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SheetHandleBar(),
                Card(
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
                            if (mockDeviceProvider.deviceUUID != null)
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
                          'This screen handles simulating devices, mocking capabilities, and states.',
                          style: Theme.of(
                            context,
                          ).textTheme.bodyMedium!.copyWith(color: Colors.grey),
                        ),
                        const Divider(),
                        MetaButton.text(
                          enabled: mockDeviceProvider.deviceUUID == null,
                          text: 'Pair RayBan Meta',
                          onPressed: () {
                            context
                                .read<MockDeviceProvider>()
                                .pairMockRayBanMeta();
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                if (mockDeviceProvider.deviceUUID != null) ...[
                  SizedBox(
                    height: 500,
                    child: Card(
                      color: Colors.white,
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'RayBan Meta Glasses',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleMedium,
                                      ),
                                      Text(
                                        '${mockDeviceProvider.deviceUUID}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall!
                                            .copyWith(color: Colors.grey),
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(
                                  width: 120,
                                  child: MetaButton.text(
                                    text: 'Unpair',
                                    onPressed: () {
                                      context
                                          .read<MockDeviceProvider>()
                                          .unpairMockRayBanMeta();
                                    },
                                    color: Colors.red,
                                  ),
                                ),
                              ],
                            ),
                            const Divider(),
                            ListView(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: MetaButton.text(
                                        text: 'Power On',
                                        onPressed: () {
                                          context
                                              .read<MockDeviceProvider>()
                                              .powerOn();
                                        },
                                      ),
                                    ),
                                    Expanded(
                                      child: MetaButton.text(
                                        text: 'Power Off',
                                        onPressed: () {
                                          context
                                              .read<MockDeviceProvider>()
                                              .powerOff();
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                                Row(
                                  children: [
                                    Expanded(
                                      child: MetaButton.text(
                                        text: 'Don',
                                        onPressed: () {
                                          context
                                              .read<MockDeviceProvider>()
                                              .don();
                                        },
                                      ),
                                    ),
                                    Expanded(
                                      child: MetaButton.text(
                                        text: 'Doff',
                                        onPressed: () {
                                          context
                                              .read<MockDeviceProvider>()
                                              .doff();
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                                Row(
                                  children: [
                                    Expanded(
                                      child: MetaButton.text(
                                        text: 'Select video',
                                        onPressed: () async {
                                          try {
                                            context
                                                .read<
                                                  stream_providers.StreamSessionProvider
                                                >()
                                                .setIsLoadingVideo(true);

                                            // Use file_picker instead of image_picker to preserve HEVC format
                                            final result = await FilePicker
                                                .platform
                                                .pickFiles(
                                                  type: FileType.video,
                                                  allowCompression: false,
                                                );

                                            if (!context.mounted) return;

                                            if (result != null &&
                                                result.files.single.path !=
                                                    null) {
                                              context
                                                  .read<
                                                    stream_providers.StreamSessionProvider
                                                  >()
                                                  .setSelectedVideo(
                                                    result.files.single.path,
                                                  );
                                            } else {
                                              context
                                                  .read<
                                                    stream_providers.StreamSessionProvider
                                                  >()
                                                  .setSelectedVideo(null);
                                            }
                                          } catch (e) {
                                            debugPrint(
                                              '[MetaWearablesDAT]Error picking video: $e',
                                            );
                                            context
                                                .read<
                                                  stream_providers.StreamSessionProvider
                                                >()
                                                .setSelectedVideo(null);
                                          } finally {
                                            if (context.mounted) {
                                              context
                                                  .read<
                                                    stream_providers.StreamSessionProvider
                                                  >()
                                                  .setIsLoadingVideo(false);
                                            }
                                          }
                                        },
                                      ),
                                    ),
                                    Expanded(
                                      child: Center(
                                        child: streamProvider.isLoadingVideo
                                            ? const SizedBox(
                                                height: 24,
                                                width: 24,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              )
                                            : (streamProvider.selectedVideo ==
                                                      null
                                                  ? Text(
                                                      'No video selected',
                                                      style: Theme.of(
                                                        context,
                                                      ).textTheme.bodyLarge,
                                                    )
                                                  : Text(
                                                      'Has camera feed',
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .bodyLarge!
                                                          .copyWith(
                                                            color: Colors.green,
                                                          ),
                                                    )),
                                      ),
                                    ),
                                  ],
                                ),
                                Row(
                                  children: [
                                    Expanded(
                                      child: MetaButton.text(
                                        text: 'Select image',
                                        onPressed: () async {
                                          try {
                                            final picker = ImagePicker();
                                            context
                                                .read<
                                                  stream_providers.StreamSessionProvider
                                                >()
                                                .setIsLoadingImage(true);
                                            final picked = await picker
                                                .pickImage(
                                                  source: ImageSource.gallery,
                                                );
                                            if (!context.mounted) return;
                                            context
                                                .read<
                                                  stream_providers.StreamSessionProvider
                                                >()
                                                .setSelectedImage(picked?.path);
                                          } catch (e) {
                                            context
                                                .read<
                                                  stream_providers.StreamSessionProvider
                                                >()
                                                .setSelectedImage(null);
                                          } finally {
                                            if (context.mounted) {
                                              context
                                                  .read<
                                                    stream_providers.StreamSessionProvider
                                                  >()
                                                  .setIsLoadingImage(false);
                                            }
                                          }
                                        },
                                      ),
                                    ),
                                    Expanded(
                                      child: Center(
                                        child: streamProvider.isLoadingImage
                                            ? const SizedBox(
                                                height: 24,
                                                width: 24,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              )
                                            : (streamProvider.selectedImage ==
                                                      null
                                                  ? Text(
                                                      'No captured image',
                                                      style: Theme.of(
                                                        context,
                                                      ).textTheme.bodyLarge,
                                                    )
                                                  : Text(
                                                      'Has captured image',
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .bodyLarge!
                                                          .copyWith(
                                                            color: Colors.green,
                                                          ),
                                                    )),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
