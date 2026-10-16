# Two-second foreground restart experiment

Prepared 2026-10-16. The maintainer subsequently selected implementation and
local validation only. Status: implemented; physical comparison remains pending.
This replaces the earlier stage-2 proposal comparing zero versus ten seconds.

## Question and current evidence

Does waiting two seconds **after cleanup completes** reduce failed replacement
starts under the same foreground conditions? The existing 400 ms recovery backoff
runs before cleanup and does not test this question.

On `b288676`, the October 16 trial had a 0.910 ms cleanup-to-start gap and the
replacement emitted `unexpectedError("Session ended by device")` 94.073 ms after
start. SDK snapshots reported connected, donned, hinges open and thermal none.
Three earlier synthetic trials passed and one failed. An earlier manual start
also failed after a gap over ten seconds: delay cannot be assumed sufficient.
The October 16 phone ran iOS 27.0.1 with added warning logging, unlike the previous
trials. Historical runs are context, not the control group for this comparison.

Two seconds follows the workaround discussed in Meta iOS issue 231, already linked
in the SDK-error investigation. It is an experimental value, not a confirmed fix,
SDK contract, or reason to match free-text errors or retry unexpectedError broadly.

## Proposed implementation

1. Add a zero/two-second selection beside the existing synthetic recovery action
   in the example diagnostics panel. Both MWDAT_INVESTIGATION and
   MWDAT_RECOVERY_EXPERIMENT must be true. Default to zero, use a closed set of
   supported values, and snapshot the selection when a valid trial is triggered.
   Close diagnostics before triggering as today. No public plugin API or native
   timing change; both conditions run in the same installed build.
2. In StreamProvider._runRecovery, after the shared teardown future completes and
   the generation guard passes, cancel the teardown deadline and enter a separate
   experimental waiting phase. For the two-second condition, await a cancellable
   timer; for zero, go straight to starting without an added asynchronous wait.
   Start the existing startup watchdog only immediately before replacement start.
   The waiting phase reports no startup/cleanup deadline. Preserve the existing
   pre-teardown backoff, native cleanup and attempt accounting in both conditions.
3. Keep the trial selection fixed for any subsequent recovery attempts belonging
   to that trial; do not increase existing retry budgets. The first executed attempt
   is the primary outcome; report subsequent attempts separately. A new manual
   start clears the trial context. Manual starts and natural errors outside a
   synthetic trial get no experimental delay, even in an investigation build.
4. Cancel and resolve the pending wait on Stop, disposal, terminal/nonrecoverable
   failure, invalidated recovery generation, background opt-out, or leaving resumed
   lifecycle. The last rule is investigation-only: this is a foreground experiment.
   Reject new manual/experimental starts while recovery/cleanup is active. Recheck
   generation, streaming intent and resumed lifecycle immediately before starting.
   Duplicate errors/states must not restart the timer, extend deadlines or consume
   another attempt. A late timer callback must never start a cancelled session.
5. Add trace events for wait begin/end/cancellation, requested delay, measured
   elapsed wait and trial identity. Preserve errorSource and native parent/camera
   identity. Use native cleanup-end-to-start timestamps for the primary actual-gap
   measurement; Dart elapsed wait is supplementary, never subtracted from native
   uptime. Delayed scheduling is reported as observed, not rounded to two seconds.

## Local validation before device use

Use existing example provider/widget-test conventions and fake time:

- All four compile-time flag combinations: controls and timing change exist only
  with both flags; normal/manual/natural recovery remains unchanged.
- A blocked teardown never starts the delay or a replacement. Once cleanup returns,
  two seconds must elapse before start; the zero condition adds no new wait.
- Teardown and startup deadlines retain their full independent budgets; neither
  counts the experimental wait. Duplicate callbacks cannot extend a wait/deadline.
- Stop, disposal, terminal error, generation invalidation, opt-out and lifecycle
  loss during the wait prevent late start. Cancellation releases pending work.
- A selection change cannot alter an active trial; repeated injections cannot
  overlap work. Trial reset and retry accounting follow the existing contract.
- Wait records distinguish completion from cancellation and carry the selected
  delay consistently. Existing genuine SDK error forwarding remains intact.

Run scoped Dart formatting/analysis, the existing recovery/experiment suites and
new widget/provider cases. Build signed normal and investigation iOS releases;
verify logging configuration and flag behavior. No device installation in this
implementation stage; report local results and stop for the next device step.

## Proposed physical comparison

Use one instrumented build, Bluetooth Classic, RAW/medium/30 FPS, background
streaming enabled, foreground/resumed throughout, and unchanged warning logging.
Record iOS, SDK, glasses firmware and Meta AI versions where available; record
unavailable metadata explicitly. Check connected/donned/open/compatible/thermal
state from the new native records and preserve SDK logs before and after.

Run at most four valid trials, **one explicitly selected trial at a time**:

| Trial | Added post-cleanup delay |
| --- | --- |
| 1 | 0 seconds |
| 2 | 2 seconds |
| 3 | 2 seconds |
| 4 | 0 seconds |

This reverses order in the second pair but does not eliminate device-history or
thermal effects. Do not run an automatic loop or repeatedly retry a failed baseline.

For each trial:

1. Verify capture preflight and clean sequence state. Explicitly stop/reset before
   establishing a fresh manual baseline; allow at least 30 seconds between trials,
   record the actual interval, and confirm readiness again. This spacing applies
   equally to both conditions and is not a proven glasses-state reset.
2. Establish at least 20 seconds of actual baseline frame delivery. If manual start
   fails, retain it as a baseline failure and stop the batch for review; do not
   count it as a synthetic trial or keep restarting until it succeeds.
3. Choose the condition, trigger once and leave controls untouched. Check actual
   native cleanup completion and replacement start, SDK state/error/link/wear
   events, new camera/texture identity, and first-frame arrival.
4. Pass only if the first replacement delivers frames continuously for at least
   20 seconds after its first frame, with no persistent stall, terminal error or
   extra recovery. State=streaming or a new texture alone is insufficient.
   A startup rejection/no frame is failure. Incomplete capture, changed lifecycle,
   removal, lost connection or thermal change makes the comparison confounded;
   preserve the observation without attributing its cause to the delay.
5. Stop on any unexpected persistent device state or missing capture. A failure
   requires review before the next trial; it does not authorize more attempts.
   After each selected trial restore the normal build, background streaming off
   and Agent Access off, unless the maintainer explicitly selects continuing the
   same batch. Rebuild the identical instrumented commit for the next trial.

## Decision rules

- Delayed passes and immediate failures suggest a timing effect under these
  conditions; four trials cannot establish reliability or a production fix.
- Both conditions passing is inconclusive because the failure is intermittent.
- Both failing, mixed delayed outcomes, or a confounded pair: preserve evidence
  and consider a minimal native reproduction/upstream report rather than lengthen
  the delay or retry budget without another plan.
- Any production change needs separate approval, repeat evidence and natural
  background/normal-release validation. This synthetic experiment does not resolve
  the original locked-phone streaming issue on its own.

## Implementation and local validation (2026-10-16)

The example diagnostics selector now offers 0 or 2 seconds only when both
investigation defines are enabled. The chosen delay is fixed for the active
synthetic recovery, including replacement retries. Completed trials do not delay
later natural recoveries; a fresh manual start resets the selection context.

The wait has its own cancellable phase after cleanup, outside both deadlines.
A temporary error subscription catches terminal/nonrecoverable errors while the
normal session listeners are detached. Lifecycle loss, Stop, disposal and
background opt-out cancel pending work. Trace events are
`recoveryExperimentWaitStarted`, `recoveryExperimentWaitCompleted` and
`recoveryExperimentWaitCancelled`; completed/cancelled records include
`actualWaitUs`. `selectedPostCleanupDelayMs` retains the trial choice while
`postCleanupDelayMs` is zero outside the active synthetic recovery.

Local automated checks:

- Scoped formatting and analysis: clean. Dart MCP analysis had no configured
  roots, so the repository-pinned Flutter analyzer was used.
- Normal example suite: 73 tests passed.
- Recovery suite with investigation-only, experiment-only and both defines:
  52 tests passed in each configuration. Experiment-specific bodies run only
  when both defines are present; gate assertions run in every configuration.
- Coverage includes independent deadlines, delayed cleanup, duplicate callbacks,
  retry delay retention, cancellation, manual reset, modal dismissal and traces.
- Signed investigation and normal iOS release builds passed, including strict
  codesign verification. Investigation plist logging was `warning`; the final
  normal build contained no investigation Logging entry. Neither was installed.
- DTD discovery found no running debug app to reload.

No device installation, launch, streaming or settings changes were performed.
These checks establish local behavior, not whether the delay fixes the SDK fault.


## Physical control trial 1 — 2026-10-16, 12:57–13:00 Europe/Madrid

**PASS for the first zero-delay replacement.** Tested implementation `03e2b14`
with both investigation defines and SDK warning logging. One synthetic injection,
one executed recovery, no extra attempt. This does not demonstrate a delay effect
or resolve background reliability; the two-second condition has not been run.

Conditions: wired iPhone 17, iOS 27.0.1 (24A446), Bluetooth Classic,
RAW/medium/30 FPS, background streaming enabled, app foreground throughout.
The user confirmed unlocked, connected and worn before capture. Native snapshots
reported connected/donned/open/compatible/thermal none before and after replacement;
battery changed from 100 to 98 percent over the capture. Glasses firmware and
Meta AI version were not available in this capture. Diagnostics showed zero
seconds and closed before injection; no frame-byte subscription was added.

| Measurement | Result |
| --- | --- |
| Baseline observed after first frame, through last pre-trigger watchdog | 49.204 s, 1,321 frames, 24.5–27.5 FPS |
| Native stop-method cleanup | 130.292 ms |
| Cleanup operation end → replacement startRequested | 1.290 ms |
| Replacement startRequested → firstFrame | 2.441 s |
| Replacement first frame → last watchdog before manual Stop | 44.127 s, 1,163 frames, 24.5–26.5 FPS |
| Replacement attempts / genuine SDK errors / watchdog expiry | 1 / 0 / 0 |

Baseline camera `19C2BAD4-C8A4-4138-84E7-36E72E52A3B2`, texture 0;
replacement `B1098198-42F1-4F12-A0DA-DB1B2D49E818`, texture 1.
Trial `1792148348614716-1` recorded `postCleanupDelayMs: 0`; no experimental
wait event occurred. All watchdog snapshots were foreground and no background
transition was captured. Actual native arrivals, not just STREAMING state or
screen pixels, support the outcome. Frame counts/rates are sampled diagnostics,
not a claim that every scheduled frame arrived.

Capture: `/tmp/dat-zero-control-20261016/trial/records.jsonl` and `summary.json`.
Startup verified; native sequences 1–165, Dart 1–25 and bridge 1 were contiguous,
with no duplicates, rejected payloads, malformed records, truncation or ordering
errors. Collector ended intentionally (`operatorStopped`). Sequence validation
cannot exclude an unobserved trailing record. The collector retains tagged
structured traces, not the full untagged SDK console.

Restoration: manually stopped streaming and turned background streaming off;
rebuilt, signature-verified, installed and relaunched the normal release without
deleting app data. Its plist had no investigation Logging entry. Verified idle
Start UI and background toggle off. Restored iPhoneMirror Agent Access off and
verified its menu. No additional camera start, lock test, or delayed trial ran.


## Physical delayed trial 2 — 2026-10-16, 13:04–13:07 Europe/Madrid

**PASS for the first two-second replacement.** Same implementation `03e2b14`
(documentation-only HEAD `74de7e6`), both investigation flags, SDK warning logging,
Bluetooth Classic, RAW/medium/30 FPS and background streaming enabled. The user
confirmed ready with glasses worn/connected and phone unlocked. iPhoneMirror
reported iOS 27.0.1. Native snapshots stayed connected/donned/open/compatible and
thermal none; battery 97 → 95 percent. SDK remains the vendored DAT 1.0.0.
Glasses firmware and Meta AI version were unavailable in the captured metadata.

Previous trial's final cleanup end → this baseline start was approximately
292.830 seconds, using native uptime across captures. A fresh launch preceded the
baseline. This interval is not evidence of a reset of glasses state.

| Measurement | Result |
| --- | --- |
| Baseline first frame → last pre-trigger watchdog | 79.310 s, 2,101 frames |
| Native stop-method cleanup | 120.200 ms |
| Selected wait / Dart measured wait | 2,000 ms / 2,001.854 ms |
| Native cleanup operation end → replacement startRequested | 2,004.845 ms |
| Replacement startRequested → firstFrame | 2.468 s |
| Replacement first frame → last watchdog before manual Stop | 43.999 s, 1,168 frames, 23–26.5 FPS |
| Executed replacements / genuine SDK errors / watchdog expiry | 1 / 0 / 0 |

Trial `1792148777561738-1` emitted one wait-start and one wait-completed event,
with no startup deadline during the wait. Baseline camera
`4E3DEFBC-BC48-443F-9B1A-3A6EA9399F1C`, texture 0; replacement
`7FCA1FB2-975E-43B4-B20F-57F5546975C4`, texture 1. All recorded lifecycle states
were foreground/resumed. No persistent stall or additional recovery occurred.

Comparison caveat: baseline watchdog samples ranged 23.5–33 FPS, but the live
diagnostics panel briefly showed 16.5 and then 10.5 FPS immediately before
injection, with recent arrivals and no stall. The longer baseline and this rate
dip differ from the control. Do not use this pair to claim a throughput or timing
benefit. Both first replacements passed; a benefit from adding delay remains
unproven, and the original locked-phone issue remains unresolved.

Capture: `/tmp/dat-two-second-20261016-trial/records.jsonl` and `summary.json`.
Verified startup; contiguous native 1–171, Dart 1–27 and bridge 1, no malformed or
rejected records, duplicate/out-of-order sequences, detected gaps or truncation.
Operator-stopped capture; trailing loss remains undetectable. Only tagged
structured traces were retained, not the full untagged SDK console.

Restored normal signed release, verified no investigation Logging plist entry,
installed/relaunched without deleting app data, and verified idle Start UI and
background streaming off. Restored and verified iPhoneMirror Agent Access off.
No extra trial or lock test ran. The next planned condition, if selected, is
another two-second foreground trial; it is not authorized by this result.
