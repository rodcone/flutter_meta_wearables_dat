# Reliable iOS investigation capture

Prepared 2026-10-14 after the maintainer selected capture repair and disconnected
the iPhone. Implementation is authorized; stop before device installation/testing.

## Evidence and scope

The latest trial captured all 119 native records through `devicectl --console`,
but neither `idevicesyslog` reader captured a Dart record. This establishes a
capture failure, not whether Dart emitted those records or why the relay missed
them. Native cleanup took 107 ms; the replacement device session then failed.
No timeout/retry change is justified. One trace-only diagnostic snapshot took
1.771 seconds; the responsible sub-operation is not isolated.

## Implementation plan

1. Add an example-only iOS method channel that forwards bounded Dart JSON records
   to NSLog, with a native receipt timestamp and bridge run identity. Require
   both the Dart build define and native launch opt-in. Initialize before app
   providers, with a bounded handshake; trace failure must not prevent app use.
   Keep original Dart event timestamps and sequence numbers. Do not await logging
   in stream operations or add a public plugin API. Preserve console logging on
   other platforms. Cap record count and payload size on both sides.
2. Add a single-console collector with explicit device/output arguments. Require
   native, bridge and forwarded Dart startup markers before declaring capture
   ready. Report malformed records, per-source/run sequence gaps, duplicates and
   truncation. Stop on preflight timeout; own and stop only the launched console
   process. Save only tagged structured records. No phone calls during local QA.
3. Exclude audio-route reads from trace-only diagnostics snapshots. Preserve public
   snapshots and frame-stall error diagnostics, and existing audio-route events.
   Keep stream lifecycle, recovery policy, timeouts and audio configuration intact.
4. Add focused Dart, host Swift and Python tests for disabled/failed transport,
   caps, identity/timestamp preservation, readiness and incomplete capture. Run
   relevant existing harnesses/example tests, scoped analysis, and an instrumented
   signed iOS build. Record results and commit locally.
5. Device gate: verify collector readiness and foreground frames, compare a
   foreground restart with a background restart, then compare normal release.
   Record actual lifecycle intervals and restore background streaming/Agent
   Access off afterward. Physical logging/recovery remains unverified until then.

## Measurement limits

Method-channel delivery and console logging add scheduling overhead. Dart event
time and native receipt time have different monotonic origins; use wall time for
approximate correlation and native receipt uptime for delivery ordering. A complete
sequence does not prove an uncaptured trailing record never existed. Startup
readiness proves only that logging is active, not glasses readiness or frame health.

## Next physical test procedure (not run)

1. Reconnect the unlocked iPhone with glasses worn/connected. Verify the device
   UDID, current app build and firmware. Enable Agent Access only if mirroring
   controls are needed. The collector does not install, lock or start the camera.
2. Build the example with the pinned Flutter SDK and
   `flutter build ios --release --dart-define=MWDAT_INVESTIGATION=true`, then
   install that build without deleting app data. From the repository root run:

   ```sh
   python3 scripts/capture_stream_investigation.py \
     --device "$DAT_DEVICE_UDID" --output "$DAT_TRACE_DIRECTORY"
   ```

   Use a new output directory. This terminates/relaunches the example with native
   tracing enabled and captures only tagged structured events. A 30-second
   default preflight requires native `traceStarted`, bridge `bridgeReady`, and
   forwarded Dart `traceStarted` with `sink: native`. A timeout is a failed
   preflight: do not begin the trial. `--preflight-timeout` can change the gate
   duration; it does not change app behavior. Both build and launch opt-ins are
   required for forwarding. On transport failure, Dart falls back to its console,
   which cannot satisfy the forwarding gate.
3. After READY, enable background streaming and start RAW / medium / 30 FPS.
   Check native first-frame/count/rate events and current Dart events before
   proceeding. Keep diagnostics closed during timed observations; avoid a second
   syslog reader or pixel polling. READY alone does not prove a healthy stream.
4. First perform one foreground Stop/Start and verify a fresh camera/session and
   actual arriving frames. Then leave Start/Stop untouched, lock for 30 seconds,
   and unlock only when prompted. Record actual native background duration,
   cleanup spans, Dart phase/deadline events, replacement identity, and whether
   first frames actually arrive. Stop if capture reports invalid/incomplete.
   This comparison is observational; do not change retry policy mid-trial.
5. Stop the stream, turn background streaming off, then Ctrl-C the collector.
   Inspect `summary.json` and retain `records.jsonl`. Missing sequences,
   duplicates, out-of-order records, rejected payloads, multiple runs, or a cap
   marker invalidate the completeness claim. Unexpected console exit is nonzero
   even if startup was verified. The summary cannot detect a missing tail with
   no later sequence number; do not treat it as proof of uninterrupted logging.
6. Rebuild/install/relaunch the normal release without either opt-in. Compare
   foreground/background behavior without trace capture in a separately agreed
   trial. Restore background streaming and Agent Access off afterward.

Dart forwards at most 2,001 records of at most 16 KiB per process run; native
checks those bounds independently. There is no retry queue, per-frame logging,
or awaited trace call in recovery operations. Outstanding channel calls are
bounded by the same total cap. A two-second startup handshake timeout lets app
startup continue if the sink is unavailable. Normal builds send no trace calls.
Native forwarded records preserve Dart `runId`, `seq`, `elapsedUs` and `wallTimeUs`
and add `bridgeRunId` / `nativeReceiptUptimeUs`. Native plugin records retain their
own run/sequence space. Audio route remains available in explicit audio events
and public diagnostics, but not in periodic/lifecycle/cleanup trace snapshots.

## Local verification — 2026-10-14

- All 52 example tests passed, including seven new trace transport tests for
  disabled logging, startup ordering, native opt-out, handshake timeout, missing
  plugin/transport errors, oversized payloads and bounded outstanding calls.
- Scoped Dart analysis and formatting passed. The signed instrumented iOS
  release build succeeded (37.9 MB), including the implicit-engine channel wiring
  and the new Swift sink in the Runner target.
- The standalone Swift sink harness passed opt-out, initialization, payload
  validation, identity/timestamp preservation and independent record-limit checks.
  Existing native trace tests and all 44 diagnostics assertions passed.
- All 13 Python capture tests passed. Fake local console subprocesses verified
  startup gating, timeout/owned-process cleanup, unexpected exit, truncated JSON,
  mid-capture integrity failure and preservation of existing output directories.
  No fixture launched devicectl or contacted a phone. Unrelated output was not
  saved. Feeding the previous real 119-record native log into the parser correctly
  reported a complete native sequence but capture not ready because Dart/bridge
  records were absent.
- Documentation diff checks passed. No device installation, launch, lock,
  mirroring action or physical regression test was performed. The resulting
  app artifact is instrumented; it is not a normal release artifact for delivery.

Status: local work complete; stop here until the iPhone is available. The new
transport's physical reliability and its effect on background scheduling remain
unverified. This change improves capture and its failure detection; it does not
fix or explain the glasses' background interruption or replacement-session error.

## Physical capture smoke test — 2026-10-14, 14:16–14:18 Europe/Madrid

Installed the instrumented build from `33c2fcf` on the wired iPhone, still on
iOS 27.0 (24A437). The user confirmed unlocked/connected/worn readiness. Native,
bridge and forwarded Dart startup markers passed the collector gate immediately.
One foreground Start/Stop cycle used RAW / medium / 30 FPS with background
streaming off. No lock interval, foreground restart comparison or background
recovery attempt was performed in this capture-validation step.

Foreground camera `7D71180C-9359-4BDD-8666-9A3539206F8E` delivered 740 frames,
with 674 texture submissions before stop. Sampled arrival rates were around
27–28.5 FPS; fresh mirror observations showed the preview and subsequent idle
screen. Submitted frames are not a count of displayed frames. Native stop method
duration was 163.999 ms. Dart recorded manual start, state updates, texture
return, manual stop, teardown start and teardown completion. All cleanup spans
paired; no camera/device error or stall was observed in this foreground cycle.

The single collector ended normally on operator stop with native sequence 1–81,
bridge sequence 1, and Dart sequence 1–10 complete: no gaps, duplicates,
out-of-order records, malformed/rejected payloads or truncation. Native run:
`B93046BC-0227-4CFD-ADE8-B2D51D88D806`; bridge run:
`52C99284-FAF8-4DAC-A0A6-B3DACA780C3E`; Dart run:
`1791980165635019-590920177`. Local structured records and summary are retained in
`/var/folders/wg/f2_rmttd7mjg7wxjybfjbz000000gn/T/dat-unified-capture-ydbtyykp/trial/`.
Temporary evidence may be removed by macOS cleanup. No video was recorded.

Outcome: unified forwarding and capture completeness checks are physically
verified for this foreground smoke test. Background delivery/overhead and the
underlying streaming failure remain unverified. The next step is the planned
foreground-versus-background restart comparison; this result does not establish
that recovery is fixed.

Cleanup: the stream stopped and the idle screen was observed. Background
streaming remained off throughout the trial. Stopped the collector, rebuilt and
installed the normal release without the Dart define, launched without native
trace flags, and verified the idle screen again. Restored Agent Access off and
verified its menu status. No implementation changes were made during this test.
