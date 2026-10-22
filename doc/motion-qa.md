# Motion device QA

Status: core physical iOS and Android lifecycle checks completed across 2026-10-21 and 2026-10-22. The first-background Android issue found during QA is fixed and revalidated; see the dated records and remaining limitations below.

Record the phone model/OS, glasses model/firmware, Meta AI app version, DAT release channel, transport, app commit, requested rate, and observed errors for each run. Use a development or beta release channel, register the example app, and ensure Android Bluetooth permissions are granted. Motion itself requires no camera or microphone prompt.

## Standalone Motion

1. Launch the example with the camera stopped. After registration, open **Motion** from the top toolbar. Confirm registration did not automatically prompt for camera or microphone access.
2. Select 10 Hz and tap **Start Motion**. Confirm state reaches `started`, the sample count increases, timestamps advance, and available readings change when you move the glasses gently.
3. Confirm absent readings display **Unavailable** independently and do not prevent other readings or samples from updating.
4. Tap **Stop Motion**. Confirm `stopped` and no further sample count increases after queued events drain. Start again and verify new samples arrive.
5. Repeat at 5 and 60 Hz. Verify the displayed sample count reflects delivery while UI updates remain readable. Requested rates are targets, not guaranteed cadence.

## Camera and Motion together

1. Start Motion first, close the sheet, then use **Start streaming** (or **Enable camera** if necessary) and grant camera permission. Reopen Motion and confirm both camera frames and Motion samples continue.
2. Stop the camera. Confirm Motion keeps receiving samples. Start the camera again and verify it renders using the newly returned texture.
3. With both active, stop Motion. Confirm camera video continues. Restart Motion and verify new samples arrive.
4. Stop both. Then repeat in reverse order: start camera, start Motion, stop Motion, stop camera. Confirm stopping the final capability allows a fresh device session.
5. If two pairs are available, select the other pair while one capability is active and attempt to start the second capability. Confirm the conflict is reported and the original capability stays active. Stop both before switching pairs successfully.

## Background, interruption, and cleanup

1. With background streaming disabled, start Motion alone, send the app to background, then return. Confirm `stoppedForBackground`/`stopped`, no automatic restart, and successful manual restart. Repeat with camera and Motion together.
2. Enable background streaming in **Settings** before starting Motion. Confirm the Android foreground-service notification is shown when notification permission allows it. Background/foreground, then lock/unlock, checking sample progression and any terminal state/errors. Repeat with both capabilities active.
3. Treat interrupted delivery with opt-in as a recorded failure, not an automatic pass: iOS locked-background session termination is an existing limitation. Capture actual timestamps and error codes; a visible last sample alone is not evidence of continuous delivery.
4. While Motion is active, disconnect or power off the glasses. Confirm state/error changes are visible. Reconnect, observe platform behavior, then explicitly stop/start Motion if needed. Verify the UI does not claim a stale sample is live.
5. Close and reopen the Motion sheet while it runs; confirm it continues without duplicate subscriptions. Stop Motion, navigate around, and verify no additional samples or errors are emitted by the stopped capability.
6. Trigger a rejected start, such as unavailable glasses or a different occupied device. Confirm the error remains readable and another attempt is possible after correcting the cause.

Successful compilation, mock channels, or generated samples do not prove these hardware scenarios. Record pass/fail and evidence separately for iOS and Android.


## Physical run — 2026-10-21

- Signed release example installed over the existing app, preserving registration/data.
- Source: `codex/dat-motion`, base `64c99f9` plus the uncommitted Motion implementation.
- Phone: iPhone 17 (iPhone18,3), iOS 27.0.1 (24A446), wired connection.
- Glasses: Meta Ray-Ban Display (accessory reported Meta RB Display); Bluetooth Classic transport. Firmware, Meta AI app version and configured DAT release channel were not independently recorded.
- Camera configuration: RAW, 30 fps, medium resolution. Background opt-in initially off.
- No Android device was connected. Results below apply only to this iOS/glasses combination.

| Scenario | Observed result |
| --- | --- |
| Standalone 10 Hz | Passed: `started`, all four readings present, advancing timestamps and changing readings with camera off. Count 48 to 175 over approximately 12.65 seconds. |
| Stop and restart | Passed: `stopped`, count settled at 176 and remained unchanged until restart; new samples arrived after restart. |
| Standalone 5 Hz | Passed: count 22 at timestamp 309923264000 ns to 105 at 326526627000 ns (approximately 5 Hz). |
| Motion first, then camera | Passed: rendered video and continuing Motion samples. |
| Stop Motion while camera runs | Passed: Motion stopped at count 215; subsequent screenshots showed changing video. |
| Start Motion with camera already running | Passed at 60 Hz. |
| Stop camera while Motion runs | Passed: camera returned to idle while Motion remained `started`, count advanced to 1644. |
| 60 Hz delivery | Passed: count 87 at 490636237200 ns to 1644 at 516725541000 ns (approximately 59.7 Hz). This is a short sampled interval, not a losslessness guarantee. |
| Background opt-in off, both active | Passed: both stopped on background entry; Motion showed `stoppedForBackground` and `stopped`, with last sample labeled as such. Manual restart succeeded. |
| Background opt-in off, Motion alone | Passed: after Home/return, `stoppedForBackground`, `stopped`, count 2209; no automatic restart. |
| Background opt-in on, Motion alone | Passed for a short cycle: `started` before/after; count 14 to 1497 across 24.78 seconds, sample timestamps 598156998000 to 622880051000 ns. Included approximately 16 seconds backgrounded. Aggregate progression is consistent with 60 Hz; no per-sample gap audit was collected. |
| Background opt-in on, both active | Passed for a short cycle: count 3100 to 4558 over 24.33 seconds, timestamps 649624484600 to 673924631600 ns; remained `started` and camera stayed active on return. No per-sample gap audit was collected. |
| Close/reopen Motion sheet | Passed repeatedly: samples continued and the same session count was retained. |

Not established by this run: never-granted camera-permission flow (existing grant retained), independently absent sensor fields (all were present), two-device conflict, Android behavior, long-duration stability, or production release-channel availability. Phone-lock and physical-disconnection checks are recorded separately when completed.

### User-assisted lock/unlock

The user locked the phone and gently moved their head, then unlocked without restarting either capability. Native lifecycle logs bracket background at 15:08:10.280 and foreground at 15:08:31.973 (21.7 seconds). Motion remained `started`: count 11 at timestamp 719586050700 ns before the test, 658 at 784286783800 ns afterward, across approximately 64.6 seconds between screenshots. Aggregate progression is consistent with 10 Hz across the interval; no per-sample gap audit was collected.

**Camera continuity did not pass:** native logs reported SDK frame gaps of 4.6 seconds at 15:08:16.986 and 2.2 seconds at 15:08:23.691 while locked. Frame arrival/submission resumed after foreground without a manual restart. This is a recorded limitation at RAW/30 fps/medium over Bluetooth Classic, not evidence that locked-background video is reliable. No terminal Motion error was displayed.

### User-assisted power-off

The user powered the glasses off with both capabilities active. Native accessory-disconnection logs appeared at 15:09:07; the camera texture was unregistered. Motion showed `stopped`, count 912, timestamp 809686051000 ns, and `unexpectedError: Unexpected device session error: Session ended by device`. The sample heading changed to **Last received sample**, with Start available. This upstream iOS error is surfaced as received rather than mapped to Android's `sessionEndedByDevice` enum.

After the user powered the glasses back on and confirmed reconnection, the app still showed `stopped` with count 912 (no automatic restart). Manual Start succeeded: `started`, fresh samples at 10 Hz, count 7 and timestamp 51222870000 ns. The device clock reset across its reboot as expected for a device-relative timestamp; do not compare it as a wall-clock time across power cycles. Final Stop settled at count 107 and timestamp 61225922000 ns.

### Cleanup and outstanding checks

Both capabilities were stopped. Motion selection was restored to 10 Hz, background opt-in restored to off, camera settings left at RAW/30 fps/medium, and the example left idle. Registration and app data were preserved. No source fixes were needed during this run; only the QA records changed. `git diff --check` passed.

Still pending: Android physical QA, standalone Motion-only lock test, long-duration runs, two-device conflict, rejected start with unavailable glasses, never-granted camera permissions, missing sensor fields, and camera lock testing at lower frame rates or Wi-Fi transport. To reproduce the observed camera limitation, enable background streaming, start RAW/30 fps/medium camera plus 10 Hz Motion over Bluetooth Classic, lock for 20 seconds, unlock without restarting, and inspect native frame-stall logs alongside Motion counts.


## Android device QA preparation — 2026-10-21

No Android device was visible to ADB during this attempt, so installation and hardware checks remain pending. The original compilation-only APK contained placeholder DAT configuration. The example was rebuilt using the existing ignored `example/android/secrets.properties` from the original checkout, without printing its values or committing it. Release build succeeded (69.4 MB); the packaged manifest no longer contains the application ID/client-token placeholders.

Prepared APK: `example/build/app/outputs/flutter-apk/app-release.apk`.
SHA-256: `74868c4abf48b583e67af7e0eb1f649c52b625e7f593a2f22ecb49911b697469`.

Connect and unlock an Android phone, enable USB debugging, authorize this computer, and confirm the glasses are paired in Meta AI on that phone before proceeding. Preserve any existing installation/data; check its signing compatibility before an in-place install. Do not count this preparation as Android device validation.


## Physical Android run — 2026-10-21

- Pixel 8a, Android 17 / API 37; USB connection.
- Installed the prepared release APK with `adb install -r` after verifying that its certificate matches the existing example. Existing registration and app data were retained.
- APK SHA-256: `74868c4abf48b583e67af7e0eb1f649c52b625e7f593a2f22ecb49911b697469`.
- Glasses model/firmware, Meta AI version and transport were not independently recorded at the start of this run.
- Observed live source: `glasses`. At 10 Hz with the camera off, Motion moved from `starting` to `started` and delivered accelerometer and gyroscope values. Magnetometer and orientation were independently `Unavailable`; the other readings continued normally.
- Count 118 at timestamp 192775138000 ns, followed by a successful Stop at count 289 and timestamp 209866391000 ns, gives approximately 10 Hz over that sample interval. The final count remained 289 in the later UI hierarchy read, with `stopped` and **Last received sample** displayed.
- Native SDK logged `SERVICE_NOT_FOUND` followed by `SERVICE_RESTORED` during startup, then **Motion capability activated**. Samples arrived afterward; no terminal Motion error was shown. The root cause of these SDK logs is not established.

The foreground app unexpectedly changed to another app before the rate/restart test. The user confirmed another task is using the Pixel and explicitly requested a pause. Android QA is paused; Motion had already been stopped at count 289, no camera session was started, and the local log capture was stopped without further phone interaction. Rate changes/restart, camera coexistence, background/lock and disconnect/recovery remain pending. These cases are not counted as passes.


### Resumed Android checks — 2026-10-21

After the first pause, the user authorized exclusive Pixel use and the same installed APK was tested further:

- 5 Hz restart passed. Count 221 at 663685825000 ns to 552 at 729872573100 ns is approximately 5 Hz. Motion continued while a camera preview was rendered.
- Stopping Motion at count 628 left the camera rendering changing video.
- Starting Motion while the camera was already streaming passed at 60 Hz: count 58 at 826346395000 ns to 2931 at 874499858000 ns is approximately 59.7 Hz.
- Stopping the camera returned it to idle while Motion remained `started` with count 2931.
- With background opt-in off, Home/return stopped standalone Motion at count 4080 and showed `stoppedForBackground`, with no automatic restart.
- Two subsequent explicit starts were rejected by DAT with `START_ERROR_DEVICE_UNAVAILABLE`; the UI showed `MOTION_ERROR: Failed to create or start device session.` and remained stopped. Availability/recovery was not established before the user requested a stop. No phone actions followed that request; the Mac log capture was ended.

These checks establish both capability start orders and both independent stop orders. Background opt-in, phone lock and physical reconnect remained pending at that point.

## Resumed Pixel QA — 2026-10-22

The installed APK was pulled and its SHA-256 matched the prepared Motion build (`74868c4abf48b583e67af7e0eb1f649c52b625e7f593a2f22ecb49911b697469`). A new app process accepted 10 Hz Motion and delivered samples (count 205, timestamp 187195066000 ns), so the previous unavailable-device condition was no longer present. SDK startup logged bootstrap retries before capability activation; no terminal error was displayed.

A first-launch lifecycle failure was observed: with background opt-in visibly off, the first Home/return cycle left Motion `started` (count 751, timestamp 241795927000 ns) and emitted no foreground-tracker transition. A second Home cycle emitted the expected background stop. A native regression test for engine attachment after the Activity start callback failed on the existing tracker. The tracker was updated to recognize resume as foreground evidence as well; test and device revalidation are recorded below when completed.


### First-background fix and device revalidation

- Fixed `AppForegroundTracker` to recognize `onActivityResumed` as foreground evidence when Flutter attaches after the Activity start callback. Start plus resume remains idempotent through the existing identity set.
- The new missed-start regression failed before the fix. All 48 native tests then passed, including 10 foreground-tracker tests, 18 Motion tests and the existing audio/configuration/permission suites.
- Rebuilt and installed the release example in place, then force-stopped the idle example and cold-launched it for revalidation. New APK SHA-256: `e55fe83e46c049814a8fc09b319099c0e17ee7fd4dd44e06fad57954e941ed39`.
- **First-background shutdown passed on the corrected APK:** 10 Hz Motion reached `started` (count 144, timestamp 706930904000 ns). The first Home transition logged background/stop at 16:42:08.336. Returning showed `stoppedForBackground`, `stopped`, count 264 and timestamp 718930422000 ns. No automatic restart occurred.
- **Manual restart passed:** `started`, count 162 at 767271381000 ns. Explicit Stop then settled at count 327 and timestamp 783773715000 ns.
- Initial/final camera configuration for this run: RAW, 30 fps, medium (504 x 896). Background opt-in was initially off. Meta AI Android version: 295.0.0.37.164 (969502538).
- Enabled background streaming before starting the next Motion session. Android reported `BackgroundStreamingService` as foreground (`connectedDevice` type), an ongoing service notification on `mwdat_example.streaming`, and an acquired partial `MWDAT::StreamingWakeLock`.
- **Standalone background opt-in passed for a short cycle:** count 138 at 893639470000 ns before Home; count 586 at 938439570000 ns after return (44.46 seconds between screenshots, approximately 29 seconds backgrounded). State remained `started`. Aggregate progression was consistent with 10 Hz; no per-sample gap audit was collected.
- **Standalone Motion lock/unlock passed for the observed interval:** user locked/unlocked the phone, with native background at 16:46:12.163 and foreground at 16:46:38.124 (25.96 seconds). Motion remained `started`, count 1302 and timestamp 1010026784000 ns afterward, versus count 586 before the user-assisted interval. Aggregate progression remained approximately 10 Hz; no terminal error was displayed.
- Camera was then started alongside Motion on the corrected APK and rendered a live preview. Motion continued at 10 Hz (count 1952, timestamp 1075127264200 ns) before the combined lock test.


### Combined Motion/camera lock test on the corrected APK

The user locked/unlocked the Pixel with camera and 10 Hz Motion active and background opt-in enabled. Native lifecycle logs show background at 16:48:24.400 and foreground at 16:49:01.730 (37.33 seconds). Motion remained `started`, count 1952 at 1075127264200 ns before the user-assisted interval and 2758 at 1155926598400 ns afterward (80.21 seconds between screenshots, approximately 10 Hz aggregate progression).

Camera arrival counters continued throughout the lock: 1537 at 16:48:23.586, 1586 at 16:48:24.802, 2031 at 16:48:39.405, 2361 at 16:48:50.285 and 2701 at 16:49:01.410. No frame-stall warning was logged during this interval. The app retained its running camera controls after unlock. These counters establish ongoing SDK delivery for this short run; they do not prove every sample/frame was delivered or displayed. The configured request was RAW/30 fps/medium; the SDK also logged a later 360 x 640 decoded frame size.


### User-assisted Android power-off

With both capabilities active, the user powered the glasses fully off. Camera texture 0 was unregistered at 16:55:16.664; Motion stop/termination followed at 16:55:16.675. The observed Motion UI showed `stopped`, `deviceDisconnected: The Motion device disconnected.`, count 6320 and timestamp 1512427445000 ns, with **Last received sample** and Start available. SDK GATT reconnect attempts while the glasses remained off did not restart the capability. Manual recovery after reconnect is checked separately below.


### Android reconnect recovery and final shutdown

After the user confirmed reconnection, Motion still showed `stopped` with count 6320 and the historical sample. The SDK had reported an active device again at 17:00:26.243, but the first manual start was rejected at 17:00:57.682 with `START_ERROR_DEVICE_UNAVAILABLE`. No samples were shown as live. After the user unfolded and wore the glasses, a second manual start succeeded without restarting/re-pairing/reinstalling the app: Motion was activated at 17:03:16.377, reached `started`, and showed count 170 at timestamp 207289378000 ns. Stop later settled at count 550 and timestamp 245287118000 ns. Wearing and successful start were correlated in this run; the exact upstream readiness condition was not independently established.

Background opt-in was restored to off. Camera was then started first and rendered fresh video after the power cycle; Motion was added successfully (count 11 at timestamp 357966329200 ns). Home/return stopped both capabilities. Motion showed `stoppedForBackground`, `stopped`, count 174 and timestamp 374266208600 ns; closing the sheet showed the camera's idle placeholder. Android service inspection confirmed no `BackgroundStreamingService` and no acquired `MWDAT::StreamingWakeLock` remained. The example was left idle with Motion set to 10 Hz, background opt-in off, and the original RAW/30 fps/medium camera settings retained. The Mac log capture was ended.

### Result and remaining limits

Core Pixel checks now cover standalone Motion at 5/10/60 Hz, restart/rate selection, independent nullable fields, both camera/Motion start orders and stop orders, first-background shutdown with opt-in off, combined shutdown with opt-in off, standalone background and lock with opt-in on, combined camera/Motion lock with ongoing SDK frame arrival, power-off cleanup, rejected-start UI and successful manual recovery after reconnect. The new first-background lifecycle fix was checked on the corrected release APK; the 5/60 Hz and independent-stop evidence predates that tracker-only change.

Still unverified: long-duration stability, two-device conflicts on hardware, never-granted permission onboarding, production DAT release-channel availability, and Android delivery of magnetometer/orientation on hardware that supports those fields. The exact Android glasses model/firmware and transport were not independently recorded. Successful short runs do not establish lossless delivery. The earlier iOS locked-camera stalls remain a separate recorded limitation.

To reproduce the fixed Android first-background case manually:

1. With background opt-in off and both capabilities stopped, force-stop/relaunch the example and start Motion at 10 Hz.
2. Press Home, wait at least two seconds, then return. Confirm `stoppedForBackground`, `stopped`, a stable last sample count and no automatic restart.
3. Manually start Motion again. Confirm fresh samples arrive. If DAT reports unavailable glasses, unfold/wear them and retry after they are ready.

All 48 Android native tests passed after the fix. The required audio execution gate confirmed its 20 tests ran successfully, and `git diff --check` passed. No Dart `lib/` changes were made during this QA fix, so no hot reload was applicable; the native change was rebuilt and installed. This records the state at the end of hardware QA, before PR preparation; no release was performed.
