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


## Attempted delayed trial 3 — baseline failure, 2026-10-16 13:11–13:12

**Comparison not executed.** The fresh manual baseline stalled after its first
frame, before opening diagnostics or selecting/injecting the two-second trial.
The example automatically recovered under its existing natural-error policy.
The operator then stopped the stream and ended the batch rather than treating
the recovered session as a clean baseline. No synthetic trigger or experimental
wait event appears in the capture; this is neither a delayed pass nor failure.

Same implementation `03e2b14`, documentation HEAD `a6bfb33`, both investigation
flags and warning logging; RAW/medium/30 FPS, Bluetooth Classic, foreground with
background streaming enabled. User confirmed unlocked/connected/worn. Native
snapshots reported connected/donned/open/compatible/thermal none (battery 93%).
iPhoneMirror reported iOS 27.0.1; DAT 1.0.0 unchanged. Glasses firmware and Meta AI
version remain unavailable. Previous final cleanup → baseline start was 266.572
seconds by native uptime; this does not prove a device-state reset.

Baseline camera `2566F8BD-3490-462A-A6BD-F9703A70D2E1`, texture 0, received and
submitted exactly one frame. The native stall snapshot then reported
`sdkFramesStopped`, 1,741,601 us since last frame, 1,739,492 us since submission,
zero queued frames, foreground, native state STREAMING. The plugin-generated
`frameStalled` reached Dart as a platform error. No genuine SDK session error,
disconnect, thermal event or background transition was captured.

One existing automatic recovery ran with no experimental delay: native cleanup
113.626 ms, cleanup-end → next start 1.348 ms. Replacement camera
`B3C4B833-A569-47B3-BB75-EEE962765872`, texture 1, delivered 1,040 frames over
39.008 seconds through the last watchdog before manual Stop, at 25.5–27 FPS.
This shows successful natural recovery in this attempt, not uninterrupted
baseline delivery and not a known cause of the original interruption.

Capture: `/tmp/dat-two-second-repeat-20261016-trial/records.jsonl` and
`summary.json`. Startup verified, native 1–152, Dart 1–24 and bridge 1 contiguous;
no malformed/rejected records, detected gaps, duplicates, out-of-order or
truncated records. Operator-stopped; unobserved trailing records cannot be ruled
out. Full untagged SDK console was not retained. Mirroring sometimes returned
older frames during idle UI setup, but native capture stayed coherent; no pixel
comparison was used as health evidence.

Restored normal signed build with no investigation Logging entry, reinstalled
without deleting data, relaunched and verified idle Start UI/background off.
Agent Access off was verified in iPhoneMirror. No manual retry, synthetic trial,
or lock test followed. Current comparison remains one zero-delay pass and one
two-second pass, plus this separately recorded baseline failure. Review the
natural stall before choosing further device work; no production timing change
is justified by these results.


## Analysis of the natural baseline stall — 2026-10-16

Read-only analysis of the existing capture and current native implementation;
no additional device operation or production change.

Timeline relative to baseline native startRequested:

| Time | Observation |
| --- | --- |
| +2.379 s | First SDK publisher callback recorded; one frame subsequently submitted |
| +4.121 s | Stall snapshot: one arrival, one submission, last arrival 1.742 s ago |
| +4.528 s | Existing recovery requests native Stop after approximately 400 ms backoff |
| +4.643 s | Replacement start, 1.348 ms after native cleanup completed |
| +7.084 s | Replacement first frame |

The failed first frame reached submission approximately 2.1 ms after arrival
(the two ages in the same stall snapshot differ by 2,109 us). Arrival is counted
at the beginning of `videoFramePublisher.listen`, before `frameQueue.sync`,
decoding/copying, throttling or texture submission. Submission is counted after
`textureFrameAvailable`. Consequently this is not evidence of continuing SDK
arrivals with a frozen Flutter preview. No second callback reached the arrival
counter before teardown. RAW was selected, so HEVC decoding is not involved.

Important limit: `queuedFrames` decreases when processing **starts**, not when
the publisher callback finishes. Zero queue depth therefore cannot prove the
first callback returned or exclude all plugin-side backpressure. Successful
submission shows the first callback progressed far through processing, but there
is no callback-exit record. The immediate cause can be localized to absent new
callback arrivals; the underlying cause cannot be assigned to SDK, transport,
glasses or callback completion with this capture.

There was no captured background transition, disconnect, doff/hinge closure,
thermal change, SDK error, or audio-route change around the gap. Audio activated
roughly 26 seconds before start on built-in microphone/Bluetooth A2DP. This is
context, not proof that audio/transport has no effect. Recovery began before we
could observe whether the original session would resume spontaneously. The gap
is a real violation of the existing 1.5-second post-first-frame rule; it does not
prove a permanent wedge or justify lengthening that rule.

Unlike the earlier synthetic replacement rejection (`unexpectedError("Session
ended by device")`), this failure delivered a frame and then went silent on a
fresh manual baseline. Treat them as separate observed failure modes unless
additional evidence connects them. A post-cleanup delay cannot prevent the
initial manual-start gap by construction. Successful immediate recovery here
also does not establish that immediate restarts always work.

### Recommended next implementation plan (not implemented)

Before more comparisons, close the specific callback-completion evidence gap:

1. Under existing investigation opt-in only, maintain per-camera callback
   entered/completed counts and active-callback start age, using a short lock
   that is never held across processing or tracing. Use `defer` to record exit
   on every callback path. Retain no sample buffer in diagnostic state.
2. Add a bounded first-callback exit record and include callback activity in
   stall/watchdog snapshots. Do not log every frame, add sleeps, subscribe to
   frame bytes, change the synchronous ownership strategy, or alter retries.
3. Validate completion accounting, early exits and session isolation with the
   smallest native harness scope; verify normal/investigation builds. A later,
   separately selected natural baseline test may distinguish an outstanding
   callback from SDK silence after callback return.

This is a proposed investigation step, not a confirmed fix. Leave the
zero/two-second comparison paused rather than collecting more synthetic passes
that cannot explain the observed manual-start failure. No upstream report should
claim an SDK root cause on the present evidence.


## Callback completion instrumentation — implemented 2026-10-16

The maintainer selected the local-only implementation plan above. Per-camera
investigation state now counts callback entries and bodies reaching their defer
exit marker. It tracks active callback IDs and timestamps under a separate short
lock; no frame/sample buffer is retained by diagnostics. Normal launches allocate
no callback tracker. No recovery policy, frame ownership, threshold or delay
changed; no public diagnostics fields were added.

Native investigation stall/watchdog, teardown and lifecycle snapshots include
`callbacksEntered`, `callbackBodiesCompleted`, `activeCallbacks`, and (only while
active) `oldestActiveCallbackAgeUs`. Each camera emits at most one
`firstCallbackBodyCompleted` record, with session ID, callback ID and
`callbackBodyDurationUs`. Accounting locks are released before trace emission and
are never held across frame processing. The defer is installed before the weak
owner guard, so that early exit also completes accounting.

Interpretation: an active callback whose age covers an arrival gap points toward
an unfinished callback body; completed bodies with no new entries show silence
after our completion marker. Neither proves SDK buffer reclamation or transport
root cause. The marker precedes trace emission and actual return to SDK code.
Arrival/submission and callback snapshots use separate locks and are not one
atomic cross-counter observation; small transient differences are possible.

Local checks: stream diagnostics harness passes 60 assertions with tracing off
and 60 with tracing on, covering active age, out-of-order and duplicate exits,
early-return defer, 500 concurrent callbacks, per-camera isolation, opt-in
allocation and unchanged public snapshot. Existing investigation trace/sink
harnesses pass. Signed investigation and normal iOS release builds pass strict
codesign verification. Investigation Logging was `warning`; the final normal
build has no investigation Logging plist entry. `git diff --check` is clean.
No installation, launch, stream, phone setting change or device QA was performed.

## Instrumented natural baseline — 2026-10-16

One user-authorized foreground manual start on `fa5f5c0`, with glasses confirmed
connected/worn, phone unlocked, RAW/medium/30 fps and background streaming enabled.
Only `MWDAT_INVESTIGATION` was enabled; no synthetic recovery trigger, experimental
delay, lock interval or second start was used. Capture preflight passed.

Result: healthy baseline; the intermittent failure did not reproduce. Camera
`061ECD51-A406-4359-83C9-858D2A86F719` (texture 0) received its first frame 2.597 s
after native start request. First-frame-to-teardown observation lasted 42.413 s,
with 1,135 arrivals and 1,051 submissions. Rolling watchdog arrival rates were
23.5–27.5 fps. The first callback body reached its completion marker in 1,930 us.
All eight post-first-frame watchdog samples reported zero active callbacks; at
teardown, entries and completed bodies both equaled 1,135, with queue zero and
peak queue one. No stall, recovery, SDK error or background transition was captured.
Device snapshots reported connected/donned/open/compatible and thermal none.

This validates callback instrumentation during a healthy device run, not the
cause or resolution of the intermittent silence. The marker still precedes actual
return to SDK code; no failure-time callback conclusion is available. Submitted
frames are not proof of displayed frames. Keep the delay comparison paused.

Local evidence: `/tmp/dat-callback-baseline-20261016/{records.jsonl,summary.json}`.
Capture ended by operator after manual stop and background-streaming disable.
Native sequences 1–95, Dart 1–10 and bridge 1 were contiguous, without malformed,
rejected, duplicate, out-of-order or truncated records. Missing trailing records
remain undetectable; this collector does not capture the entire SDK console.

Restoration: normal signed release rebuilt without investigation defines, strict
codesign verification passed and MWDAT Logging was absent. Installed in place,
relaunched and verified idle with background streaming off. Agent Access was
turned off and verified in iPhoneMirror. No production code changed, no additional
stream trial ran, and nothing was pushed or posted externally.

## Instrumented natural baseline repeat — 2026-10-16

The maintainer selected one further foreground trial and confirmed readiness.
Built from `adf142a` with investigation enabled and recovery experiment disabled;
RAW/medium/30 fps, background streaming enabled, no lock or synthetic trigger.
Capture preflight passed. One manual start was performed; the app's existing
natural recovery made one automatic restart. No second manual start was made.

The failure reproduced. Camera `6508D127-DB75-47CE-BDD1-5873D815F11B` (texture 0)
received and submitted exactly one frame, 2.425 s after native start request.
`firstCallbackBodyCompleted` recorded 2,040 us. At the stall (4.097 s after start),
`callbacksEntered=1`, `callbackBodiesCompleted=1`, `activeCallbacks=0`, queue zero,
peak queue one. Last arrival age was 1,672,731 us; last submission age 1,671,199 us.
The camera still reported streaming in foreground, with `sdkFramesStopped`.
The same completed/active counts persisted at teardown roughly 409 ms later.

Natural recovery then stopped the session (stop-method duration 117.167 ms), and
requested a new session 1.486 ms after cleanup completion. Replacement parent
`D2039866-481F-48EA-BE81-53A0E32EA7B8` failed while starting: SDK error stream
reported `unexpectedError("Session ended by device")` about 83 ms after the new
start request; `ensureSessionStarted` also caught it. These are two reporting
paths for the replacement failure, not evidence of two independent failures.
No replacement camera or first frame was created. The app returned to idle.

Both parent snapshots reported connected/donned/open/compatible, battery 83%,
thermal none. No background transition, disconnect, doff, thermal change or
failure-time audio-route change was captured. Audio activated about 24 s before
manual start using built-in microphone and Bluetooth A2DP output.

Interpretation: this closes the pending callback-body question for this failure:
frame delivery ceased after the first body reached its completion marker, with
no recorded active callback at stall or teardown. It does not prove actual SDK
return/buffer reclamation, nor identify an SDK, transport or firmware root cause.
It also shows fresh-start silence and replacement rejection in one natural run;
causality between them remains unproven. Recovery interrupts observation of
possible spontaneous resumption. Do not change timeouts or claim a delay fix
from this result; next review the evidence and plan a discriminating experiment.

Evidence: `/tmp/dat-callback-repeat-20261016/{records.jsonl,summary.json}`. Native
1–113, Dart 1–18 and bridge 1 contiguous, no malformed/rejected/duplicate/
out-of-order/truncated records; missing trailing records remain undetectable.
This is tagged investigation capture, not the full SDK console.

Cleanup: verified stopped UI, disabled background streaming, ended collector,
rebuilt normal release without defines, verified strict codesign and absence of
MWDAT Logging, installed in place and relaunched. Normal app verified idle with
background streaming off; iPhoneMirror Agent Access verified off. No production
code changes or external publication. Device reliability remains unresolved.
