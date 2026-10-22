# DAT Motion implementation

Target SDK: existing DAT 1.0.1 on iOS and Android. Plugin release version remains unchanged; the feature is unreleased.

## Scope and decisions

- Expose typed Motion configuration, samples, state, and errors through the static `MetaWearablesDat` facade and existing platform architecture.
- Support Motion independently of camera permission and camera streaming.
- Camera and Motion share the same device session. Either may start first, stopping one preserves the other, and stopping the last ends the session. Reject a different device while the session is occupied.
- Preserve native timestamp precision and nullable sensor fields. Forward source and error strings with unknown fallbacks. Support Android's paused Motion state without inventing an iOS paused state.
- Add the iOS `MWDATMotion` framework and Android `mwdat-motion` at 1.0.1. Keep SwiftPM, CocoaPods, architecture thinning, and packaging consistent.
- Use the existing background opt-in. Cover shutdown, disconnect, detach, start/stop overlap, and stale callback delivery without automatic plugin retries.
- Add an example panel independent of the camera, with full-rate sample consumption and at most 10 sample-triggered UI rebuilds per second. Request camera permission only for camera actions.

Motion is an upstream beta capability restricted to development and beta release channels. This change does not establish production-channel support. Native coordinate components are forwarded unchanged; the bridge does not define a new coordinate system.

## Validation

Run focused Dart model/channel tests, example provider/widget tests, formatting and analysis, native lifecycle/serialization tests, Android build checks, and iOS compilation checks for the linked framework. Validate framework architecture and package size after vendoring.

Physical-device checks are listed in [Motion QA](../motion-qa.md). Automated tests and successful builds do not establish real sensor delivery, coexistence, or background reliability. Record hardware results only when actually observed.

### Verified on 2026-10-21

- Flutter 3.47.5 / Dart 3.13.4: 50 core-plugin tests and 18 example tests passed. The 20 focused Motion tests passed again after test-lint cleanup. Static analysis of both packages' changed source and test scopes is clean; formatting and `git diff --check` pass.
- Android: 46 native tests passed, including 18 new Motion tests; the existing audio execution gate passed. The release example APK built successfully. No device installation was performed.
- iOS: the release example built through SwiftPM, and a temporary consumer built through CocoaPods. Both were unsigned device builds. The temporary CocoaPods consumer used isolated Flutter settings; the user's global SwiftPM setting remains enabled.
- Host Swift tests passed for Motion serialization, nullable readings, 64-bit timestamps, stale callbacks, subscription cancellation, state replay, shared device selection, independent stop admission, and the existing camera/audio teardown behavior. SDK doubles in the Motion harness do not prove hardware timing.
- The package dry-run includes `MWDATMotion.xcframework` and reports a 13 MB compressed archive. Its only validation warning is the expected uncommitted working tree.
- No running debug app was available for hot reload. A subsequent signed release was installed on a physical iPhone 17: standalone Motion at 5/10/60 Hz, camera coexistence and independent stops, and short background/foreground cycles passed. Detailed evidence and remaining limitations are in [Motion QA](../motion-qa.md). Android hardware remains unverified. The optional mock companion has no new Motion-feed API.

Implementation is on `codex/dat-motion`, based on `origin/main` at `64c99f9`, in an isolated worktree. The original diagnostics checkout was preserved. Hardware QA preceded PR preparation; no tag or publication is part of this change.

## References

- [Meta Motion guide](https://wearables.developer.meta.com/docs/develop/dat/motion/)
- Shipped iOS `MWDATMotion.swiftinterface` from SDK tag 1.0.1.
- Published Android `com.meta.wearable:mwdat-motion:1.0.1` artifact.


### Additional validation on 2026-10-22

Physical Pixel QA found a first-launch lifecycle gap: with background opt-in off, a missed Activity start callback could leave Motion running through the first Home transition. The tracker now treats resume as foreground evidence too. The regression test failed before the fix; all 48 Android native tests passed afterward. A rebuilt release APK was installed without clearing app data, and the first-background stop plus manual restart passed on the Pixel. Standalone Motion also passed short background and user-assisted lock/unlock intervals with opt-in enabled. See the dated [Motion QA record](../motion-qa.md) for exact evidence and remaining checks.


The final corrected-APK Pixel run also passed standalone and combined lock/unlock with background opt-in, disconnect cleanup, and manual Motion/camera recovery after reconnect. DAT initially rejected the post-reconnect start as device unavailable; retry after the user wore the glasses succeeded, so this is recorded as a readiness condition observed during QA, not a claimed SDK fix. Both-active background shutdown with opt-in off passed. The example was left idle with background opt-in off; its service and wake lock were absent. The required Android audio execution gate and final whitespace check passed. Long-duration, two-device, onboarding, and additional-hardware checks remain outside this run's evidence.


### PR preparation review on 2026-10-22

Reviewed the additive Dart API/channel contracts, native sample serialization and listener lifetimes, independent capability stop paths, shared parent ownership, device selection, example registration flow and package/framework wiring. No remaining source blockers were identified. Kept the feature under Unreleased with package versions unchanged; versioning/publication remains a separate release step.

Fresh validation passed: 50 core Flutter tests and 18 example tests, clean Dart analysis for both packages, formatting, all 48 Android native tests with zero skips/failures, the 20-test Android audio execution gate, Swift Motion/shared-session/stream-teardown tests and 15 iOS audio checks. One cascade lint in a new example test was corrected and its six-test suite reran successfully. No Dart runtime behavior changed during PR preparation, and no running debug/DTD instance was available for hot reload. Package dry-run included the Motion framework and reported a 13 MB archive; its only warning before staging was the dirty working tree. Device evidence remains scoped to the QA record, including the iOS lock-camera limitation and unverified longer/multi-device/onboarding scenarios.
