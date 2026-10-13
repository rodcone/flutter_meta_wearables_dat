# Investigate iOS streaming stalls while locked

Prepared 2026-10-13. Status: Step 1 captured an actionable example recovery bug;
the originating SDK error remains unexplained. See the controlled-trial results below.
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

## Step 1 implementation and capture procedure

Added opt-in native and example JSON trace events without changing streaming,
audio configuration, stall thresholds, or recovery decisions. Both loggers cap
output at 2,000 events plus one explicit limit marker per process. Native events
have a random run ID, sequence, uptime and wall-clock microseconds; Dart events
have sequence, Stopwatch elapsed and wall-clock microseconds. Use the paired
wall/monotonic samples to correlate clocks, allowing for sampling uncertainty
and any wall-clock adjustment. Do not directly subtract Dart and native clocks.

Native events cover parent/camera identity, states and error codes, lifecycle,
audio activation/interruption (including an optional `wasSuspended` value),
first/resumed SDK frames, stall snapshots, and teardown. Existing watchdog ticks
produce a summary every five seconds or when a tick is delayed beyond two seconds;
no new keep-alive timer or frame-byte subscription was introduced. Dart events
cover received state/errors, both retry counters, start/stop/teardown, recovery
watchdog expiration and the final error passed to teardown. `streaming` state and
`startReturnedTexture` still do not prove frame delivery; correlate with native
`firstFrame`/`framesResumed`. SDK error mappings are logged without free-text
messages, and audio traces use port types without device names.

Native switch: launch argument `--mwdat-investigation` or environment
`MWDAT_INVESTIGATION=1`. A `traceStarted` event verifies activation.
Example switch: build with `--dart-define=MWDAT_INVESTIGATION=true`.
Both are off by default. Installation preserves existing app data.

From `example/`, build with the repository Flutter SDK:

```sh
/Users/gdelataillade/dev/flutter/bin/flutter build ios --release \
  --dart-define=MWDAT_INVESTIGATION=true
```

After installation, start a tagged collector before launching. Substitute
the connected iPhone UDID and a fresh local output path; stop the collector after
the bounded trial. Collect only tagged events, not a whole-device log archive.
During this run, `-p Runner` missed the newly launched process; omit that filter
and select the verified app PID when parsing, or resolve the PID after launch.
Use a PTY reader with line-flushed output when consuming syslog incrementally:

```sh
idevicesyslog -u "$DAT_DEVICE_UDID" --no-colors \
  -m MWDAT-TRACE -o "$DAT_TRACE_PATH"
```

The syslog relay delivered Dart events but did not deliver native NSLog events
in this setup. A second, filtered `devicectl --console` capture delivered native
events. Launch with the console bridge, without a debugger, and retain only
`[MWDAT-TRACE]` lines from that output:

```sh
xcrun devicectl device process launch --device "$DAT_DEVICE_UDID" \
  --terminate-existing --console \
  --environment-variables '{"MWDAT_INVESTIGATION":"1"}' \
  io.rodcone.flutterMetaWearablesDatExample --mwdat-investigation
```

Before locking, verify that both native and Dart tagged JSON actually reach the
collector, enable background streaming, and establish a healthy foreground
baseline. Do not infer missing events until collector completeness is checked.
Record firmware from the paired-device UI if exposed. USB log transport connected
successfully and the controlled trial below verified both event streams without
sequence gaps. Console/log capture can affect observation; repeat without capture
when assessing any eventual behavioral fix.

Validation: focused Dart MCP analysis clean; five focused example tests passed
with tracing disabled and enabled; 44 native timing assertions passed. A host
smoke check confirmed the native logger emits nothing while disabled and valid
sequenced JSON capped at 2,001 entries while enabled. Signed iOS release build
passed. The built app contains DAT Core 1.0.0 and `audio`, `bluetooth-central`,
`bluetooth-peripheral`, `external-accessory` modes. No DTD/debug app was running;
native changes were rebuilt instead of hot reloaded. SDK root cause remains open.

Documentation comparison:
- [Meta background guide announcement](https://github.com/facebook/meta-wearables-dat-ios/discussions/142)
  links an April 2026 CameraRecorder-based guide with audio-engine recording,
  HFP and an active audio session. That differs from this plugin's camera-only
  setup. It is not proof that changing audio routing would fix these stalls.
  The local DAT 1.0.0 release tag contains binaries and metadata, not sample sources.
- [Apple audio-session guidance](https://developer.apple.com/library/archive/documentation/Audio/Conceptual/AudioSessionProgrammingGuide/ConfiguringanAudioSession/ConfiguringanAudioSession.html)
  discusses suspension-driven audio interruption when an app is not actively
  using audio. This supports capturing interruption metadata, not assuming that
  activation alone proves uninterrupted background execution.

## Controlled trial — 2026-10-13, 15:48 Europe/Madrid

Evidence: signed release on iPhone 17 / iOS 27.0, DAT 1.0.0, Bluetooth Classic,
RAW / medium / 30 FPS, background opt-in on. Native trace run
`5EF2F4AC-C4C2-43F4-81AF-64304DFCA5C1`, camera
`6ABC2E0D-287B-428D-8260-ABC484569E54`. Firmware was not read in this run.
Both native console and Dart syslog streams were verified before the lock.
Complete captured sequences: native 1–35 and Dart 1–17, including cleanup;
neither had missing sequence numbers or reached the event cap. No debugger was
attached, but the console bridge and USB/Mirror connection are observer effects
to account for in later verification. No recording payload or screenshot was saved.

Foreground was healthy at approximately 26.5–28 SDK FPS. The lock command was
issued at 15:48:25; native background entry was 15:48:26.448. A 30-second wait
preceded the unlock request, but native foreground return was 15:50:29.948:
actual background duration 123.501 seconds, including the user's response time.
The app showed the stopped placeholder after unlock without Start/Stop input.

| Time after background entry | Evidence |
| --- | --- |
| +0.805 to +0.886 s | Nine native `videoStreamingError` events from the same camera |
| +0.904561 s | Dart receives the first error; SDK retry count is zero |
| +0.904914 s | Schedules recovery 1, with a 400 ms backoff |
| +0.905802 s | Next error reschedules recovery and increments count to 2 |
| +0.906761 s | Next error reschedules recovery and increments count to 3 |
| +0.908607 s | Fourth received error calls `endSessionWithError` |
| +0.908678 s | Cancels the pending recovery timer |
| +0.917781 s | Native camera teardown begins; last SDK frame age is 0.765 s |
| +1.056695 s | Dart teardown completes |

There was no `recoveryStarted` or automatic start event. Three scheduled retries
were consumed by an error burst before any attempt could execute. There was no
`frameStalled` event, and the separate frame-stall retry count stayed zero.
No audio-interruption event was captured before this stop. These facts establish
the immediate application-side failure, not the source of the SDK error burst.
The earlier trials with retained frame-stall snapshots may have different paths.

Code corroboration: `_setStreamError` permits another `_scheduleRecovery` while
`_isRecovering` is true. Each schedule increments `_recoveryAttempts` and cancels
the previous timer. Once the counter reaches three, the next recoverable error
tears down instead. Increasing the frame-stall threshold cannot fix this sequence.

### Proposed next implementation (not yet applied)

1. Reproduce this exact burst in the provider test: several `videoStreamingError`
   events on a streaming session before the first 400 ms backoff fires. Assert
   one pending attempt, no premature terminal teardown, then one executed retry.
2. Coalesce recoverable errors belonging to a pending/in-flight recovery. Keep
   terminal SDK errors, explicit Stop and background opt-out authoritative.
   Ensure errors from a failed replacement still advance recovery rather than
   being swallowed forever; distinguish backoff from an executing attempt if
   needed. Count actual attempts rather than repeated notifications.
3. Retain bounded retries and the existing separate frame-stall budget. Test
   persistent failed replacements, terminal errors during backoff, cancellation,
   and old-session callbacks. A mere `_isRecovering` early return is insufficient
   unless these cases remain correct.
4. Repeat the instrumented lock trial, then a normal release run without capture.
   Report successful retry separately from uninterrupted SDK streaming. Investigate
   the SDK burst independently if it persists after application recovery works.

This supersedes running the entire Step 2 comparison first: the captured burst
is already a deterministic, actionable policy defect. No recovery fix was made
during evidence capture. Temporary trace collectors were stopped; the background
toggle was restored to its initial off state for this run. A normal release build
without the Dart tracing define was built, installed and launched with no trace
argument/environment. The idle screen was verified and iPhoneMirror Agent Access
was restored to off. The 44-assertion native harness still passes; no recovery
behavior was changed.

## Recovery fix — 2026-10-13

Approved implementation of the plan above:

- Error notifications share a single pending backoff. Counters advance when a
  recovery executes, with the same three-attempt limits and separate frame-stall
  budget. Duplicate errors do not extend the watchdog deadline.
- Every recovery explicitly stops before starting. The captured SDK error burst
  occurred while native state was still streaming, so relying on an SDK auto-stop
  could return the failed session's existing texture.
- Errors during a replacement's pending start are retained and processed once
  the start completes. Failed replacements still advance to the next bounded
  attempt. An old session's streaming notification cannot cancel pending recovery.
- Recovery and subscription generations reject obsolete callbacks. Manual Stop,
  terminal errors, background opt-out and the watchdog cancel recovery. A late
  native start result is cleaned up before another manual start is allowed.
- Added 12 provider regression cases: nine-error burst; errors during replacement
  start; synchronous/asynchronous failed replacements; Stop during teardown;
  watchdog with late texture; and Stop/terminal/background cancellation both
  during backoff and during a pending start. Existing first-frame stall budget
  and compatibility tests remain intact.

The burst regression was observed failing before the fix (fourth error ends
recovery before any attempt). After the fix, all 26 example tests pass, focused
Dart MCP analysis reports no errors, and the signed instrumented iOS release
build succeeds. No running Dart debug/DTD process was available for hot reload;
physical verification uses a newly installed release build. Device retest pending.

### Instrumented device retest — 16:07 Europe/Madrid

Same iPhone/glasses, Bluetooth Classic, RAW / medium / 30 FPS, background opt-in.
Native trace run `3FE322BD-11C4-4B80-B2C1-C90E2995ADE4`. Complete sequences native
1–73 and Dart 1–43, with no missing entries or trace cap. Local-only filtered
logs and normalized `trial.json` are under the temporary directory
`dat-recovery-trace-ptclotxz`; no frame payloads or screenshots were saved.

| Relative to background entry | Result |
| --- | --- |
| +0.531 to +0.542 s | Five SDK `videoStreamingError` events on camera `08FB1800-684E-4536-B29E-3466F9196DC0` |
| +0.586 s | One recovery scheduled; four following Dart notifications coalesced |
| +1.306 s | One actual retry executes (timer scheduling took longer than the nominal 400 ms in background) |
| +4.167 s | First frame on fresh camera `8242F61E-77CA-4FF9-A96E-A2A08F204C6C`, texture 1 |
| +60.371 s | Later `sdkFramesStopped` stall: 1.699 s arrival gap after 1420 received frames |
| +60.777 s | Separate frame-stall recovery executes, frame-stall budget count 1 |
| +63.442 s | First frame on camera `AC55B641-8A12-4F04-AA36-137AACA33602`, texture 2 |
| +69.655 s | Foreground after manual unlock; no Start/Stop input |

The preview was observed updating after unlock. Diagnostics showed SDK 27.5 FPS,
texture submissions 25 FPS, no current stall, 990 frames received and 740
submitted. Both recoveries happened while locked. This validates error-burst
coalescing and recovery on this device, **not uninterrupted background delivery**:
the upstream SDK error burst and a later frame gap still occurred. USB,
iPhoneMirror and console/syslog capture remain observer effects. After verification,
manual Stop worked, and both collectors were stopped before installing the normal
trace-disabled release for a comparison run.
