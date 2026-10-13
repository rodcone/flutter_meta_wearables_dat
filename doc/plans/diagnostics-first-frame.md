# Stream diagnostics and first-frame detection

Status: approved and implemented; automated validation passed, device QA pending.
Baseline: main at b731a6b (PR #52 merged), 2026-10-13.
Tracks issue #33 and the independent watchdog gap reported in #47.

## Goal and scope

Make release-build streaming failures diagnosable from Dart without a Mac or a
video-frame subscription, and report a stream that never produces its first
frame. Preserve existing streaming, transport, audio routing, and automatic
recovery ownership. No DAT upgrade or motion/input/microphone implementation.

## Evidence from the current code

- Both native watchdogs skip detection when no SDK frame has ever arrived.
- Both platforms already count SDK arrivals and texture submissions separately.
- iOS FrameLivenessTracker snapshots under a lock. Android FrameProcessor reads
  individual volatile fields; public snapshots need coherent synchronization.
- Both resyncPushClock implementations change the push timestamp on foreground
  entry without a submission. Keep watchdog grace separate from diagnostic time.
- Current FPS logs use the most recent inter-frame interval, which remains stale
  when delivery stops; it is not a suitable public current-FPS metric.
- Audio-route information exists in iOS BackgroundStreamingController logs but
  there is no Dart diagnostics API. The current example has no diagnostics UI.
- The example already handles frameStalled through a bounded recovery policy.

## Proposed public contract

Add `MetaWearablesDat.getDiagnostics(): Future<StreamDiagnostics>` through the
existing facade, platform interface, and method channel. No additional event
channel in this iteration. Reading must not initialize DAT, request permissions,
start a session, configure audio, or change watchdog/rate baselines.

The immutable snapshot will expose:

| Field | Semantics |
| --- | --- |
| sessionId | Opaque per-camera-session generation; null when idle; changes on restart, including same glasses. Not a hardware identifier. |
| sessionState | Existing StreamSessionState; stopped when idle. |
| requestedFrameRate, requestedQuality, requestedCodec | Requested configuration; null without a camera session. |
| effectiveCodec | Codec actually used by the bridge; Android reports raw even if hvc1 was requested. Null until known. |
| isAppInBackground, backgroundStreamingEnabled | Current lifecycle and keep-alive status, preserving existing platform semantics. |
| framesReceived, framesSubmitted | Per-session integer counts; zero before first frame. Submitted means handed to the texture/surface, not displayed by Flutter. |
| receivedFps, submittedFps, measurementWindow | Rates over a bounded rolling two-second monotonic window; window is shorter during startup. Null until measurable, zero after a full empty window. No lifetime averages or stale last-gap rates. |
| timeSinceLastFrame, timeSinceLastSubmission | Nullable Duration values; null means no actual arrival/submission. Foreground grace must not fabricate a timestamp. |
| waitingForFirstFrame, firstFrameWait | Whether the current session has received no frames; elapsed eligible streaming time, excluding paused/suspended intervals. |
| stallReason | Nullable typed reason: firstFrameTimeout, sdkFramesStopped, textureSubmissionsStopped. Clear on recovery/new session; not proof of physical root cause. |
| audioRoute | iOS input/output port types from currentRoute; null on Android (unsupported). Empty iOS lists mean no ports, not unavailable. Avoid device names/UIDs. |
| queuedFrames, peakQueuedFrames | Existing iOS queue metrics; null on Android until an equivalent queue is tracked. |

Wire durations use explicitly named integer microsecond keys. Idle snapshots use
null configuration/timing/rates, zero counters, and no stall reason; audio route
and app/background status remain queryable. Snapshots are current state, not an
unbounded history. The example may retain the latest failure snapshot locally.
Document unsupported fields and malformed/unknown enum handling in Dart tests.

Keep the existing `frameStalled` code. Add an optional typed `stallReason` to
StreamSessionError and the native payload; old consumers keep using code/message.
Populate it for existing arrival/submission stalls as well as first-frame timeout.

## First-frame policy

- Propose 10 seconds of eligible streaming time before firstFrameTimeout. This
  is a conservative starting threshold, not a measured SDK guarantee.
- Start timing on the native STREAMING transition, independent of Dart listeners;
  never include connection, permission, Wi-Fi association, or STARTING time.
- Use a monotonic injected clock. Accumulate time only while the stream is
  STREAMING and frame delivery is expected. Pause during SDK PAUSED and grant
  foreground/resume grace rather than counting process suspension as a failure.
- With background opt-in enabled, SDK arrivals are still expected while the
  process is executing; texture submissions are not expected in background.
- Emit once per no-first-frame episode on the platform thread. Repeated polls
  and pause/resume must not produce duplicate reports for the same episode.
- Cancel on teardown/session replacement and disarm permanently for that session
  once its first frame arrives. A late first frame clears the first-frame reason.
- Keep the current 1.5-second arrival-gap and 6-second submission-gap policies
  after the first frame; preserve their current recovery/dedup behavior.
- Capture coherent metrics before emitting an error, because example recovery
  can immediately tear down/reset the session. Include reason and concise counts
  in the error payload/message; a later getDiagnostics call may show a new session.
- No native automatic restart and no texture swap. The existing example retry
  budget remains bounded; show the first-frame reason when retries are exhausted.

## Implementation sequence and files

1. Native timing policy and tests: extend iOS `FrameLivenessTracker.swift`; extract
   Android timing/counters from `FrameProcessor.kt` into a small tracker. Separate
   real submission timestamps from foreground grace. Use bounded fixed-size rate
   buckets and short synchronization sections, never hold locks while processing
   pixels or sending Flutter events. Test clocks, resets, zero rates, and races.
2. Native integration: both `MetaWearablesDatPlugin` files and their state/error
   handlers. Observe SDK state independently of event-channel subscribers; arm,
   pause, reset, and cancel first-frame tracking with the camera session. Guard
   stale callbacks by session generation. Add the getDiagnostics method branch.
3. iOS route snapshot: read AVAudioSession.currentRoute without changing its
   category, activation, or routing. Keep Android audioRoute explicitly absent.
4. Dart contract: the three existing `lib/` API/channel files, typed diagnostics
   and stall reason, serialization and channel tests. Keep the static facade and
   current error code/source compatibility.
5. Example: a small Provider/ChangeNotifier diagnostics controller and opt-in
   panel on the stream screen. Poll at most once per second while visible and
   foregrounded; prevent overlapping requests, discard stale responses, and
   cancel polling on close/background/dispose. Display received versus submitted
   rates, state, configuration, first-frame wait, and route availability. Allow
   copying the displayed snapshot manually; no automatic uploads or media capture.
   Preserve a failure snapshot where available and show its session ID as stale
   if recovery starts a new session. Correct the retracted 15-FPS settings advice.
6. Documentation: README, public dartdoc, CHANGELOG, AGENTS and consumer agent
   instructions. Explain that counters measure bridge delivery, not screen
   presentation; zero arrivals cannot establish whether SDK/device/transport is
   the cause. Qualify background behavior using the existing known limitation.

## Verification gates

- Native deterministic tests on both platforms, with fake clock/state: no first
  frame before/at/after deadline; duplicate polling; pause/resume; stop-before-
  deadline; late first frame; restart generation; background permission/state;
  normal 2-FPS delivery; received-but-not-submitted; existing midstream stalls.
- Tracker tests: coherent counters, monotonic durations, bounded storage, rates
  decay to zero, read frequency does not change rates, grace is not a real push.
- Add a small Foundation-only Swift test harness for the timing policy if the
  Flutter-linked package cannot be tested directly. CI must execute the production
  policy source and assert nonzero tests, not duplicate it in a test-only model.
  Android tests run through the host Gradle project with verified JUnit reports.
- Dart tests: complete/idle/unsupported snapshot decoding, unknown values,
  optional reason compatibility, method-channel forwarding and error behavior.
- Example tests: opt-in polling, lifecycle cancellation, no overlapping requests,
  stale response rejection, and bounded recovery on the new stall reason.
- Focused formatter/analyzer/tests first, then existing core/mock/example suites,
  iOS SwiftPM and CocoaPods builds, Android build/tests, and publication dry runs.
- Forced silence belongs in fake/test infrastructure, not a production public
  switch. Do not deliberately heat glasses or disrupt real transport to induce it.

## Manual QA after implementation

1. Install release builds on iOS and Android; disconnect the debugger. Start
   streaming a nonsensitive scene, enable diagnostics, and confirm live counters,
   sensible rates, and iOS route types / Android unsupported indication.
2. Stop/start twice. Expect a new session ID and reset counters, with no stale
   timeout/error from the prior session. Verify normal low-FPS streaming too.
3. Disable background streaming, go Home, return: session stays stopped. Enable
   background streaming, repeat Home/lock cycles: inspect arrivals/recovery and
   confirm intentional lack of background texture submission is not misreported.
   Record any recurrence of the existing iOS lock failure without claiming it fixed.
4. Fold/unfold glasses and restart. Confirm terminal cleanup and a fresh snapshot.
5. Close diagnostics while streaming: video continues, polling stops, and no
   videoFramesStream subscription was created solely for diagnostics.
6. Verify first-frame silence and deadline boundaries through the deterministic
   native/integration harness; hardware success alone cannot validate that path.

## Delivery and later PRs

Implement in reviewable commits: timing/tests, native+public API, example/docs.
Target the next minor release (1.1.0 candidate) because this adds public APIs;
do not publish or alter release versions during planning. Both packages remain
versioned together when a release is prepared.

Keep PR #51 separate and rebase it after this lands: integrate per-camera resets
and preserve diagnostics while the parent device session remains connected.
PR #50 can later add audio metrics; no audio route policy from #32 is changed here.
Closing #31/#47 or posting issue replies is a separate maintainer action.

Before coding, confirm the proposed snapshot API, first-frame error semantics,
and 10-second default. Revisit the default if physical QA shows legitimate longer
delays after STREAMING; do not shorten it merely to make tests faster.

## Implementation notes

- A separate locked tracker owns public counts, actual timestamps, bounded rate
  buckets and the first-frame clock on each platform. Existing throttle state
  remains in place. This avoids coupling diagnostic reads to rendering deadlines
  or exposing the watchdog's synthetic foreground timestamps as actual frames.
- The production tracker also owns the tested 1.5s/6s delivery-stall decision.
- Stall events include the captured snapshot so recovery cannot erase evidence.
- Inspection found the example recovery path did not explicitly stop before
  restart and reset its retry budget on STREAMING without frame evidence. Frame
  stalls now explicitly stop and have a separate three-retry limit per manual
  start. Other SDK error recovery keeps its existing policy.
- Publication versions remain 1.0.0; this change is documented as unreleased.

## Automated validation (2026-10-13)

- Core Dart tests: 28 passed; example tests: 14 passed; mock package tests: 4 passed.
- Android native tests: 15 passed, including seven diagnostics tests; JUnit XML
  checked for nonzero cases and no skipped/failed tests.
- Swift production timing harness: 44 assertions passed; CI now runs it.
- Dart MCP analysis: core and example lib/test clean. Formatting and diff checks clean.
- Release builds: Android APK; iOS SwiftPM example; independent CocoaPods host
  including both plugins. No signing/device runtime claims.
- Publication dry runs passed validation; core reported only the expected dirty
  working-tree warning before commit, mock reported zero warnings.
- No running Dart/Flutter app was found by DTD discovery, so no hot reload was
  possible. Native changes require rebuilding the installed app.
- The CocoaPods host used an isolated XDG config directory; the maintainer's
  global SwiftPM setting remains enabled.

Physical checks above remain outstanding. The 10-second first-frame threshold
is a conservative policy; existing intermittent iOS locked-background termination
is not claimed fixed by this diagnostics change.
