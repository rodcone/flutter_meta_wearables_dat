# Matched restart timing experiment

Status: stage 1 implemented on 2026-10-14. Two foreground batches on
2026-10-15 produced three passes and one failure; the repeat batch passed twice.
Stage 2 remains a proposal, with no delay implementation or production fix.

## Stage 1 controls and trace interpretation

Build from `example/` with the pinned Flutter SDK:

```sh
/Users/gdelataillade/dev/flutter/bin/flutter build ios --release \
  --dart-define=MWDAT_INVESTIGATION=true \
  --dart-define=MWDAT_RECOVERY_EXPERIMENT=true
```

The diagnostics sheet exposes **Investigation: synthetic foreground recovery
(once)** only with both defines. It is enabled only for an eligible foreground
stream. Tapping it dismisses the sheet and waits for route disposal before
dispatch, so diagnostics polling stops first. The captured session token and all
eligibility guards are checked again after dismissal. A stopped, replaced,
backgrounded or disposed session cannot accept the stale request.

An accepted request records `recoveryExperimentTriggered`, with `trialId`,
`triggerSource: synthetic`, `postCleanupDelayMs: 0` and lifecycle. Related Dart
records retain that trial origin until a fresh manual session. On each
`errorReceived`, **`errorSource`** distinguishes `synthetic` from `platform`;
platform includes native SDK errors and plugin watchdog errors. A later real
error in a synthetic trial remains `platform`. Native records are unchanged.

For device QA, use the capture startup checks and physical protocol below:
enable background streaming, start RAW / medium / 30 FPS, verify at least ten
seconds of actual frames, open diagnostics, then tap the experiment action.
Observe replacement frames for ten seconds; explicitly Stop and Start before
repeating. The current control tests immediate recovery only. It does not make
the SDK experience a genuine camera failure or establish the physical root cause.

Validation on 2026-10-14: scoped formatting/static analysis passed; the normal
example suite passed 63 tests and the recovery suite with both defines passed
42. The 11 experiment checks also ran with neither define and each define alone
to verify that both gates are required. The signed instrumented iOS release
build succeeded (`build/ios/iphoneos/Runner.app`). No installation, camera use or
phone test was performed in this implementation step. Native code and the
capture collector were unchanged, so their existing harnesses were not rerun.

## Question and evidence

The latest captured foreground manual restart passed after a 10.453817-second
gap between native cleanup completion and the next native start request. The
automatic background replacement failed after a 3.511 ms gap. Its cleanup took
181 ms, and `unexpectedError` arrived from the new device session before Dart
cancelled recovery. Neither watchdog expired. See the
[comparison evidence](ios-locked-stream-investigation.md).

The existing `400 * attempt` ms backoff in `_scheduleRecovery` runs **before**
`_runRecovery` begins teardown. Increasing that backoff does not directly control
the post-cleanup gap. Manual Start also resets counters and intent differently
from automatic recovery. UI taps cannot reliably reproduce the automatic gap.

We need to test immediate restart in the foreground through the existing
automatic recovery path. This can show whether background state is necessary
for the observed replacement failure in this setup. It cannot reproduce the
SDK/device condition behind a genuine `videoStreamingError` by itself.

## Stage 1: foreground recovery with the existing immediate restart

Add a small example-only experiment gated by **both** the existing
`MWDAT_INVESTIGATION=true` define and a separate
`MWDAT_RECOVERY_EXPERIMENT=true` define. Normal builds expose no control and
execute no experiment path. No public plugin API, native behavior or transport
configuration changes.

- Put one clearly labelled investigation action in the existing diagnostics
  sheet: trigger one synthetic foreground recovery. Close the sheet before
  dispatch and keep diagnostics polling off during the observation.
- Route the synthetic `videoStreamingError` through the same provider `_setError`
  entry point as a real error. Do not bypass `_scheduleRecovery`, `_runRecovery`,
  teardown, subscriptions, deadlines or cancellation guards. Preserve the
  production backoff, immediate post-cleanup start, error mapping and retry budget.
- Accept only while foreground/resumed, streaming is intended, state is
  `streaming`, and there is no pending recovery/start/teardown or terminal-action
  latch. Allow only one synthetic injection per manual session. Verify recent
  native frame delivery externally before triggering; streaming state alone is
  insufficient. Reject invalid requests without consuming a recovery attempt.
- Record a trial ID, `triggerSource: synthetic`, lifecycle, selected delay (zero)
  and the trigger event. Carry that origin into the related Dart trace records.
  Native SDK callbacks remain authentic and separate. Never report the injected
  error as a real SDK fault. Analyze the first executed recovery attempt as the
  primary result; preserve/report any subsequent ordinary retries.
- After any terminal/cancelled trial, explicitly stop/reset and establish a fresh
  manually started session before the next trial. No automatic experiment loop.

Physical protocol: enable background streaming before starting (same audio and
transport setup as the failed background trial), RAW / medium / 30 FPS. Verify
all capture startup markers and at least 10 seconds of fresh frame delivery.
Trigger the foreground experiment and observe the replacement for 10 seconds
after its first frame. Repeat once if the first trial is valid, using a fresh
manual session and another healthy baseline. Keep the glasses worn/connected.

Primary measurements: native cleanup-end-to-start gap, device/camera identities,
first replacement frame, frame counts/rates after replacement, authentic errors,
Dart phase/deadline/cancellation ordering, and capture completeness. A new texture
or `streaming` state alone is not success. Use native monotonic times for gap
measurement, not Dart-to-native wall-clock differences.

## Decision gate after stage 1

| Observation | Next investigation |
| --- | --- |
| Immediate synthetic foreground recovery fails like background | Test a post-cleanup delay in the foreground before attributing failure to background state. |
| Immediate synthetic foreground recovery passes twice | Repeat natural background recovery with the same zero-delay configuration. A difference implicates lifecycle or actual SDK-error context, not lifecycle alone. |
| Mixed results, incomplete logs, no healthy baseline, lifecycle changes during trial | Mark inconclusive; resolve the observation problem or repeat the same condition before adding variables. |

## Stage 2, only if warranted: controlled post-cleanup delay

Add an experiment-only selection of **0 ms or 10,000 ms after teardown returns**.
Ten seconds is a comparison point from the successful manual test, not a proposed
production fix or a known SDK requirement. Snapshot it at trial entry; never
change it mid-recovery. Keep the same recovery path for both values.

The cleanup deadline ends when teardown completes. The existing startup deadline
must begin immediately before the replacement start, after any experimental
wait. Model the experimental wait explicitly so it cannot be misclassified as
startup, reset by duplicate errors, or used to overlap cleanup. Explicit Stop,
background opt-out, disposal, terminal errors and generation changes cancel the
wait and prevent any late restart. Report requested and actual wait separately;
background timers may run late. Do not introduce another recovery attempt merely
because the wait ended, or broaden retries for `unexpectedError`.

Start with foreground synthetic trials at 0 and 10 seconds, then reverse the
order on a second valid pair to reduce ordering/thermal effects. Reset to a fresh
manual session with a healthy baseline between trials. If these support a delay
effect, apply the same two selections to **natural** background recovery, one lock
trial at a time. Preserve and record genuine SDK errors. If no natural error
occurs, classify that trial as streaming observation, not a restart trial.

Synthetic foreground and natural background triggers still differ in native
failure context. Do not call this a fully isolated lifecycle experiment. Record
actual timing, wear/connection evidence, firmware if available, thermal level,
transport, codec and build. Any improvement requires repeat evidence and a
separate normal-release validation before proposing a shipping behavior change.

## Automated checks and device boundary

Before installation, use the existing provider/widget-test conventions to cover:

- Gate off: no experiment UI, injection or timing change in ordinary builds.
- Valid synthetic trigger enters the same recovery sequence once; duplicate or
  invalid triggers do not consume attempts or overlap native work.
- Explicit cancellation and terminal errors win; successful state/texture results
  still require real first-frame evidence in physical QA.
- If stage 2 is implemented: delayed start cannot precede cleanup or the chosen
  wait; teardown/start deadlines exclude the experimental wait correctly; late
  callbacks after Stop, disposal or opt-out never start a replacement.

Run scoped format/analysis, the example recovery suite, the collector/native
harnesses if changed, and a signed instrumented iOS build. Review the diff before
device use. The synthetic path only exercises app recovery policy; mock tests
cannot validate the physical SDK condition.

For each physical trial, require collector READY plus current native/Dart events.
Keep the diagnostics panel closed during timing, avoid frame-byte subscriptions
and pixel polling, and stop on invalid capture. For background trials prompt for
manual unlock after 30 seconds and report actual native lifecycle intervals.
Preserve logs locally, stop collectors, restore background streaming off, reinstall
the normal release and restore Agent Access off when the test batch ends.

No changes to existing timeouts, transport, audio session configuration, public
diagnostics or SDK error handling are proposed for production by this plan.


## Physical stage 1 results — 2026-10-15

Tested commit `80e6868` on the connected iPhone 17, iOS 27.0 (24A437), with
DAT 1.0.0, Bluetooth Classic transport (`com.meta.ar.wearable`), background
streaming enabled, RAW / medium / 30 FPS. Both compile-time investigation flags
and the native launch opt-in were active. The user confirmed the glasses stayed
worn and connected throughout, including the failed restart. Firmware was not
independently read in this batch. The visible thermal indicator was normal.

The app remained foreground: trial Dart records say `resumed`, native frame
snapshots say `isAppInBackground: false`, and no native background transition was
captured. Diagnostics closed on each trigger and remained closed during recovery.
iPhoneMirror reconnected between observations; guarded stale actions were rejected,
and a fresh observation was obtained before dispatch. The separate native console
capture continued with one process/run and no detected sequence loss.

| Measurement | Trial 1 | Trial 2 |
| --- | --- | --- |
| Trial ID | `1792079656344983-1` | `1792079824577310-2` |
| Healthy baseline through last pre-trigger watchdog | 33.068 s / 947 frames | 64.086 s / 1,831 frames |
| Native device-session cleanup duration | 131.489 ms | 119.021 ms |
| Cleanup completion to native replacement start | 0.823 ms | 1.745 ms |
| Replacement result | Camera created; first frame 2.528 s after start | Device-session error 127.061 ms after start; no camera or first frame |
| Frame observation after replacement first frame | 28.902 s; 826 received frames at last watchdog; 27–28 FPS | None |
| Outcome | Pass | Fail |

Trial 1 replaced camera `9803957E-F847-4586-B7BD-C4232324956A` with
`4BD72BA2-3DA7-4596-AAF9-39F413951D25`, using a new texture (0 → 1).
Its last observation reported 23 FPS submitted; submission is not display proof.
The preview was also visible after recovery. One automatic recovery attempt ran;
no authentic platform error was reported in that trial.

Trial 2 began from camera `5A3FEAE0-2127-4961-9C6D-24369F71D641`.
Its replacement device session emitted `unexpectedError`; Dart recorded
`errorSource: platform` and cancelled in the `starting` phase. The synthetic
`videoStreamingError` had its own `errorSource: synthetic` record. No teardown or
startup deadline expired and no second automatic recovery attempt ran. The UI
returned to the idle Start screen. This reproduces the replacement failure class
in the foreground; it does not identify the underlying SDK/device/transport cause.

**Separate failed baseline:** after the successful first trial, manual Stop/Start
created camera `8050BD48-614B-4D0E-9BD2-7DFDDCC0A31F`, which failed with
`unexpectedError` before delivering any frame. That manual start was 10.885741 s
after cleanup completion. No synthetic trigger ran against this camera. A further
manual start established the healthy baseline used for trial 2. Preserve this as
a startup failure, not as a third experiment trial or evidence that a ten-second
post-cleanup delay guarantees success.

**Decision:** results are mixed. Keep the existing recovery policy and repeat the
same zero-delay foreground condition after checking device/SDK readiness before
introducing another variable. Background state alone is insufficient to explain
this failure class. A synthetic trigger on a healthy camera does not recreate the
native failure context of a natural background camera error. These data establish
neither a reliable restart delay nor a production fix.

Capture retained locally (ignored, not published):
`build/investigations/2026-10-15-foreground-recovery/records.jsonl` and
`summary.json`. Native run `EE9B4AD0-7DE6-43B8-AB39-0E1627CCE1F9` has sequences
1–280; Dart run `1792079566734124-867509392` has 1–51; bridge run
`A1922C99-0088-4150-9473-00D0B06AFF09` has its startup record. Collector reports
`operatorStopped`, startup verified, no gaps/duplicates/out-of-order/truncation,
and no malformed/rejected payloads. As always, sequence checks cannot detect a
missing tail without a later sequence number. Native uptime, not cross-runtime
wall-clock subtraction, was used for cleanup/start timing.

Cleanup: stopped the owned collector, rebuilt/installed/launched the normal
release without investigation defines, and visually verified background streaming
off on the idle app. Restored Agent Access off and verified its menu status. No
production code changes, new timeouts, delay implementation or lock tests were
made in this batch. The normal signed release build and documentation diff checks
passed; unchanged automated suites were not rerun for this documentation-only step.


## Repeat foreground batch — 2026-10-15, approximately 18:15–18:21

The maintainer selected a readiness check and two identical foreground trials.
Rebuilt from `d379af7` (experiment code still `80e6868`), installed without deleting
app data, and required a new native/bridge/Dart capture preflight. The user
confirmed the phone was unlocked and the glasses connected and worn, with an
instruction to keep them on throughout. Registration/Start availability, fresh
native frames, foreground lifecycle and the normal thermal indicator provided
operational readiness evidence. Firmware and battery state of the glasses were
not independently read; this was not a complete device-health audit.

The configuration stayed Bluetooth Classic, background streaming enabled,
RAW / medium / 30 FPS, zero added post-cleanup delay. Both manual baseline starts
succeeded without a retry. An explicit manual Stop/Start separated trials.

| Measurement | Repeat 1 | Repeat 2 |
| --- | --- | --- |
| Trial ID | `1792081060575799-1` | `1792081218424575-2` |
| Healthy baseline through last pre-trigger watchdog | 59.103 s / 1,671 frames | 59.221 s / 1,677 frames |
| Native device-session cleanup duration | 104.781 ms | 112.507 ms |
| Cleanup completion to replacement native start | 1.734 ms | 1.646 ms |
| First replacement frame after native start | 2.272 s | 2.510 s |
| Observation after first replacement frame | 44.190 s / 1,248 frames | 33.868 s / 973 frames |
| Arrival FPS range in captured post-first-frame watchdogs | 26–29 | 27.5–29 |
| Texture submission FPS range | 24–27 | 24.5–27.5 |
| Outcome | Pass | Pass |

Repeat 1 replaced `300414D0-BA9F-4AEB-8311-CD6F196DA807` with
`D28C8EF1-787C-4BD8-9C7B-6AB3B62EEBEE` (texture 0 → 1). Repeat 2 replaced
`0D35FC3B-5453-431E-B5BC-3C98196E90C6` with
`8B4ACD7B-8B87-4731-81B2-D170CBFACA43` (texture 2 → 3). Each trial executed one
automatic recovery attempt, reached actual first-frame delivery and continued
receiving frames until explicit Stop. No platform error, frame-stall report or
recovery deadline expiry was captured. Native snapshots remained foreground;
Dart records remained `resumed`, with no native background transition captured.
The live preview was visible after each recovery; submission counts alone are
not proof of display.

iPhoneMirror repeatedly changed connection sessions. Rejected stale actions were
not counted as dispatched; a fresh observation preceded each accepted tap.
These interruptions lengthened manual setup/baselines, but native capture had one
continuous run with no detected gaps. Diagnostics was closed during recovery.
There was no phone lock or background test in this batch.

Capture retained locally in ignored
`build/investigations/2026-10-15-foreground-repeat/`: `records.jsonl` and
`summary.json`. Native run `70800349-91C9-4F70-8A00-E1AD9DF8B007` contains
sequences 1–285, Dart run `1792080944410142-332703833` contains 1–49, and bridge
run `CBBE665B-5A7A-4521-9FB2-945590EF1B8C` contains its startup record.
Operator stopped the collector after final manual teardown. Preflight passed;
no malformed/rejected records, gaps, duplicates, out-of-order or truncation were
reported. The missing-tail limitation still applies. Timings use native uptime.

**Interpretation:** this batch passed twice, but the combined evidence remains
three passes and one failure across four synthetic trials, plus the separate
manual startup failure in the first batch. Immediate foreground restart can
succeed; it is not uniformly reliable. These small samples do not establish a
failure rate, a root cause, or that background streaming is fixed. The earlier
foreground failure remains valid. Keep the production recovery policy unchanged;
inspect what the SDK exposes behind `unexpectedError`, and use a natural
zero-delay background comparison if another device trial is selected. No fixed
delay is justified by the present results.

Cleanup: stopped streaming and the owned collector, then rebuilt, installed and
launched the normal signed release. Generated build configuration contains no
MWDAT investigation/experiment defines. Visually verified the idle Start screen
and background streaming off, then restored Agent Access off and verified its
menu status. No production code changed. The normal release build and
documentation diff checks passed; unchanged automated suites were not rerun.
