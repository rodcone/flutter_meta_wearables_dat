# iOS SDK error detail capture

Approved 2026-10-15: implement investigation-only diagnostics and validate locally;
stop before device installation or testing. No recovery timing/policy changes.

## Plan

1. Preserve bounded SDK error descriptions, origin (error stream versus startup or
   camera-attachment catch), parent session identity and current SDK session state
   in native investigation records. Keep human-readable strings out of recovery
   decisions. Record truncation explicitly; raw descriptions are local diagnostic
   material and must be reviewed before sharing.
2. Attach opt-in device-state/link listeners to the selected session's device.
   Record link, don, hinge, compatibility, battery and thermal snapshots with native
   timestamps and the parent identity. Cancel listeners on replacement/teardown;
   reject callbacks after cancellation. No new polling or timers. An unavailable
   device is explicitly recorded, not treated as disconnected.
3. Set MWDAT.Logging.Level=warning in the built example plist only when the exact
   Dart define MWDAT_INVESTIGATION=true is present. Restore the source plist's
   logging configuration in ordinary builds, including incremental builds.
   Require the existing native launch opt-in for custom trace listeners/events.
4. Exercise opt-out, bounded strings and listener cancellation with host Swift
   checks; test plist flag parsing and instrumented-to-normal restoration. Run
   existing trace/collector checks and build instrumented and normal iOS release
   artifacts locally. Verify their plist contents and signatures. Do not install.

## Evidence and limits

The installed DAT 1.0.0 interface exposes unexpectedError(description: String),
not a typed underlying reason. The plugin already forwards that description to
Dart, but the structured traces previously retained only the error code.
The existing SDK log was retrieved locally; it has no timestamps that correlate
its transport errors with our trial records. Do not attribute those lines to a
specific failure. Keep SDK logs before/after a future trial and use the timestamped
custom events for correlation; missing error text cannot be recovered retroactively.

Meta's replies in issues [301](https://github.com/facebook/meta-wearables-dat-ios/issues/301)
and [332](https://github.com/facebook/meta-wearables-dat-ios/issues/332) explain that
no reason accompanies a device-ended message and recommend link-state evidence.
Issue [231](https://github.com/facebook/meta-wearables-dat-ios/issues/231) suggests
spacing rapid session cycles by at least two seconds. That is a possible future
experiment, not part of this change or a proven fix for our failures.

## Future device procedure (not authorized in this step)

1. Verify build/firmware and glasses readiness. Preserve the existing SDK log.
2. Install the investigation build, launch with the existing trace collector and
   verify preflight. Confirm device snapshot/link events before starting trials.
3. Capture a failed restart with error origin, description and parent identity;
   inspect link/don/hinge transitions around it. Keep the existing recovery policy.
4. Stop streaming and capture the SDK log again from
   Library/Caches/MetaWearablesDAT/Logs/MetaWearablesDAT.log. Do not infer timestamps
   for file lines that lack them or treat an absent warning as proof of absence.
5. Restore the normal build, background streaming off and Agent Access off.

## Implemented record contract

- `deviceErrorReceived` retains its existing name/parent and adds `errorOrigin`
  (`errorStream`), `deviceSessionState`, `sdkDescription`, and (only for the SDK
  unexpected-error case) `unexpectedDescription`. `deviceErrorCaught` carries the
  same fields with origin `ensureSessionStarted` or `addCamera`. A catch can forward
  the same SDK error already seen on the stream; do not count these as independent
  device failures. A missing parent/state is null, not a fabricated identity.
- Each description is at most 1,024 UTF-8 bytes without splitting a Unicode scalar;
  corresponding `...Truncated` booleans distinguish a complete string from a prefix.
  Descriptions are diagnostic text only and may contain SDK-provided identifiers.
- `deviceSnapshot` records link, don, hinge, compatibility, nullable battery and
  thermal state. The initial property reads are not an atomic SDK snapshot;
  subsequent records come from the SDK's device-state listener. `deviceLinkChanged`
  records the separate link callback. `deviceObservationUnavailable` explicitly
  marks missing device lookup; observation retries when the session reaches started.
- Every record uses the existing native monotonic/wall timestamps, sequence cap
  and parent UUID. Times indicate app receipt/read time, not the glasses' clock.
  Cancellation invalidates callbacks synchronously and cancels SDK tokens
  asynchronously without adding an awaited step to recovery. Late records from a
  cancelled observer are suppressed. No device names/IDs or image payloads are added.
- Native listeners/details require the existing launch opt-in. SDK warning file
  logging requires the investigation **build** define independently; launching such
  a build without native tracing does not disable its warning log configuration.
  Ordinary builds restore the original source Logging dictionary, rather than
  retaining a previous investigation build's settings.
- The plist helper lives under `example/ios/scripts`, since top-level maintainer
  scripts are excluded from the published package. The existing Thin Binary phase
  runs it after plist processing and before signing. Source Info.plist is untouched.

## Local verification — 2026-10-15

- New host Swift harness passed disabled/no-listener behavior, state/link events,
  parent/timestamp fields, exact error detail, UTF-8 boundary truncation, null
  metadata, idempotent cancellation, deinit cancellation and late-callback rejection.
  These tests use SDK doubles; real device event delivery is still unverified.
- Existing native trace/sink harness passed; all 13 collector tests passed.
- All four plist-helper tests passed: exact build flag, invalid input, preservation
  of source options, and investigation-to-normal restoration.
- Signed iOS release builds passed against the real DAT 1.0.0 SDK with both
  investigation flags and without them. Inspected the built plist and verified
  signatures for each. The final local artifact is the normal build.
- No Dart code changed, so Dart analysis/tests and hot reload were not needed.
  No iPhone install, launch, stream, settings or Agent Access operation was run.
  Recovery behavior and physical root cause remain unverified by these local checks.

Repeatable local checks:

```sh
sh scripts/test-investigation-device.sh
sh scripts/test-stream-investigation.sh
python3 -m unittest discover -s scripts/tests -p 'test_*.py'
```

## First instrumented device trial — 2026-10-16, approximately 12:41–12:42 CEST

The maintainer authorized one device trial and reported the phone connected,
unlocked, Agent Access enabled and glasses connected; wear confirmation arrived
later and agreed with the captured SDK state. We ran one synthetic foreground
recovery, not a lock/background test. Built and installed `b288676` with both
investigation flags, preserving app data. Native/bridge/Dart preflight passed.

Environment: wired iPhone 17, iOS **27.0.1 (24A446)**, Bluetooth Classic,
RAW / medium / 30 FPS, background streaming enabled. This differs from the earlier
27.0 trials, and SDK warning logging is newly enabled; do not call this a matched
OS/logging comparison. Glasses firmware/Meta AI app versions were not independently
read. SDK snapshots for both baseline and replacement reported connected,
compatible, donned, hinges open, battery 100 and thermal none.

**Outcome: failed replacement, with useful new error evidence.**

- Baseline camera `26E23F55-E822-44FA-B907-179A0A967C7C`, parent
  `EBB0BE02-7A05-409E-A653-15F4051B6E4C`, delivered 670 frames before teardown;
  last watchdog had 621 frames, 23.292 s after the first frame. Preview was visible.
- Trial `1792147321101557-1` triggered one synthetic `videoStreamingError` and one
  automatic recovery attempt. Diagnostics closed before the trigger took effect.
- Device-session cleanup took **109.328 ms**. Cleanup completion to replacement
  native start was **0.910 ms**; no post-cleanup delay was added.
- Replacement parent `87A5AB2C-E7F8-4D2F-87D9-1F5E07AFACF2` emitted an SDK
  `unexpectedError` **94.073 ms** after native start. The new record identifies
  origin `errorStream`, device session state `starting`, and complete SDK/associated
  descriptions **"Session ended by device"** (both truncation flags false).
- The replacement then reported stopping/stopped. The startup catch recorded the
  same description with origin `ensureSessionStarted`; it is not a second failure.
  No replacement camera/texture or first frame was created, and no recovery
  deadline expired. Dart cancelled recovery during starting; the app showed Start.
- Link events/snapshots reported connected and no disconnect, doff, hinge-close or
  thermal change was captured before the failure. These app-observed SDK states
  narrow the evidence; they do not rule out a transport fault that the SDK did not
  report through those listeners. All relevant native snapshots were foreground
  and Dart lifecycle stayed resumed. No further start was attempted.

Capture retained locally under ignored `build/investigations/2026-10-16-sdk-details/`:
`trial/records.jsonl`, `trial/summary.json`, `sdk-before.log`, `sdk-after.log` and
`sdk-delta.log`. Native run `A30DE121-8E69-41EE-8A90-4DEE7E6619E3` has sequences
1–115, Dart run `1792147122211510-1044678926` has 1–19, and bridge run
`B81E41A6-2EE6-45DC-B7C0-E2B4A6249514` has its startup record. Collector ended
`operatorStopped`, startup verified, with no detected gaps, duplicates, out-of-order,
truncation or malformed/rejected records. The missing-tail limitation remains.

The SDK file preserved its entire pre-trial prefix: 148,704 → 614,704 bytes,
5,002 appended lines. Of these, 4,987 were repeated StreamSecurer `No data returned`
warnings and 12 were IORoute zero-byte read warnings. No timestamps identify
whether those lines occurred at startup, normal streaming, deliberate teardown or
failed replacement. They are not proof of cause; warning-volume overhead is also
unmeasured. The timestamped native error record is the decisive new observation.

Cleanup: stopped the owned collector, rebuilt/installed/launched the normal signed
release, verified no Logging override in its built plist, visually checked idle
Start and background streaming off, and restored Agent Access off with menu
verification. No production code or recovery policy changed. Both builds/signatures
and documentation diff checks passed; unchanged automated suites were not rerun.

Interpretation: the new instrumentation works on the physical device and captures
the previously missing description and device state. The foreground restart failure
persists after the iOS update. Across five synthetic trials there are three passes
and two failures under differing OS/logging conditions; this is not a failure-rate
estimate or a fix. A controlled investigation-only two-second post-cleanup-delay
comparison remains a reasonable next plan, not a guaranteed remedy: an earlier
manual start also failed after a gap longer than ten seconds.
