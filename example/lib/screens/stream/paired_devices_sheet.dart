import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_meta_wearables_dat/flutter_meta_wearables_dat.dart';
import 'package:flutter_meta_wearables_dat_example/providers/stream_provider.dart';
import 'package:flutter_meta_wearables_dat_example/shared/widgets/sheet_handle_bar.dart';
import 'package:provider/provider.dart';

/// Bottom sheet listing the paired Meta wearables reported by
/// [MetaWearablesDat.getDevices].
///
/// Demonstrates the read-only device API: each pair's model + name, which one
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
    final sheetHeight =
        MediaQuery.of(context).size.height * 0.9 -
        MediaQuery.of(context).padding.bottom;

    return SizedBox(
      height: sheetHeight,
      child: Padding(
        padding: const EdgeInsets.only(left: 25, right: 25),
        child: Consumer<StreamSessionProvider>(
          builder: (context, sp, _) {
            return Column(
              children: [
                const SheetHandleBar(),
                const SizedBox(height: 8),
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Text(
                      'Paired glasses',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        tooltip: 'Refresh',
                        onPressed: sp.devicesLoading
                            ? null
                            : () => unawaited(sp.refreshDevices()),
                        icon: const Icon(Icons.refresh),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Expanded(child: _buildBody(context, sp)),
                SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, StreamSessionProvider provider) {
    final theme = Theme.of(context);
    if (provider.devicesLoading && provider.devices.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (provider.devicesError != null && provider.devices.isEmpty) {
      return _MessageView(
        icon: Icons.error_outline,
        color: Colors.redAccent,
        message: provider.devicesError!,
      );
    }
    if (provider.devices.isEmpty) {
      return _MessageView(
        icon: Icons.search_off,
        color: theme.colorScheme.onSurface.withOpacity(0.4),
        message:
            'No paired glasses found. Make sure a pair is powered on and '
            'connected in the Meta AI app.',
      );
    }
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: provider.devices.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index == 0) {
          return _AutomaticTile(
            selected: provider.selectedDeviceId == null,
            onTap: () => provider.selectDevice(null),
          );
        }
        final device = provider.devices[index - 1];
        return _DeviceTile(
          device: device,
          isSelected: provider.selectedDeviceId == device.id,
          isStreaming: provider.isStreaming,
          onTap: () => provider.selectDevice(device.id),
        );
      },
    );
  }
}

/// "Automatic" entry — clears the pin so the SDK auto-selects the active pair.
class _AutomaticTile extends StatelessWidget {
  const _AutomaticTile({required this.selected, required this.onTap});

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final primary = theme.colorScheme.primary;
    return Material(
      color: selected ? primary.withOpacity(0.08) : onSurface.withOpacity(0.04),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? primary : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.auto_mode,
                size: 20,
                color: onSurface.withOpacity(0.7),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Automatic',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: onSurface.withOpacity(0.9),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Let the SDK pick the active pair',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: onSurface.withOpacity(0.55),
                      ),
                    ),
                  ],
                ),
              ),
              if (selected) Icon(Icons.check_circle, color: primary, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.device,
    required this.isSelected,
    required this.isStreaming,
    required this.onTap,
  });

  final WearableDevice device;
  final bool isSelected;
  final bool isStreaming;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final primary = theme.colorScheme.primary;
    // The user picked this pair, but a different one is currently streaming.
    final needsRestartToSwitch =
        isSelected && isStreaming && !device.isStreamingDevice;
    return Material(
      color: isSelected
          ? primary.withOpacity(0.08)
          : onSurface.withOpacity(0.04),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? primary : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _modelLabel(device.type),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: onSurface.withOpacity(0.9),
                      ),
                    ),
                  ),
                  if (device.isStreamingDevice)
                    const _Badge(label: 'Streaming', color: Colors.green)
                  else if (isSelected)
                    _Badge(label: 'Will stream', color: primary)
                  else if (device.isActive)
                    _Badge(
                      label: 'Auto-pick',
                      color: onSurface.withOpacity(0.5),
                      outlined: true,
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                device.name,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: onSurface.withOpacity(0.55),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _Badge(
                    label: _linkLabel(device.linkState),
                    color: device.linkState == WearableLinkState.connected
                        ? Colors.green
                        : onSurface.withOpacity(0.45),
                    outlined: true,
                  ),
                  if (device.supportsDisplay) ...[
                    const SizedBox(width: 6),
                    _Badge(label: 'Display', color: primary, outlined: true),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'ID: ${device.id}',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: onSurface.withOpacity(0.4),
                ),
              ),
              if (device.firmwareInfo != null &&
                  device.firmwareInfo!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    'Firmware: ${device.firmwareInfo}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: onSurface.withOpacity(0.4),
                    ),
                  ),
                ),
              if (needsRestartToSwitch)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Stop streaming, then Start to switch to this pair.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: primary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
            ],
          ),
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
        borderRadius: BorderRadius.circular(8),
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

class _MessageView extends StatelessWidget {
  const _MessageView({
    required this.icon,
    required this.color,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 40),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
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
  WearableDeviceType.metaGlasses => 'Meta Glasses',
  WearableDeviceType.unknown => 'Unknown model',
};

String _linkLabel(WearableLinkState state) => switch (state) {
  WearableLinkState.connected => 'Connected',
  WearableLinkState.connecting => 'Connecting',
  WearableLinkState.disconnected => 'Disconnected',
  WearableLinkState.unknown => 'Unknown',
};
