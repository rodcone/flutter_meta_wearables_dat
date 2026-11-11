import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_meta_wearables_dat/flutter_meta_wearables_dat.dart';
import 'package:flutter_meta_wearables_dat_example/providers/motion_provider.dart';
import 'package:flutter_meta_wearables_dat_example/shared/widgets/sheet_handle_bar.dart';
import 'package:provider/provider.dart';

/// Motion remains active when this sheet closes so camera and Motion can coexist.
class MotionSheet extends StatelessWidget {
  const MotionSheet({this.deviceId, super.key});

  final String? deviceId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.9,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 25),
        child: Column(
          children: [
            const SheetHandleBar(),
            Text(
              'Motion',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Consumer<MotionProvider>(
                builder: (context, motion, _) {
                  final sample = motion.latestSample;
                  return ListView(
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.paddingOf(context).bottom + 24,
                    ),
                    children: [
                      const Text(
                        'Beta · Development and beta release channels only. '
                        'Motion works with the camera off and needs no camera '
                        'or microphone permission.',
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<MotionSamplingRate>(
                        initialValue: motion.samplingRate,
                        decoration: const InputDecoration(
                          labelText: 'Sampling rate',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final rate in MotionSamplingRate.values)
                            DropdownMenuItem(
                              value: rate,
                              child: Text('${rate.value} Hz'),
                            ),
                        ],
                        onChanged: motion.isActive || motion.commandPending
                            ? null
                            : (rate) {
                                if (rate != null) motion.setSamplingRate(rate);
                              },
                      ),
                      const SizedBox(height: 12),
                      Text('State: ${motion.state.code}'),
                      Text('Samples received: ${motion.sampleCount}'),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: motion.commandPending
                            ? null
                            : () {
                                if (motion.isActive) {
                                  unawaited(motion.stop());
                                } else {
                                  unawaited(motion.start(deviceId));
                                }
                              },
                        icon: Icon(
                          motion.isActive ? Icons.stop : Icons.play_arrow,
                        ),
                        label: Text(
                          motion.commandPending
                              ? 'Please wait…'
                              : motion.isActive
                              ? 'Stop Motion'
                              : 'Start Motion',
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Close this sheet to use the camera alongside Motion. '
                        'Stopping either one keeps the other running. '
                        'Stop Motion before changing its sampling rate.',
                      ),
                      if (motion.lastError case final error?) ...[
                        const SizedBox(height: 16),
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            '${error.code}: ${error.message}',
                            style: TextStyle(color: theme.colorScheme.error),
                          ),
                        ),
                      ],
                      const Divider(height: 32),
                      if (sample == null)
                        const Text('Waiting for a motion sample.')
                      else ...[
                        Text(
                          motion.state == MotionState.started
                              ? 'Latest sample'
                              : 'Last received sample',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text('Source: ${sample.source.code}'),
                        Text('Timestamp: ${sample.timestampNs} ns'),
                        _Reading(
                          label: 'Acceleration (m/s², includes gravity)',
                          value: _vector(sample.accelerometer),
                        ),
                        _Reading(
                          label: 'Angular velocity (rad/s)',
                          value: _vector(sample.gyroscope),
                        ),
                        _Reading(
                          label: 'Magnetic field (µT)',
                          value: _vector(sample.magnetometer),
                        ),
                        _Reading(
                          label: 'Orientation (quaternion)',
                          value: _quaternion(sample.orientation),
                        ),
                      ],
                      const SizedBox(height: 16),
                      const Text(
                        'Readings may be unavailable independently. Timestamps '
                        'come from the glasses’ monotonic clock. This display '
                        'updates at most 10 times per second; every incoming '
                        'sample is counted.',
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _vector(MotionVector3? value) => value == null
      ? 'Unavailable'
      : 'x ${value.x.toStringAsFixed(3)} · '
            'y ${value.y.toStringAsFixed(3)} · z ${value.z.toStringAsFixed(3)}';

  static String _quaternion(MotionQuaternion? value) => value == null
      ? 'Unavailable'
      : 'x ${value.x.toStringAsFixed(3)} · y ${value.y.toStringAsFixed(3)} · '
            'z ${value.z.toStringAsFixed(3)} · w ${value.w.toStringAsFixed(3)}';
}

class _Reading extends StatelessWidget {
  const _Reading({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(value),
      ],
    ),
  );
}
