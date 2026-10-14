# iOS background recovery: separate backoff, teardown and startup deadlines

Status: implemented in the example; automated checks passed. The 2026-10-14
instrumented device attempt failed automatic recovery because native cleanup
outlasted its separate deadline. Background reliability remains unresolved.
Prepared 2026-10-13 after the
17:08/17:09 Europe/Madrid instrumented lock trials. User requested tracing and a
plan before further behavioral changes.

## Finding

The example starts its 10-second recovery watchdog when it schedules backoff.
On the second captured lock, Dart's nominal 400 ms backoff took 6.843 seconds to
execute under background scheduling. The remaining watchdog time expired while
`stopStreamSession()` was still pending. Recovery cancelled its own intent and
never attempted a replacement. This is independent of the already-fixed burst
counter defect: 36 errors correctly shared one pending recovery and one executed
attempt.

The SDK's device-session `unexpectedError` arrived after that cancellation, while
native teardown was running. It therefore did not initiate abandonment in this
capture. This does not prove that the earlier normal-release device-ended banner
had the same sequence, nor does it identify why the SDK interrupts video.

Native teardown includes a 3-second camera-state wait and a 10-second device-state
wait, plus asynchronous listener cancellation and scheduling. Those are individual
wait bounds, not a guarantee that the complete platform call finishes in 13 wall
seconds. A startup deadline should not cover backoff plus all of that work.

## Agreed implementation

1. **Model recovery phases explicitly in the example provider.** Use backoff,
   stopping, starting and awaiting-streaming phases, scoped to the existing
   recovery generation. Keep actual-attempt counters, the separate per-manual-start
   frame-stall budget and burst coalescing. The existing 10-second deadline starts
   immediately before invoking the replacement start and remains active until
   its future and streaming state confirm success. It does not run during
   backoff or teardown. Never reset it on duplicate errors or state notifications.

2. **Give teardown its own bounded wait and shared completion.** Replace the
   `_isTearingDown` early-return behavior with an in-flight future: concurrent
   callers await the same cleanup instead of assuming it has finished. Use
   a 20-second example teardown deadline, measured from the stop call, to allow
   the native 3+10-second waits and scheduling overhead. On expiry, abandon the
   recovery generation, surface a failure, and do not start another camera while
   the unresolved native stop might still affect it. A late stop completion must
   not schedule a restart. Keep the new-start guard until that completion; this
   may require an app relaunch if the platform never returns. The 20 seconds is
   an application policy choice, not a claim about OS background guarantees.

3. **Preserve authoritative cancellation and scoped results.** Manual Stop,
   background opt-out, disposal and terminal errors cancel every recovery phase.
   Late timers, futures, states and errors cannot affect a later generation.
   Starting/retrying remains app policy; the plugin does not gain automatic
   restart behavior. Keep `unexpectedError` behavior unchanged in this fix: do
   not broadly retry unknown device errors or match the SDK's description text.
   Add phase/deadline labels to existing opt-in trace records so the next capture
   can establish which bound fired without logging sensitive error descriptions.

4. **Reproduce the timing defect before the fix, then validate.** Extend provider
   regression tests with a stop that completes after 11 seconds (longer than the
   old aggregate watchdog but inside the proposed teardown bound); require a
   replacement start and streaming completion. Cover stalled teardown expiry,
   late completion, shared teardown callers, unresolved startup, duplicate errors
   not extending deadlines, and cancellation in each phase. Retain all existing
   retry-budget and compatibility tests. Run scoped formatting/analysis and the
   example suite, then rebuild the signed release.

5. **Verify on the actual device in two modes.** With glasses continuously worn
   and connected, enable background streaming, use RAW / medium / 30 FPS, and
   perform two lock/unlock cycles without manual Start/Stop between them. Unlock
   only after the prompt; record actual native lifecycle durations when tracing.
   First use instrumentation to confirm teardown completion precedes the fresh
   start and the correct phase deadline. Then repeat with normal release logging
   disabled. Judge automatic recovery separately from uninterrupted delivery.
   Stop, restore background opt-in off and Agent Access off after testing.

## Acceptance and limitations

- A recovery that spends more than 10 seconds in backoff/teardown can still reach
  the replacement-start phase if teardown finishes within its own bound.
- Hung teardown and hung startup remain bounded separately; timed-out native work
  must never be overlapped by a fresh start, even if it finishes much later.
- Three-attempt limits and frame-stall accounting remain intact. No automatic
  camera revival after explicit stop or background opt-out.
- No change to native frame-stall thresholds, codec, transport or audio routing.
- This fixes demonstrated premature abandonment. It does not promise continuous
  background streaming or explain the SDK/device errors. A device-session error
  that independently ends a healthy session remains a separate investigation.

## Implementation and verification — 2026-10-13

- Recovery now records backoff/stopping/starting/awaiting-streaming phases. The
  20-second cleanup timer and 10-second startup timer begin at their respective
  phase entries; neither includes backoff. Existing opt-in traces include phase
  and deadline length. Repeated error/state events do not reset an active bound.
- Cleanup callers share the actual platform future. A cleanup deadline reports
  the example-only `recoveryTeardownTimeout` error immediately, but Start stays
  disabled until native work settles. Startup expiry also surfaces its failure
  without waiting indefinitely for subsequent cleanup. Late start results share
  any pending cleanup and cannot expose their obsolete texture.
- Background opt-out cancels recovery directly, including while old-session
  subscriptions are detached. Manual Stop shares pending cleanup, and disposal
  prevents completion callbacks from notifying a disposed provider.
- The 11-second cleanup regression failed against the previous implementation
  (recovery was already cancelled), then passed with the change. All 31 recovery
  tests and all 45 example tests passed. Coverage includes hung cleanup/startup,
  late results, shared stop callers, streaming-before-start-completion, missing
  streaming confirmation, duplicate errors and cancellation across phases.
- Scoped Dart MCP analysis reported no errors; formatting and diff checks passed.
  No running Dart debug app/DTD was found, so hot reload was unavailable.
- Signed `flutter build ios --release` passed and produced
  `example/build/ios/iphoneos/Runner.app`. This build has not been installed or
  exercised on the phone yet; the previously restored normal release remains
  the last device-tested build.
- The existing native SDK/device interruption remains unresolved. These checks
  verify example recovery policy; physical lock/unlock reliability must still be
  tested using step 5 with the new build.

## Device follow-up — 2026-10-14

See [the investigation record](ios-locked-stream-investigation.md) for timing and
capture limitations. Build `4a21088` correctly coalesced 40 errors into one
recovery and retained the unresolved-stop guard after its cleanup deadline.
However, native stop completion took about 93.37 seconds, and no replacement
start occurred. The 20-second timer callback itself ran about 43.62 seconds after
teardown began; these timers cannot guarantee wall-clock execution while the app
is backgrounded. No startup deadline was armed in this attempt.

Do not simply increase the cleanup deadline. Before changing behavior again,
instrument entry/exit around the native teardown task, synchronous camera stop,
video-listener cancellation, stream-state wait, listener cancellation, and
device-session stop/wait. Separate scheduling delays from awaited SDK operations
and trace emission overhead. Repeat with stable observation or manual controls,
then compare with an uninstrumented release. Preserve the non-overlap and
explicit-cancellation guards throughout.
