import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_meta_wearables_dat/flutter_meta_wearables_dat.dart';
import 'package:flutter_meta_wearables_dat_example/providers/device_provider.dart';
import 'package:flutter_meta_wearables_dat_example/providers/stream_provider.dart'
    as stream_providers;
import 'package:flutter_meta_wearables_dat_example/shared/widgets/sheet_handle_bar.dart';
import 'package:provider/provider.dart';

class SettingsSheet extends StatelessWidget {
  const SettingsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final sheetHeight =
        MediaQuery.of(context).size.height * 0.9 -
        MediaQuery.of(context).padding.bottom;

    return SizedBox(
      height: sheetHeight,
      child: Padding(
        padding: const EdgeInsets.only(left: 25, right: 25),
        child: Column(
          children: [
            const SheetHandleBar(),
            const SizedBox(height: 8),
            Text(
              'Settings',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 18),
            const _StreamSettingsSection(),
            const SizedBox(height: 24),
            _DisconnectSection(),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
          ],
        ),
      ),
    );
  }
}

class _StreamSettingsSection extends StatelessWidget {
  const _StreamSettingsSection();

  @override
  Widget build(BuildContext context) {
    return Consumer<stream_providers.StreamSessionProvider>(
      builder: (context, sp, _) {
        final locked = sp.isStreaming;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionTitle(title: 'Stream', icon: Icons.videocam_outlined),
            const SizedBox(height: 16),
            _FpsSlider(
              fps: sp.fps,
              onChanged: locked ? null : sp.setFps,
            ),
            const SizedBox(height: 8),
            _ResolutionPicker(
              quality: sp.streamQuality,
              onChanged: locked ? null : sp.setStreamQuality,
            ),
            const SizedBox(height: 8),
            _CodecSelector(
              videoCodec: sp.videoCodec,
              hvc1Supported: sp.supportsHvc1,
              onCodecChanged: sp.setVideoCodec,
              enabled: !locked,
            ),
            const SizedBox(height: 16),
            _BackgroundStreamingToggle(
              value: sp.backgroundStreamingEnabled,
              onChanged: sp.setBackgroundStreamingEnabled,
            ),
          ],
        );
      },
    );
  }
}

class _BackgroundStreamingToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _BackgroundStreamingToggle({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Icon(
            Icons.smartphone,
            size: 18,
            color: theme.colorScheme.onSurface.withOpacity(0.65),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Keep streaming in background',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: theme.colorScheme.onSurface.withOpacity(0.85),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Stream stays alive when the app is backgrounded or the phone is locked.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.55),
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: (v) {
              HapticFeedback.selectionClick();
              onChanged(v);
            },
          ),
        ],
      ),
    );
  }
}

class _FpsSlider extends StatelessWidget {
  final double fps;
  final ValueChanged<double>? onChanged;

  const _FpsSlider({required this.fps, this.onChanged});

  static const List<double> _stops = [2, 7, 15, 24, 30];

  int _closestIndex() {
    var best = 0;
    var bestDiff = (fps - _stops[0]).abs();
    for (var i = 1; i < _stops.length; i++) {
      final diff = (fps - _stops[i]).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        best = i;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    final theme = Theme.of(context);
    final idx = _closestIndex();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SettingLabel(
          label: 'Frame rate',
          value: '${_stops[idx].toInt()} fps',
          enabled: enabled,
        ),
        const SizedBox(height: 4),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
            tickMarkShape: const RoundSliderTickMarkShape(tickMarkRadius: 3),
            activeTrackColor: enabled
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurface.withOpacity(0.12),
            inactiveTrackColor: theme.colorScheme.onSurface.withOpacity(0.08),
            thumbColor: enabled
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurface.withOpacity(0.3),
            activeTickMarkColor: theme.colorScheme.onPrimary,
            inactiveTickMarkColor: theme.colorScheme.onSurface.withOpacity(0.2),
          ),
          child: Slider(
            value: idx.toDouble(),
            max: (_stops.length - 1).toDouble(),
            divisions: _stops.length - 1,
            onChanged: enabled
                ? (v) {
                    HapticFeedback.selectionClick();
                    onChanged!(_stops[v.round()]);
                  }
                : null,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: _stops.map((s) {
              final isSelected = s == _stops[idx];
              return Text(
                '${s.toInt()}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: enabled
                      ? (isSelected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface.withOpacity(0.45))
                      : theme.colorScheme.onSurface.withOpacity(0.25),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _ResolutionPicker extends StatelessWidget {
  final StreamQuality quality;
  final ValueChanged<StreamQuality>? onChanged;

  const _ResolutionPicker({required this.quality, this.onChanged});

  static const List<(StreamQuality, String, String)> _options = [
    (StreamQuality.low, 'Low', '360 \u00d7 640'),
    (StreamQuality.medium, 'Med', '504 \u00d7 896'),
    (StreamQuality.high, 'High', '720 \u00d7 1280'),
  ];

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SettingLabel(
          label: 'Resolution',
          value: _options.firstWhere((o) => o.$1 == quality).$3,
          enabled: enabled,
        ),
        const SizedBox(height: 8),
        Row(
          children: _options.map((opt) {
            final selected = opt.$1 == quality;
            final isLast = opt == _options.last;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: isLast ? 0 : 8),
                child: _ResolutionChip(
                  label: opt.$2,
                  subtitle: opt.$3,
                  selected: selected,
                  enabled: enabled,
                  onTap: enabled ? () => onChanged!(opt.$1) : null,
                  theme: theme,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _ResolutionChip extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;
  final ThemeData theme;

  const _ResolutionChip({
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.enabled,
    required this.theme,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = !enabled
        ? theme.colorScheme.onSurface.withOpacity(0.3)
        : selected
            ? theme.colorScheme.onPrimary
            : theme.colorScheme.onSurface.withOpacity(0.7);

    return Material(
      color: !enabled
          ? theme.colorScheme.onSurface.withOpacity(0.04)
          : selected
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurface.withOpacity(0.06),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 10,
                  color: fg.withOpacity(0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CodecSelector extends StatelessWidget {
  final VideoCodec videoCodec;
  final bool hvc1Supported;
  final ValueChanged<VideoCodec> onCodecChanged;
  final bool enabled;

  const _CodecSelector({
    required this.videoCodec,
    required this.hvc1Supported,
    required this.onCodecChanged,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SettingLabel(
          label: 'Video codec',
          value: videoCodec == VideoCodec.hvc1
              ? 'HEVC — background'
              : 'Raw — foreground',
          enabled: enabled,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _CodecChip(
              label: 'RAW',
              selected: videoCodec == VideoCodec.raw,
              onTap: enabled ? () => onCodecChanged(VideoCodec.raw) : null,
            ),
            const SizedBox(width: 8),
            _CodecChip(
              label: 'HVC1 ${hvc1Supported ? '' : '(iOS only)'}',
              selected: videoCodec == VideoCodec.hvc1,
              enabled: hvc1Supported && enabled,
              tooltip: hvc1Supported
                  ? 'HEVC (iOS only)'
                  : 'HVC1 is unavailable on Android',
              onTap: (hvc1Supported && enabled)
                  ? () => onCodecChanged(VideoCodec.hvc1)
                  : null,
            ),
          ],
        ),
      ],
    );
  }
}

class _CodecChip extends StatelessWidget {
  final String label;
  final bool selected;
  final bool enabled;
  final String? tooltip;
  final VoidCallback? onTap;

  const _CodecChip({
    required this.label,
    required this.selected,
    this.enabled = true,
    this.tooltip,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final chip = FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: () {
        final cb = onTap;
        return cb != null ? (bool _) => cb() : null;
      }(),
      showCheckmark: false,
    );
    final t = tooltip;
    return t != null ? Tooltip(message: t, child: chip) : chip;
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final IconData icon;

  const _SectionTitle({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color:
                    Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
              ),
        ),
      ],
    );
  }
}

class _SettingLabel extends StatelessWidget {
  final String label;
  final String value;
  final bool enabled;

  const _SettingLabel({
    required this.label,
    required this.value,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final opacity = enabled ? 1.0 : 0.45;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
              color: theme.colorScheme.onSurface.withOpacity(0.65 * opacity),
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              color: theme.colorScheme.onSurface.withOpacity(0.5 * opacity),
            ),
          ),
        ],
      ),
    );
  }
}

class _DisconnectSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<DeviceProvider>(
      builder: (context, deviceProvider, _) {
        if (!deviceProvider.isRegistered) return const SizedBox.shrink();
        return SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () {
              HapticFeedback.lightImpact();
              unawaited(deviceProvider.disconnect());
              if (context.mounted) Navigator.of(context).pop();
            },
            icon: const Icon(Icons.link_off, size: 18),
            label: const Text('Disconnect glasses'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red.shade700,
              side: BorderSide(color: Colors.red.shade400),
            ),
          ),
        );
      },
    );
  }
}
