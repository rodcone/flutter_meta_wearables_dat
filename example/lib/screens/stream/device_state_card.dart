import 'package:flutter/material.dart';
import 'package:flutter_meta_wearables_dat/flutter_meta_wearables_dat.dart';

/// The latest observed glasses state, independent of camera controls.
class DeviceStateCard extends StatelessWidget {
  const DeviceStateCard({super.key, required this.state, this.deviceName});

  final DeviceState? state;
  final String? deviceName;

  @override
  Widget build(BuildContext context) {
    final value = state;
    final battery = value?.batteryLevel;
    final connection = switch (value?.linkState) {
      WearableLinkState.connected => 'Connected',
      WearableLinkState.connecting => 'Connecting',
      WearableLinkState.disconnected => 'Disconnected',
      _ => 'Connection unknown',
    };
    final charging = switch (value?.chargingState) {
      WearableChargingState.charging => 'Charging',
      WearableChargingState.notCharging => 'Not charging',
      _ => 'Charging unknown',
    };
    final worn = switch (value?.donState) {
      WearableDonState.donned => 'Worn',
      WearableDonState.doffed => 'Removed',
      _ => 'Wear state unknown',
    };
    final hinge = switch (value?.hingeState) {
      WearableHingeState.open => 'Hinges open',
      WearableHingeState.closed => 'Hinges closed',
      _ => 'Hinges unknown',
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value?.deviceId == null
                ? 'Device state unavailable'
                : 'Monitored device: ${deviceName ?? value!.deviceId}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$connection · ${battery == null ? 'Battery unknown' : 'Battery $battery%'}'
            ' · $charging · $worn · $hinge',
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
          const SizedBox(height: 6),
          _ThermalChip(level: value?.thermalLevel),
        ],
      ),
    );
  }
}

class _ThermalChip extends StatelessWidget {
  final ThermalLevel? level;

  const _ThermalChip({required this.level});

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(level);
    final label = _labelFor(level);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.thermostat, color: Colors.white, size: 14),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _colorFor(ThermalLevel? level) {
    return switch (level) {
      null || ThermalLevel.unknown => Colors.blueGrey.shade700,
      ThermalLevel.none || ThermalLevel.light => Colors.green.shade700,
      ThermalLevel.moderate => Colors.amber.shade800,
      ThermalLevel.severe => Colors.orange.shade800,
      ThermalLevel.critical => Colors.red.shade700,
      ThermalLevel.emergency || ThermalLevel.shutdown => Colors.red.shade900,
    };
  }

  String _labelFor(ThermalLevel? level) {
    return switch (level) {
      null => 'Thermal: waiting…',
      ThermalLevel.unknown => 'Thermal: unknown',
      ThermalLevel.none => 'Thermal: normal',
      ThermalLevel.light => 'Warm',
      ThermalLevel.moderate => 'Warming',
      ThermalLevel.severe => 'Hot',
      ThermalLevel.critical => 'Critical',
      ThermalLevel.emergency => 'Emergency',
      ThermalLevel.shutdown => 'Shutdown',
    };
  }
}
