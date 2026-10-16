import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_meta_wearables_dat_example/providers/diagnostics_controller.dart';
import 'package:flutter_meta_wearables_dat_example/providers/stream_provider.dart';
import 'package:provider/provider.dart';

class DiagnosticsSheet extends StatefulWidget {
  const DiagnosticsSheet({super.key});

  @override
  State<DiagnosticsSheet> createState() => _DiagnosticsSheetState();
}

class _DiagnosticsSheetState extends State<DiagnosticsSheet> {
  RecoveryExperimentDelay _delay = RecoveryExperimentDelay.immediate;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => DiagnosticsController(),
    child: Consumer2<DiagnosticsController, StreamSessionProvider>(
      builder: (context, controller, stream, _) {
        final snapshot = controller.snapshot;
        final failure = stream.lastFailureDiagnostics;
        final report = const JsonEncoder.withIndent('  ').convert({
          'current': snapshot?.toMap(),
          'lastFrameStall': failure?.toMap(),
        });
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .75,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Stream diagnostics',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Copy diagnostics',
                        onPressed: snapshot == null && failure == null
                            ? null
                            : () async {
                                await Clipboard.setData(
                                  ClipboardData(text: report),
                                );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Diagnostics copied'),
                                    ),
                                  );
                                }
                              },
                        icon: const Icon(Icons.copy),
                      ),
                    ],
                  ),
                  const Text(
                    'Updates once per second while this panel is open. '
                    'Submitted frames are not a measurement of displayed frames.',
                  ),
                  const SizedBox(height: 12),
                  if (StreamSessionProvider.recoveryExperimentEnabled) ...[
                    Row(
                      children: [
                        const Text('Wait after cleanup: '),
                        DropdownButton<RecoveryExperimentDelay>(
                          value: _delay,
                          items: const [
                            DropdownMenuItem(
                              value: RecoveryExperimentDelay.immediate,
                              child: Text('0 seconds'),
                            ),
                            DropdownMenuItem(
                              value: RecoveryExperimentDelay.twoSeconds,
                              child: Text('2 seconds'),
                            ),
                          ],
                          onChanged: stream.recoveryExperimentToken == null
                              ? null
                              : (value) {
                                  if (value != null) {
                                    setState(() => _delay = value);
                                  }
                                },
                        ),
                      ],
                    ),
                    OutlinedButton(
                      onPressed: stream.recoveryExperimentToken == null
                          ? null
                          : () async {
                              final token = stream.recoveryExperimentToken;
                              final delay = _delay;
                              final route = ModalRoute.of(context);
                              if (token == null || route == null) return;
                              Navigator.of(context).pop();
                              // Wait for disposal and polling shutdown, not
                              // merely the start of the dismissal animation.
                              await route.completed;
                              stream.triggerRecoveryExperiment(
                                token,
                                delay: delay,
                              );
                            },
                      child: const Text(
                        'Investigation: synthetic foreground recovery (once)',
                      ),
                    ),
                  ],
                  if (controller.error != null) Text(controller.error!),
                  if (snapshot != null) ...[
                    Text(
                      'SDK: ${snapshot.receivedFps?.toStringAsFixed(1) ?? "—"} fps · '
                      'Texture: ${snapshot.submittedFps?.toStringAsFixed(1) ?? "—"} fps',
                    ),
                    Text(
                      'State: ${snapshot.sessionState.name} · '
                      'Stall: ${snapshot.stallReason?.name ?? "none"}',
                    ),
                  ],
                  const SizedBox(height: 12),
                  const Text(
                    'Report includes the latest frame-stall snapshot, even after recovery.',
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: SingleChildScrollView(
                      child: SelectableText(
                        report,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}
