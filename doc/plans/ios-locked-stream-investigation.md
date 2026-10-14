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

### Normal release comparison — observed at 16:45 Europe/Madrid

Built/installed without the Dart investigation define and launched without native
trace arguments/environment; console/syslog collectors were stopped. Same RAW /
medium / 30 FPS and background opt-in. Before lock, the diagnostics panel showed
camera `BAD6E223-1C39-4A5C-B124-A17CABC18E41`, 266 received frames, SDK 28.5 FPS,
26.5 texture submissions/sec and no stall. The lock command was issued at
16:12:28. The user later replied unlocked; the first fresh observation was at
16:45:43, about 33 minutes after the command. This elapsed observation window
must not be reported as a measured continuous lock interval: no lifecycle trace
was collected. The user subsequently confirmed that the glasses were removed or
disconnected during the interval; continuous wear/connection was not maintained.

At inspection the app showed the stopped placeholder, no current session/texture,
and background streaming still enabled. Retained frame-stall snapshot:

- Camera `3EBC21F1-C045-4EC7-97F4-F7430AC414B5` (different from the pre-lock camera).
- Native state 4 / streaming; app backgrounded; background opt-in true.
- 5,098 frames received, zero texture submissions (expected in background).
- `sdkFramesStopped`, last arrival 2,350,251 us ago, rolling received FPS 0.
- First-frame wait 828,343 us; queue 0, peak 1.
- Audio input `MicrophoneBuiltIn`, output `BluetoothA2DPOutput`.

A replacement camera delivered frames during this run, but the app was stopped
at inspection. The retained snapshot alone does not establish final stop time,
retry count, retry exhaustion, or a terminal SDK error. This comparison cannot be
marked a pass for background continuity or a controlled 30-second test, and does
not overturn the instrumented proof that error-burst coalescing works. The user's
confirmation that the glasses were removed or disconnected makes this run
inconclusive for background reliability under continuous wear/connection. It is
not evidence of a recovery regression. The timing of removal/disconnection is
unknown, so it cannot be assigned as the cause of the retained stall or final stop.
No further code change is justified from this snapshot alone. Background streaming
was restored to off and the normal release left idle; the retained diagnostics
were preserved. Mirror sessions reconnected several times during inspection,
without any agent-initiated app restart.
Agent Access was restored to off after inspection. No additional code or runtime
configuration changes were made.

### Controlled normal release repeat — 16:55 Europe/Madrid

User explicitly confirmed the glasses were being worn before this repeat. Same
installed normal release, no trace collectors, RAW / medium / 30 FPS, Bluetooth
Classic. Background streaming was enabled from its restored off state. Initial
camera `03F9A2D8-B117-4861-8B9A-5E73404F18E8` showed 246 received frames, 222
submissions, SDK 28 FPS, texture submissions 27 FPS and no active stall. The old
failure snapshot from the preceding run remains historical unless replaced.

Lock command issued at 16:55:03; a black phone screen was observed afterward.
After a 30-second wait, the user was prompted to unlock without Start/Stop input
and to keep the glasses worn and connected. The user reported accidentally
unlocking during the intended 30 seconds, so this attempt is not counted as a
continuous 30-second lock test. A fresh observation at 16:56:56 showed live video;
diagnostics then showed replacement camera `1E7CEDA3-58AC-406E-8180-5EB691B70ADD`,
1,156 received frames, 1,063 submissions, 27.5 SDK FPS and 26.5 submissions/sec,
with no active stall. The retained historical stall had 1,627 received frames and
a 2,691,201 us SDK arrival gap. Recovery occurred, but its timing is unavailable.

A second lock command was issued at 16:57:50 on that running replacement session,
without a manual Stop/Start between intervals. The user was again prompted to
unlock after a 30-second wait. A fresh observation at 16:59:19 (89 seconds after
the command, including response/observation latency) showed the stopped
placeholder and the visible banner: "Unexpected device session error: Session
ended by device". The user then confirmed unlocked. Exact lock duration and final
stop timing are unavailable without lifecycle tracing. No manual Start/Stop was
performed between the lock command and this observation.

Diagnostics showed no current session, state stopped, background opt-in still
true, and the same retained 1,627-frame / 2,691,201 us `sdkFramesStopped` snapshot
seen before this second lock. That snapshot is historical and must not be assigned
as the cause of this final stop.

Read-only code inspection ties the displayed message prefix to iOS
`DeviceSessionError.unexpectedError(description:)`, mapped to `unexpectedError`
in `StreamErrorStreamHandler.swift`. The example does not classify that code as
recoverable. This is a source-based interpretation of the visible message, not a
captured event-code trace. It is distinct from the earlier `videoStreamingError`
burst. Native device-session observation also tears down the camera on `.stopped`.
The observation does not prove which error/state callbacks arrived first or why
the glasses ended the session.

Outcome: first repeat inconclusive due to accidental early unlock; second repeat
failed the user-visible resume expectation with a device-ended error. The bounded
retry fix remains validated for its covered errors, while normal-release lock
reliability is unresolved. Do not broadly retry every `unexpectedError` or match
SDK description strings without investigating the device-session lifecycle and
agreeing on a recovery policy. Next recommended step: capture this error/state
sequence with existing instrumentation, then prepare any implementation plan.

Restored background streaming to off and left the normal release idle. No code,
transport, codec, watchdog threshold or audio policy changes were made.
Agent Access was restored to off after the repeat.

### Instrumented follow-up — 17:08 and 17:09 Europe/Madrid

User selected tracing and a fix plan, with glasses worn and connected. Installed
the signed release with the existing opt-in Dart/native investigation flags;
RAW / medium / 30 FPS and Bluetooth Classic remained unchanged. Native run ID
`511FE80A-5A21-4304-AED3-6D497551A8ED`, process 82727. Captured native console and
filtered Dart syslog separately; merged tagged records are retained locally in
`/var/folders/wg/f2_rmttd7mjg7wxjybfjbz000000gn/T/dat-recovery-trace-2_r1ypsm/trial.json`.
This temporary artifact is not committed and may be removed by macOS cleanup.

Native sequence 1–116 is complete. Dart sequence 1–112 has missing records 26–32
in the first interval; the second interval's records 35–112 are complete. These
are trace records, not frame payloads. No audio interruption event was recorded;
that absence does not exclude an SDK, transport or scheduling problem.

First background interval: 17:08:04.453 to 17:08:56.603, **52.150 seconds** by
native monotonic timestamps. Two camera errors coalesced into one recovery; the
replacement first frame arrived 5.199 seconds after background entry. After 1,272
frames, an SDK arrival stall at +51.676 seconds triggered another recovery across
unlock. The next camera delivered its first frame at 17:08:59.513. Post-unlock
diagnostics showed 28 received FPS and 27.5 submissions/sec. Automatic recovery
was observed, but delivery was interrupted and the missing Dart records limit
analysis of that first interval.

Second interval: native background at 17:09:35.638, foreground at 17:12:11.576,
**155.939 seconds** by monotonic timestamps. The requested wait was 30 seconds;
actual time also included user-response latency. No manual Start/Stop occurred
between intervals. The decisive failure occurred within the first 17 seconds:

| Seconds after background entry | Captured event |
| --- | --- |
| +1.274 onward | 36 native `videoStreamingError` callbacks |
| +2.292 | Dart schedules one recovery; duplicate errors share it |
| +8.455 | Native reports `sdkFramesStopped` after 1,064 frames |
| +9.135 | Dart begins its one executed recovery attempt |
| +9.143 | Dart begins teardown |
| +10.857 | Native receives stop request |
| +11.812 | Native camera teardown begins |
| +11.891 | A late frame arrives during teardown after a 9.358-second gap |
| +13.847 | Dart recovery watchdog expires while stop is pending |
| +13.930 | Recovery cancellation invalidates the intended restart |
| +15.132 | Native device-session error is received |
| +15.139 | Native requests `unexpectedError`, with no current camera ID |
| +15.170 | Native device session reports stopped |
| +16.404 | Dart teardown completes; no replacement start follows |

The nominal 400 ms backoff took **6.843 seconds** to execute. The existing
10-second watchdog starts when backoff is scheduled, so it consumed delayed
backoff and pending teardown before a replacement start could even be attempted.
The 36-error burst correctly consumed one actual recovery attempt: the existing
burst-accounting fix held. At unlock the app visibly showed the stopped
placeholder.

In this capture the SDK `unexpectedError` arrived **after** Dart had abandoned
recovery. It did not initiate that cancellation. Its description was intentionally
not logged, and this trace does not prove the earlier normal-release device-ended
banner had the same ordering. Instrumentation, USB and console capture can affect
scheduling. The physical cause of SDK interruptions remains unresolved.

Prepared [a separate recovery-deadline implementation plan](ios-recovery-watchdog-phases.md).
No behavioral changes were applied. Restored background streaming off, stopped
both collectors, installed and launched the normal release without investigation
flags, verified its idle screen and off toggle, and restored Agent Access off.

### Phase-deadline device test — 2026-10-14, 11:54 Europe/Madrid

Installed the instrumented signed release built from `4a21088`. Phone remains
iOS 27.0 (24A437); user deferred the iOS update and confirmed its scheduled
installation was cancelled. User confirmed glasses worn at setup. RAW / medium /
30 FPS, Bluetooth Classic, background streaming enabled. Foreground SDK arrival
was around 27–28.5 FPS, with texture submissions around 25–26 FPS.

Native run `80DB91A1-8C13-47A8-BA59-388FC9791A29`, PID 86750. Complete native
sequence 1–92 and Dart sequence 1–91, with no sequence gaps. Local tagged logs,
merged `trial.json`, and mirror event history are in
`/var/folders/wg/f2_rmttd7mjg7wxjybfjbz000000gn/T/dat-recovery-trace-6srbxhl7/`.
Temporary evidence may be removed by macOS cleanup; no video was recorded.

iPhoneMirror 0.5.0 exposed action observations and timestamped connection events.
It repeatedly reported video stalls, native failures and reconnects while the DAT
app still logged healthy foreground frames. The agent's attempted lock returned
HTTP 409 (session changed), and no native background event followed it. The user
therefore locked the phone manually and confirmed locked. This separates the
mirror failures from the subsequently observed app failure; causality between
mirroring and background scheduling is not established.

Native background entry was 11:54:43.728; foreground return was 11:56:28.482.
Monotonic background duration: **104.755890 seconds**, including the time after
the 30-second unlock prompt while awaiting the user's reply. This is not an exact
30-second lock test. No manual Start/Stop occurred during the interval.

| Seconds after native background entry | Event |
| --- | --- |
| +2.715 | Dart schedules recovery for the camera error burst |
| +3.130 | One recovery enters stopping and starts teardown |
| +3.132 | Native receives stop request |
| +18.126 | Native camera-teardown trace emitted |
| +30.209 | Camera state becomes stopping |
| +46.753 | Dart cleanup watchdog fires in stopping phase (20,000 ms policy) |
| +48.435 | Recovery cancellation is traced |
| +95.753 | Native device-session error received |
| +95.754 | Native requests `unexpectedError` without a current camera ID |
| +95.780 | Device session reports stopped |
| +96.500 | Dart teardown completes; no replacement start follows |
| +104.754 | Foreground event; native session stopped |

All 40 `videoStreamingError` callbacks shared one actual recovery attempt.
Cleanup took about **93.37 seconds** from Dart teardown start to completion.
The nominal 20-second timer callback ran about **43.62 seconds** after teardown
began; background scheduling/logging delays prevent treating it as a wall-clock
execution guarantee. The trace does not isolate which SDK await, actor scheduling
delay or diagnostic operation accounted for the long native stop.

After unlock, a successful fresh mirror observation showed the stopped placeholder
and "Waiting for an active device". Diagnostics showed no current session, state
stopped, zero counters, foreground, and background opt-in still true. The user
subsequently confirmed that the glasses remained worn and connected throughout
the interval. Classify this as an observed failure to resume under user-confirmed
continuous wear/connection. This is user-reported connection evidence, not an
independent transport trace; the app's later lack of an active device remains
unexplained. The later `unexpectedError` again followed watchdog cancellation;
its description was not logged.

Outcome: the new phase deadline and non-overlap guard behaved as designed, but
automatic recovery failed. No replacement start was issued while cleanup was
pending, nor after it eventually completed. A second consecutive interval could
not proceed from a running stream; the uninstrumented comparison was not run.
Do not mark background reliability fixed or merely increase the timeout again.
The next proposed investigation is native teardown phase timing, described in
[the recovery plan](ios-recovery-watchdog-phases.md).

Cleanup: disabled background streaming and visually verified the off toggle;
stopped both owned collectors; built, installed and launched the normal release
without trace flags; observed the idle Start screen. Agent Access restored off.
No implementation changes were made during this test.

### Native cleanup phase capture — 2026-10-14, 12:47 Europe/Madrid

Installed the instrumented release from `922e60e`, RAW / medium / 30 FPS,
Bluetooth Classic, background opt-in enabled. User confirmed the phone ready
and glasses connected/worn at setup. Foreground arrival was 28.5–30 FPS near
lock, with 26.5–28 texture submissions/sec. No manual Start/Stop occurred during
the interval. iPhoneMirror dispatched lock successfully; native background entry
was 12:47:35.135 and foreground return was 12:48:22.011: **46.877028 seconds**
monotonic elapsed time, including user response latency after the 30-second
unlock prompt. The user confirmed unlocking.

Native run `554ADD44-CD16-488A-AED4-2AF1A85E3927`, PID 86886, sequence 1–119
complete, with no truncation and every cleanup span paired. Local tagged logs
and merged `trial.json` are in
`/var/folders/wg/f2_rmttd7mjg7wxjybfjbz000000gn/T/dat-recovery-trace-99rtxewl/`.
The Dart syslog reader captured no records; a second reader connected but also
captured none. Consequently Dart phase transitions, timer events and recovery
accounting cannot be verified from this capture. No video was recorded; temporary
evidence may be removed by macOS cleanup.

| Seconds after native background entry | Event |
| --- | --- |
| +1.238 | Camera reports `videoStreamingError` |
| +4.397 | Stall trace emitted; its diagnostic field capture took 1.771 seconds |
| +4.868 | Frame arrival resumes before teardown |
| +4.875 | Native receives stop request |
| +4.982 | Native stop method completes, measured operation duration 107.140 ms |
| +4.983 | Replacement start requested; a new device-session identity is observed |
| +5.080 | Replacement device session reports an error; `unexpectedError` requested |
| +5.081 | Replacement device session stops; no replacement camera was created |
| +46.877 | Foreground return with stopped state and zero current-session counters |

The measured stop included camera stop 2.352 ms, video listener cancellation
16.255 ms, camera stopped-state wait 45.454 ms, device stop call 0.182 ms and
device stopped-state wait 34.183 ms. Both state races returned `stopped: true`;
first-result-to-group-exit gaps were below 0.5 ms. Main-actor scheduling was
0.248 ms and teardown-task scheduling 0.801 ms. These are elapsed durations,
including nested instrumentation and scheduling, not isolated CPU or SDK costs.

**Outcome: automatic recovery failed again, but the earlier 93-second cleanup
delay did not reproduce.** This time cleanup completed before a fresh start,
which failed about 96 ms after its device-session observation. No replacement
camera or first frame followed. A fresh post-unlock mirror screenshot showed
the stopped placeholder with Start enabled. The mirror required one reconnect
after unlock. There was no second consecutive interval or uninstrumented lock
comparison.

The 1.771-second diagnostic-field capture is a separate measurement concern:
`diagnosticsSnapshot()` includes an audio-route read, but this span does not
isolate that read from other work or scheduling. Trace-lock waits were at most
4 microseconds. Neither the prior long cleanup nor this replacement-session
failure has a demonstrated physical root cause. Do not increase deadlines or
broaden `unexpectedError` retries based on this run. A useful next investigation
is to restore reliable Dart capture, minimize observation overhead, and compare
one foreground restart with one background restart using the same configuration.

Cleanup: disabled background streaming and visually verified it off, stopped
both owned log collectors, rebuilt/installed/launched the normal release without
investigation flags, observed its idle screen and verified its background toggle
off again. Restored iPhoneMirror Agent Access off and verified the menu status.
No implementation changes were made during this test; the normal release build
and documentation diff check passed.
