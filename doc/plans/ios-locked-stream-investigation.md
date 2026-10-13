# Investigate iOS streaming stalls while locked

Prepared 2026-10-13. Status: plan only; no runtime changes or new device tests.
Baseline: `8ded141` on `codex/diagnostics-plan`. Prior evidence is recorded in
[diagnostics-first-frame.md](diagnostics-first-frame.md#agent-controlled-ios-background-qa-2026-10-13).

## Objective and known evidence

Determine why SDK frame delivery stalls while the phone is locked, and whether
the example's recovery policy turns a transient gap into unnecessary teardown.
Deliver a targeted fix only when the evidence identifies an actionable defect.
Keep native stall reporting separate from application-owned recovery.

The release build used Bluetooth Classic, RAW, medium, 30 FPS, and background
streaming enabled. Home/return preserved the session. The first lock produced
a 1.69-second SDK arrival gap and an automatic session replacement. After the
second lock the app was stopped; the retained snapshot showed a 3.39-second gap
in a later session. Manual restart restored moving video. These observations
do not establish the final terminating event, retry count, or underlying cause.

Both failure snapshots had queue depth zero and A2DP output. This provides no
evidence of a growing plugin frame backlog or HFP routing at those instants;
it does not exclude an earlier route transition, process suspension, or SDK issue.

## Code findings to investigate

- `BackgroundStreamingController.swift` activates `.playAndRecord` with
  `.videoRecording` and `.mixWithOthers`. It logs activation, route changes,
  interruptions and media-services reset. Its enabled flag stays true during
  an interruption, so that flag alone cannot prove uninterrupted audio activity
  or process execution. The source plist declares all four background modes.
- `MetaWearablesDatPlugin.swift` records arrival inside the SDK publisher
  callback. A main-actor watchdog checks every second and reports an SDK gap
  above 1.5 seconds. First-frame timing excludes long scheduling gaps; the
  post-first-frame check uses elapsed arrival age. We must distinguish a real
  delivery gap from callback/watchdog scheduling order after suspension.
- `stream_provider.dart` waits 400 ms times its SDK retry counter, explicitly
  stops a frame-stalled session, then starts another. A separate frame-stall
  budget allows three retries per manual start. Reaching `streaming` clears the
  in-flight recovery state but does not establish that frames have resumed.
- The diagnostics panel retains only the most recent stall. It cannot explain
  the complete sequence of recoveries or the final reason for stopping.

## Step 1 — Establish a trustworthy timeline

First inspect available release-device logs and verify the installed build's
configuration, SDK version, glasses firmware, and background modes. Compare the
background setup with the DAT 1.0.0 guidance/sample and applicable Apple docs;
source comments are not proof of a supported keep-alive mechanism. Use official
sources and record version/links when this investigation is executed.

If existing logs cannot correlate events, add bounded, opt-in investigation
logging that works in a signed release build without an attached debugger:

- Monotonic timestamp, event sequence, app lifecycle state, camera generation,
  parent-device-session identity where available, and raw SDK state/error code.
- Audio activation outcomes, interruption begin/end and options, media reset,
  category/mode/options, and route port types. Label observed activation results
  separately from the plugin's enabled flag; do not invent an `isActive` reading.
- Watchdog tick interval, last SDK arrival age, frame-count deltas, and queue
  depth. Record delayed ticks and frame resumption; use low-frequency summaries,
  not a log entry for every frame or an extra timer intended to keep iOS awake.
- Example recovery scheduled/started/completed/cancelled, both retry counters,
  explicit stop/start causes, and the final terminating event. Correlate native
  and Dart time domains with an explicit anchor rather than equating clocks.

Prefer existing OS logs if they remain available after unlock. If necessary,
use an opt-in bounded local journal with capped size, batched writes, a dropped-
event count, and explicit export/clear. Check protected-file accessibility before
relying on writes while locked. Exclude frame/audio bytes, device names and
unnecessary identifiers. Do not add a public diagnostics API unless required.
Do not subscribe to `videoFramesStream()` just to gather health evidence.

Success: one complete lock trial can be reconstructed from background entry
through stall, recovery decisions, foreground return and final state. Missing
logs are reported as a limitation, not interpreted as proof of suspension.

## Step 2 — Separate natural resumption from automatic recovery

Add a test-only example configuration that disables automatic recovery for
`frameStalled` while retaining diagnostics and all terminal-error cleanup.
It must bypass both retry scheduling and retry-exhaustion teardown for that
nonterminal event. Default behavior stays unchanged. Bound observation to the
trial duration, then explicitly stop; never leave an unattended camera session.

Run the same release-build trials with normal recovery and with this observation
mode. Keep transport, codec, quality and FPS identical. Reset the retry budget
with a manual start before each independent trial; separately repeat two lock
cycles within one session to test accumulated retry-budget behavior.

Initial matrix, one trial per cell, then repeat only the discriminating cases:

| Scenario | Normal recovery | Observe without frame-stall recovery |
| --- | --- | --- |
| Foreground control, 60 seconds | Baseline | Baseline |
| Home, at least 30 seconds, then return | Capture timeline | Capture timeline |
| Lock, at least 30 seconds, then unlock | Capture timeline | Capture timeline |
| Two consecutive lock cycles, no manual restart between | Track total retries | Track natural resumption |

Record actual transition times and duration, not just the requested wait.
Unlocking still requires the user. For reproduction: start a nonsensitive scene,
confirm live counters, lock until prompted, unlock to the example without Start
or Stop, and let the agent inspect the report. No folding, calls, or route changes
are part of this first comparison. Restore the original app settings afterward.

Interpretation:
- Frames resume in the same session without recovery: investigate recovery
  eagerness; a reported gap can be valid even if restarting is unnecessary.
- Long watchdog gaps coincide with delivery gaps: investigate scheduling/audio
  lifecycle and event ordering; these timestamps alone cannot prove suspension.
- Watchdog remains timely while SDK arrivals stop: investigate SDK delivery,
  accessory transport and device-session events; it is not yet a hardware verdict.
- Terminal SDK events precede stopping: preserve their semantics and identify
  the device/SDK reason instead of blaming the frame-stall retry limit.

## Step 3 — Narrow the cause, changing one variable at a time

Choose the next experiment from Step 2 evidence. A minimal native DAT sample
using the same SDK, phone, glasses and transport can distinguish Flutter/example
policy from behavior shared with the SDK sample, provided its background setup
is equivalent. A lower-FPS comparison can test load sensitivity. Wi-Fi is a later
transport comparison only if justified; it changes configuration and pairing
conditions, so it should not be the first experiment or require deleting the
installed app without discussing its state loss.

Do not introduce HFP, microphone capture, silent audio, blanket timeout increases,
unbounded retries, or changes to background opt-out as speculative fixes.

## Step 4 — Implement the smallest supported fix

Present the evidence and concrete code change before implementation. Possible
outcomes are conditional, not preselected:

- Recovery policy issue: retain the stall signal, allow a bounded opportunity
  for real frame resumption, then restart if necessary. Keep the three-retry
  bound and honor explicit Stop throughout pending recovery.
- Scheduling issue: adjust eligibility/grace only where measured ordering proves
  it necessary, preserving detection of a genuinely silent foreground stream.
- Audio lifecycle issue: correct the demonstrated activation/interruption path
  without silently changing routing or activating the microphone.
- SDK/firmware limitation: prepare a minimal reproduction and document the
  limitation honestly; do not claim a plugin fix. External reporting is separate.

Keep this investigation distinct from the existing diagnostics delivery so its
new evidence does not turn that change into an unbounded background rewrite.

## Verification and completion criteria

For changed policy, add deterministic tests for the specific failure sequence:
short gap followed by same-session frames; persistent silence; delayed watchdog
execution; terminal error during recovery; explicit Stop during backoff; budget
exhaustion; stale events from an old generation; and background opt-out.
Use the smallest affected Swift/Dart test and analysis scopes, then a fresh signed
release install for native changes. Hot reload cannot validate native changes.

On hardware, repeat at least three independent lock trials plus two consecutive
lock cycles after one manual start. Include a longer, at least 90-second locked
interval, a Home control, and background opt-out. Report continuity, recovery,
and cleanup separately: a new session after unlock is recovery, not uninterrupted
streaming. Confirm manual restart, bounded retry behavior, and no frozen preview.

Completion means a correlated timeline identifies an actionable cause or an
explicit unresolved boundary, any proposed fix has matching regression evidence,
and all device claims state the tested configuration and actual durations.
Android is outside this iOS investigation except for regression checks if shared
Dart code changes. Stop streaming and restore temporary settings/agent access
after each test session. No release, publication or issue closure is part of this plan.
