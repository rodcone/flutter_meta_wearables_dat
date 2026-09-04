# Forwarding native logs to Flutter

Status: proposal, not implemented. Written 2026-09-04.

## Problem

Native iOS logs never reach the `flutter run` console, so debugging the plugin's
Swift layer requires building from Xcode, which loses hot reload.

Android is not affected: `flutter run` reads `adb logcat` filtered to the app
pid, so Kotlin `Log.*` output already shows up.

## Root cause (verified against the local Flutter SDK)

`flutter run` picks a log source per device. `IOSDeviceLogSource.unifiedLogging`
is misleadingly named: it means **the Dart VM Service**, not Apple's unified log
(`packages/flutter_tools/lib/src/ios/devices.dart:1904`). It only carries what
the Dart isolate writes.

On Xcode >= 26 with a CoreDevice (iOS 17+ physical device), the source selection is:

```
if (_isCoreDevice) {
  if (xcodeVersion.major >= 26) → primary: devicectlAndLldb, fallback: unifiedLogging
```

Primary-source lines are **not** filtered (`_excludeLog` only dedups against the
fallback). So:

- Swift `print()` → app stdout → lldb → should appear in `flutter run`
- `NSLog()` → routed through `os_log` to the unified log store → not on stdout

The plugin uses `NSLog` at all 35 iOS sites and `print` at zero. That is the
likely cause. Ruled out: no `OS_ACTIVITY_MODE` override in the example scheme.

Residual uncertainty (~30%): `NSLog` historically does mirror to stderr under a
debugger, which is why it appears in Xcode's console. Flutter's lldb forwarding
is new, starts only after attach, and has a known open issue referenced at
`packages/flutter_tools/lib/src/ios/lldb.dart:279`. The broken link may be the
forwarding rather than `NSLog`.

## Step 0 — run this test first

Do not skip to Step 2. `flutter run` the example on a wired iOS 17+ device,
background the app, and check whether this line appears:

```
[MWDAT] lifecycle: app entered background
```

Source: `ios/.../AppLifecycleObserver.swift:111`.

If it appears, the problem is narrower than assumed and Step 1 alone may be the
whole fix.

## Step 1 — centralize logging (do this regardless)

Add a single `MWDATLog` with levels and categories. Replace every direct log
call:

| Target | Sites |
| --- | --- |
| iOS core (`NSLog`) | 35 |
| iOS mock | 0 |
| Android core (`Log.*`) | 48 |
| Android mock (`Log.*`) | 3 |

Then switch the iOS sink from `NSLog` to `os.Logger` with subsystem
`io.rodcone.mwdat` and categories (`lifecycle`, `stream`, `decode`, `route`,
`audio`). The plugin floor is iOS 17.2, so `Logger` (iOS 14+) is available.

Payoff: Console.app and `log show` can filter by subsystem/category instead of
substring-matching `[MWDAT]`. No public API change, no runtime risk.

**Gotcha:** `os_log` redacts interpolated non-static strings as `<private>` by
default. Every diagnostic needs `\(x, privacy: .public)`. `NSLog` had no such
behavior; missing this yields a log full of `<private>`.

If Step 0 came back positive, `MWDATLog` also emits a `print()` under `#if DEBUG`
and the work is done. No channel, no public API.

## Step 2 — event channel (optional, only for the observability angle)

Justified by consumer observability, not by the local debug loop. It lets
consumers route plugin diagnostics into Sentry / Datadog / Crashlytics
breadcrumbs, and gives maintainers something a bug reporter can actually attach.

Design:

- Channel `flutter_meta_wearables_dat/native_logs`, handler `NativeLogStreamHandler`.
- Gate emission on `hasListener` so there is zero cost when nobody subscribes.
  Pattern: `ios/.../VideoFrameStreamHandler.swift:42`.
- Seed on subscribe. Pattern: `ios/.../VideoStreamSizeStreamHandler.swift:17`.
- Payload as a map `{level, category, message, timestampMs}`, not a preformatted
  string, so consumers can filter and route.
- Dart: `MetaWearablesDat.nativeLogStream()`, emission gated on a level
  threshold that defaults to off in release.

### Hazards specific to this codebase

1. **Never `sync` to main.** Logs originate from at least four contexts: the
   `@MainActor` plugin body, `frameQueue` (`MetaWearablesDatPlugin.swift:143`),
   `BackgroundStreamingController.sessionQueue`
   (`BackgroundStreamingController.swift:71`), and VTDecompression callbacks.
   The audio session queue blocks for hundreds of ms; a `sync` hop to main from
   there while main waits on that queue deadlocks. Use `DispatchQueue.main.async`.
2. **Bounded, drop-don't-queue.** Hot sites are already self-limiting (FPS log
   every 30 frames; decode failures capped at <=10 then every 30th, see
   `MetaWearablesDatPlugin.swift:1499`). Cap emission and emit an "N dropped"
   marker rather than growing a queue during a decode stall.
3. **Ring buffer for the subscribe gap, and label the replay.** Dart subscribes
   after `runApp`; native logging starts at `register()`. A bounded ring (~200
   entries) replayed on `onListen` covers that and, more importantly, hot
   restart. Mark replayed entries (`replayed: true`): a synthetic seed in
   `StreamStateStreamHandler.resubscribe()` was once misread as an SDK replay and
   caused a wrong revert (see CLAUDE.md). Do not set that trap again.
4. **Never log from inside the log path**, or a sink failure loops.
5. **Implement on both platforms.** A `nativeLogStream()` that silently yields
   nothing on Android is a worse trap than not having it.

## Also worth doing

Document the zero-code workarounds in the README Troubleshooting section and
`AGENTS.md`. There is currently no native-logging guidance anywhere, which is a
gap for consumers too.

- **Console.app**, live, keeps hot reload: Window > Devices > pick the device,
  filter on `MWDAT`. `flutter run` still owns the app.
- **`log collect`** for post-hoc capture and bug reports:

  ```bash
  log collect --device-name "<device>" --last 5m --output mwdat.logarchive
  log show mwdat.logarchive --predicate 'eventMessage CONTAINS "MWDAT"'
  ```

  Note `log stream` has **no** `--device` flag (only `log collect` does, per
  `man log`), so there is no live CLI tail from a device.

## Sequencing

1. Step 0 test.
2. Step 1 (`MWDATLog` + `os_log`) plus the README/`AGENTS.md` docs.
3. Step 2 only if the observability angle is wanted. Minor version bump.
