# Richer Device State

Prepared 2026-10-22. Implemented locally on `codex/device-state`, based on main
`64c99f9`. Automated validation is recorded below; physical QA remains pending.

## Outcome and scope

Extend `MetaWearablesDat.deviceStateStream()` with battery, charging, worn/removed,
and hinge readings, alongside thermal state. Include identity and connection
metadata in the same event so consumers can attribute readings and clear them
when they are no longer usable.

Recommend one focused PR: Dart contract, both native handlers, tests, documentation,
and a small example readout. Device state is metadata, not a session capability;
observing it must not start a device session, camera, Motion, audio, or background
service. No new SDK module, permission prompt, or SDK upgrade is required. Existing
Android Bluetooth permission and initialization requirements still apply.

This feature has no functional dependency on the pending Motion work. Develop on
a separate branch from the appropriate current base, reconcile overlapping facade
and example files when integrating, and keep Motion's pending hardware QA separate.
Do not fold this into its existing PR as an unrelated feature.

## Verified baseline before this change

- Dart `DeviceState` currently contains only `thermalLevel`; its constructor,
  equality, and hash code reflect that one field.
- The existing channel is `flutter_meta_wearables_dat/device_state`.
- iOS already uses `Device.addDeviceStateListener`; its handler has monitoring
  and device generations to reject callbacks after asynchronous cancellation.
- Android already collects `Wearables.devicesMetadata[deviceId]` and restarts
  monitoring after initialization and selector changes.
- Both handlers currently send only `thermalLevel` and emit no explicit empty
  snapshot when their selector loses its device.
- The Dart method currently creates a new channel stream on each call. Cache one
  broadcast stream per platform instance, following the Motion implementation,
  so separate callers share one native subscription.
- The example owns the subscription in `StreamSessionProvider`; it stores only
  thermal state, clears that state on active-device loss, and displays it only
  during streaming.
- Inspected the bundled iOS 1.0.1 `MWDATCore` Swift interface and the cached Android
  `mwdat-core:1.0.1` AAR with `javap`. Both expose all proposed physical fields and
  enum cases. This verifies API availability, not physical reporting behavior.

## Public contract

Keep `DeviceState({required this.thermalLevel, ...})` and the existing static
stream method. Add optional named constructor parameters with the defaults below.
Use the existing single package import and platform interface.

| Field | Dart type | Default / meaning |
| --- | --- | --- |
| `thermalLevel` | `ThermalLevel` | Existing required field; wire values remain 0–7. |
| `deviceId` | `String?` | `null` if no monitored device is resolved. Uses the same identifier as `WearableDevice.id`. |
| `linkState` | `WearableLinkState` | `unknown`; reuse the existing enum. |
| `compatibility` | `WearableCompatibility` | `undefined`; reuse the existing enum. |
| `batteryLevel` | `int?` | `null` for unknown; a known reading is a percentage. |
| `chargingState` | `WearableChargingState` | `unknown`, `charging`, `notCharging`. |
| `donState` | `WearableDonState` | `unknown`, `donned` (worn), `doffed` (removed). |
| `hingeState` | `WearableHingeState` | `unknown`, `open`, `closed`. |

Use explicit camel-case string codes for new enums, consistent with existing
wearable metadata types; never serialize native enum ordinals. Missing or future
enum codes map to `unknown` (or `undefined` for compatibility). Keep all existing
thermal codes unchanged. Centralize Dart decoding in `DeviceState.fromMap` and
include every field in value equality, hash code, and diagnostic output.

An old thermal-only event must still decode to its original thermal value, with
defaults for the added fields. A missing connection key must not erase legacy
thermal data. New native handlers perform connection-based invalidation before
emitting their full maps. Older Dart clients ignore the added keys.

Existing constructor calls remain valid. Streams will now emit for changes other
than temperature, and equality will compare the full snapshot; document both.
Apps that implement `DeviceState` as an interface would need the new getters.
Record the feature under Unreleased and determine package versioning at release.

### Battery normalization

| Native value | Dart value |
| --- | --- |
| iOS `nil` | `null`. |
| iOS integer 0–100 | Preserve the value, including a reported zero. |
| Android integer 1–100 | Preserve the value. |
| Android zero | `null`: the SDK cannot distinguish unknown from empty. |
| Out-of-range or malformed value | `null`; do not clamp or invent a percentage. |

This deliberately sacrifices a definite Android 0% display rather than presenting
an unreported battery as empty. Do not infer it from charging state or previous
readings. The example should show “Battery unknown”, not “0%”, for `null`.

## Observation and lifecycle

1. Follow the plugin's existing effective native selector, including its current
   pinning behavior. `deviceId` identifies what was actually observed; changing a
   prospective selection in the example is not itself a native selector change.
2. On the first native listen, seed the current SDK snapshot. If there is no
   resolved device or the SDK is not initialized, emit an empty snapshot:
   `deviceId: null`, unknown link/physical enums, undefined compatibility, and
   null battery. Android keeps the listener pending until initialization restarts
   monitoring. Do not trigger permissions from `onListen`.
3. On selector change, invalidate the previous subscription before attaching the
   next. Clear the previous reading immediately, then emit the new device's
   snapshot. A known ID whose metadata is not yet available may have unknown
   readings; do not reuse values from the previous device.
4. When a snapshot reports a non-connected link, retain its known identity and
   link/compatibility metadata but clear physical values, including thermal. When
   the selector resolves no device, emit the empty snapshot. Handle both event
   orders; no dependency on the separate `activeDeviceStream()` delivery order.
5. Reconnection seeds a new SDK snapshot. This is the latest SDK report, not a
   claim that the sensor has just been sampled. Do not add fabricated timestamps
   or start any previously stopped capability.
6. Cancellation, forced selector restart, unregister, and engine detach must
   invalidate queued deliveries. Retain iOS generation guards and apply equivalent
   subscription/device checks on Android where cancellation alone is insufficient.
   Check the existing unregister and selector-reset hooks during implementation.
7. Cancel native monitoring when the last Dart listener leaves. Relistening starts
   a fresh native subscription and seed. The shared Dart broadcast stream does not
   promise replay to an additional listener joining while another is already
   active; an app provider should retain its latest snapshot for newly built UI.

No polling, keepalive, automatic stop/start, or synthesized capability errors are
part of this feature. Worn and hinge values are observations, not a guarantee that
a session can start. Unknown is distinct from “not worn” or “closed”.

## Implementation map

| Area | Change |
| --- | --- |
| `lib/flutter_meta_wearables_dat.dart` | Add enums and fields, decoding, value semantics, and API documentation. |
| `lib/meta_wearables_dat_method_channel.dart` | Cache the device-state broadcast stream and use the shared decoder. |
| iOS / Android `DeviceStateStreamHandler` | Serialize complete snapshots, normalize battery, clear stale readings, and enforce cancellation/selection boundaries. Reuse metadata enum mappings where practical. |
| Native plugin selector/registration hooks | Make only the changes needed to invalidate/rebind this observer; leave capability ownership unchanged. |
| Example `StreamSessionProvider` | Store the complete snapshot and preserve the existing thermal getter. Notify on any snapshot change; clear on errors, unregister, and observed device loss. |
| Example stream screen | Show a compact device readout before and during streaming. Label the monitored device, use explicit unknown states, retain the thermal warning, and keep existing start/stop policy. |
| Tests and CI | Add focused Dart decoding/channel tests, real handler lifecycle tests on both native sides, and provider/UI tests. Wire native suites into CI. |
| README / CHANGELOG / agent API reference | Explain the expanded event, battery difference, selection semantics, and foreground/background limitations. |

Avoid another example subscription or a provider architecture refactor. The native
`deviceId` must prevent the example from labeling one device's reading as a different
pair selected for a future start. A simple “Monitored device” label is sufficient.
Do not add a one-shot getter, per-device query API, battery history, readiness
predicate, or MockDeviceKit public expansion in this first PR.

## Validation and acceptance

Automated checks can proceed without a phone:

- Dart: preserve the old constructor and thermal-only payload; test all enum
  defaults, malformed optional fields, battery boundaries, complete equality, and
  matching cross-platform fixtures. Android zero normalization belongs in its
  native mapper; Dart must preserve a valid iOS zero.
- Channel: two calls/listeners share one native listen; cancelling one does not
  detach the other; final cancellation and relisten work; errors propagate.
- Native: initial/no-device states, initialization after subscribe, same-device
  replay without duplicate collectors, A→B switching, absent metadata, disconnect
  and reconnect in either callback order, delayed callbacks after cancel/relisten,
  unregister, and engine detach. Exercise the actual handlers, not just copied
  mapping logic. Verify these paths never create or stop a device session.
- Example: battery/charging/don/hinge changes update without a thermal change;
  unknown/disconnected readings clear; the status is visible before camera start;
  prospective device selection never relabels the observed snapshot.
- Run formatting and analysis only for touched Dart scopes, then targeted tests.
  Compile against real Android and iOS 1.0.1 artifacts and run the existing session
  lifecycle checks where selector/registration hooks changed. Native host doubles
  alone do not establish SDK compatibility.

### Manual QA on 2026-10-23 — deferred by the user

Run on iPhone and Pixel with compatible paired glasses, when hardware is available:

1. Open the example with camera and Motion stopped. Confirm available readings and
   device identity appear without camera/microphone prompts or a new session.
   Missing physical fields should remain visibly unknown, not fabricated values.
2. Remove and put on the glasses, then fold and unfold them. Check worn and hinge
   transitions separately; unknown or unsupported reports remain unknown. These
   observations must not trigger an app-side capability start/stop.
3. Place the glasses on charge and remove them. Compare battery approximately with
   Meta AI and check charging when the link remains connected. If charging causes
   disconnection, confirm the readout clears rather than claiming live charging.
4. Power the glasses off, then on. Confirm stale readings clear, the correct device
   repopulates, and camera/Motion do not start automatically. If a second pair is
   available, switch the effective selection and check attribution.
5. Repeat subscription cancel/relisten, then background/foreground the example.
   Confirm fresh observation resumes under the existing app lifecycle policy; do
   not claim continuous background delivery or add a background service for it.

Record model, firmware, platform, and each unsupported/unknown field. Do not drain
the battery to zero, overheat glasses, reset, or re-pair to force edge cases.

## Implementation and automated validation — 2026-10-22

Implemented in the separate `codex/device-state` worktree from main `64c99f9`.
No package version or SDK dependency changed. The existing Motion/lifecycle
worktree was preserved, including its staged diff.

Both native observers now follow registration and the SDK device list as well as
the selector. A missing metadata entry can recover when that list updates, and
removing a device clears its readings even when the selector retains its ID.
Regression coverage also rejects a delayed iOS selector replay after removal.
Android events are round-tripped through Flutter's `StandardMethodCodec` in the
handler tests, including string device identity. iOS disposal is wired to engine
detach; generation checks reject delayed SDK callbacks.

The pre-commit review also found overlap and overflowing labels on the idle
example screen at 320 × 640 with enlarged text. Its readout, instructions, and
controls now share a scrollable layout, and thermal/availability labels wrap.
The additional widget regression checks that the status does not cover the
heading and that the Start control remains reachable by scrolling.

| Check | Result |
| --- | --- |
| Formatting of the 8 changed/new Dart files | Passed; no remaining changes required. |
| Dart MCP analysis of touched plugin and example scopes | Passed, no errors. |
| Full plugin `flutter test` suite | 38 tests passed, including 8 new decoding/channel tests. |
| Full example `flutter test` suite | 17 tests passed, including 6 new provider/widget tests. |
| Android `:flutter_meta_wearables_dat:testDebugUnitTest` | 39 tests passed, including 11 new Device State tests; no failures, errors, or skips. |
| iOS `sh scripts/test-ios-device-state.sh` | 10 scenarios and engine-detach wiring check passed. Compiles the production handler against controllable host SDK fixtures. |
| Existing `sh scripts/test-ios-stream-lifecycle.sh` | Teardown/wiring checks and 15 audio-handler checks passed. |
| Example `flutter build apk --release --no-pub` | Passed against DAT 1.0.1. |
| Example `flutter build ios --release --no-codesign --no-pub` | Passed via SwiftPM against the actual DAT 1.0.1 frameworks; unsigned build only. |
| `git diff --check` | Passed. |

The Android test report gate and iOS host suite are wired into CI; no remote CI
run was triggered. No running Flutter debug app was available for hot reload, and
no app was launched on a device. These checks establish model/channel behavior,
native observation logic, and SDK build compatibility. They do not establish
physical sensor reporting, connection behavior, or background delivery on glasses.
Physical QA remains deferred to 2026-10-23 using the steps above.

## Sources

Checked against Meta's current v1.0 documentation and local SDK 1.0.1 artifacts:

- [Device State guide](https://wearables.developer.meta.com/docs/develop/dat/device-state).
- [iOS DeviceState reference](https://wearables.developer.meta.com/docs/reference/ios_swift/dat/1.0/mwdatcore_devicestate).
- [Android Device reference](https://wearables.developer.meta.com/docs/reference/android/dat/1.0/com_meta_wearable_dat_core_types_device), including the ambiguous zero battery value.
- [ChargingState](https://wearables.developer.meta.com/docs/reference/android/dat/1.0/com_meta_wearable_dat_core_types_chargingstate), [DonState](https://wearables.developer.meta.com/docs/reference/android/dat/1.0/com_meta_wearable_dat_core_types_donstate), and [HingeState](https://wearables.developer.meta.com/docs/reference/android/dat/1.0/com_meta_wearable_dat_core_types_hingestate).
