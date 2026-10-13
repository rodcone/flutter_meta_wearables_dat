# iOS background recovery: separate backoff, teardown and startup deadlines

Status: proposed implementation; not applied. Prepared 2026-10-13 after the
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

## Proposed implementation

1. **Model recovery phases explicitly in the example provider.** Use backoff,
   stopping, starting and awaiting-streaming phases, scoped to the existing
   recovery generation. Keep actual-attempt counters, the separate per-manual-start
   frame-stall budget and burst coalescing. The existing 10-second deadline starts
   immediately before invoking the replacement start and remains active until
   its future and streaming state confirm success. It does not run during
   backoff or teardown. Never reset it on duplicate errors or state notifications.

2. **Give teardown its own bounded wait and shared completion.** Replace the
   `_isTearingDown` early-return behavior with an in-flight future: concurrent
   callers await the same cleanup instead of assuming it has finished. Propose
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
