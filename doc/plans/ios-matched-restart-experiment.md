# Matched restart timing experiment

Status: plan only, prepared 2026-10-14. No experiment code or device actions
authorized by this planning step. Implement the first stage only after the
maintainer selects it; decide later stages from its evidence.

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
