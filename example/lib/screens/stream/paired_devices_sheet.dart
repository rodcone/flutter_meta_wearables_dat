import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_meta_wearables_dat/flutter_meta_wearables_dat.dart';
import 'package:flutter_meta_wearables_dat_example/providers/stream_provider.dart';
import 'package:flutter_meta_wearables_dat_example/shared/widgets/sheet_handle_bar.dart';
import 'package:provider/provider.dart';

/// Bottom sheet listing the paired Meta wearables reported by
/// [MetaWearablesDat.getDevices].
///
/// Demonstrates the read-only device API: each pair's name + model, which one
/// is actively streaming ([WearableDevice.isStreamingDevice]) vs the
/// auto-selector's current pick ([WearableDevice.isActive]), and its
/// connection state. With two pairs of the same model this is how you tell
/// them apart and see which one you're streaming from.
class PairedDevicesSheet extends StatefulWidget {
  const PairedDevicesSheet({super.key});

  @override
  State<PairedDevicesSheet> createState() => _PairedDevicesSheetState();
}

class _PairedDevicesSheetState extends State<PairedDevicesSheet> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(context.read<StreamSessionProvider>().refreshDevices());
    });
  }

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: 0.85,
      widthFactor: 1,
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(left: 25, right: 25, bottom: 100),
        child: Consumer<StreamSessionProvider>(
          builder: (context, streamProvider, child) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SheetHandleBar(),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Paired devices',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Refresh',
                      onPressed: streamProvider.devicesLoading
                          ? null
                          : () {
                              unawaited(streamProvider.refreshDevices());
                            },
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Flexible(child: _buildBody(streamProvider)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildBody(StreamSessionProvider provider) {
    if (provider.devicesLoading && provider.devices.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (provider.devicesError != null && provider.devices.isEmpty) {
      return _MessageCard(
        icon: Icons.error_outline,
        color: Colors.redAccent,
        message: provider.devicesError!,
      );
    }
    if (provider.devices.isEmpty) {
      return const _MessageCard(
        icon: Icons.search_off,
        color: Colors.grey,
        message:
            'No paired glasses found. Make sure a pair is powered on and '
            'connected in the Meta AI app.',
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      itemCount: provider.devices.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) =>
          _DeviceTile(device: provider.devices[index]),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({required this.device});

  final WearableDevice device;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    device.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (device.isStreamingDevice)
                  const _Badge(label: 'Streaming', color: Colors.green)
                else if (device.isActive)
                  const _Badge(label: 'Selected', color: Colors.blueAccent),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _modelLabel(device.type),
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _Badge(
                  label: _linkLabel(device.linkState),
                  color: device.linkState == WearableLinkState.connected
                      ? Colors.green
                      : Colors.grey,
                  outlined: true,
                ),
                if (device.supportsDisplay) ...[
                  const SizedBox(width: 6),
                  const _Badge(
                    label: 'Display',
                    color: Colors.purple,
                    outlined: true,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'ID: ${device.id}',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
            if (device.firmwareInfo != null && device.firmwareInfo!.isNotEmpty)
              Text(
                'Firmware: ${device.firmwareInfo}',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.label,
    required this.color,
    this.outlined = false,
  });

  final String label;
  final Color color;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: outlined ? Colors.transparent : color.withOpacity(0.15),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.icon,
    required this.color,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}

String _modelLabel(WearableDeviceType type) => switch (type) {
  WearableDeviceType.rayBanMeta => 'Ray-Ban Meta',
  WearableDeviceType.oakleyMetaHSTN => 'Oakley Meta HSTN',
  WearableDeviceType.oakleyMetaVanguard => 'Oakley Meta Vanguard',
  WearableDeviceType.metaRayBanDisplay => 'Meta Ray-Ban Display',
  WearableDeviceType.rayBanMetaOptics => 'Ray-Ban Meta Optics',
  WearableDeviceType.unknown => 'Unknown model',
};

String _linkLabel(WearableLinkState state) => switch (state) {
  WearableLinkState.connected => 'Connected',
  WearableLinkState.connecting => 'Connecting',
  WearableLinkState.disconnected => 'Disconnected',
  WearableLinkState.unknown => 'Unknown',
};
