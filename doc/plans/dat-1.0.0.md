# DAT 1.0.0 migration plan

Status: implemented; local verification and all 14 CI checks passed at b40391f; two independent review rounds completed; PR #48 open. DAT 0.9.0 → 1.0.0; both Flutter packages 0.9.2 → 0.10.0. Partial hardware QA is recorded below. Intermittent iOS lock/background session termination remains unresolved; no merge, tag, or publication has occurred.

Remaining hardware tests are deferred at the maintainer's request: power-off recovery, fresh registration, multi-device switching, mock teardown/permission checks, and Android hardware QA. Deferral does not mark them passed. The initial upgrade-in-place startup failure cleared after reinstalling, but its cause remains unknown.

## Evidence

- iOS upstream release commit `7070df1`, previous `225f64f`; Android release `61d2ca3`, previous `81dfb51` (Android has no release tags).
- iOS `1.0.0` tag frameworks staged in `/tmp/dat-1.0.0-inspection/ios`; deployment target remains 17.2.
- All three Android POMs and AARs returned HTTP 200 from Maven Central. Group/artifact names unchanged.
- Generated iOS interfaces include documentation: Core 1676, Camera 1008, MockDevice 1015 doc-comment lines; increases match the added surface.
- Old/new Swift interfaces and Android `javap -public` dumps staged in `/tmp/dat-1.0.0-inspection`.
- CameraAccess sample and camera-streaming/session-lifecycle/dat-conventions skill diffs inspected on both platforms.

## Changelog triage

Each upstream bullet is represented below. New experimental capabilities are deferred under the standing camera-only compatibility scope, not declared impossible.

### IOS

| Category | Upstream item | Relevance and action |
| --- | --- | --- |
| Added | Muse Code support. Use your Muse Code tools to build with DAT. | Not relevant to plugin runtime; no action. |
| Added | [Experimental] **Inputs.** The new `MWDATInputs` module adds `Inputs`, reporting glasses input to a session as `InputEvent` values, described by `InputSource`, `NavDirection`, `DragAction`, `ButtonType` and `CapturePressType`, with `InputsConfiguration`, `InputsState` and `InputsError`. | Optional new capability; defer new Dart APIs and dependencies in this compatibility update. |
| Added | [Experimental] **Motion.** The new `MWDATMotion` module adds `Motion`, streaming device orientation and movement as `MotionSample` values built from `Vector3` and `Quaternion`, configured with `MotionConfiguration`, `MotionSamplingRate` and `MotionSource`, with `MotionState` and `MotionError`. | Optional new capability; defer new Dart APIs and dependencies in this compatibility update. |
| Added | [Experimental] **Speech.** The new `MWDATSpeech` module adds `Speech`, delivering on-device transcription as `TranscriptionResult`, reporting `SpeechState` and `SpeechError`. Requires `Permission.microphone`. | Optional new capability; defer new Dart APIs and dependencies in this compatibility update. |
| Added | [Experimental] **Voice invocations.** In `MWDATCore`, `VoiceInvocationsStream` delivers `VoiceInvocation` requests to a session, starting with `LaunchApp`, answered through `ResponseHandle`. `VoiceInvocationError` reports failures. | Optional new capability; defer new Dart APIs and dependencies in this compatibility update. |
| Added | [Experimental] **Photo capture.** In `MWDATCamera`, `Camera.photo` captures standalone high-quality photos, delivering `PhotoCaptureData` and reporting `PhotoTransferProgress` while the image transfers. `PhotoResolution` and `PhotoQuality` control capture; `PhotoState` and `PhotoError` report lifecycle and failures. | Optional new capability; defer new Dart APIs and dependencies in this compatibility update. |
| Added | [Experimental] **Camera audio streaming.** In `MWDATCamera`, `StreamConfiguration.audioCodec` and `Stream.audioFramePublisher` deliver `AudioFrame` data alongside video, described by `AudioCodec` and `AudioSampleRate`. | Optional new capability; defer new Dart APIs and dependencies in this compatibility update. |
| Added | [API] **Device state on `Device`.** New accessors `batteryLevel` (`Int?`), `chargingState` (`ChargingState`), `donState` (`DonState`), `hingeState` (`HingeState`) and `thermalLevel` (`ThermalLevel`). | Relevant: migrate thermal observation to Device listeners/metadata; retain thermal-only Dart contract, defer additional state fields. |
| Added | [API] `Device.addDeviceStateListener((DeviceState) -> Void)` delivers the device's `DeviceState` immediately and on every change. | Relevant: migrate thermal observation to Device listeners/metadata; retain thermal-only Dart contract, defer additional state fields. |
| Added | [API] `DeviceSession.device: Device?` — the live device snapshot for the session's device. | Relevant: migrate thermal observation to Device listeners/metadata; retain thermal-only Dart contract, defer additional state fields. |
| Added | [API] `Wearables.handleUrl(_:onRegistrationRequest:)`, the request-scoped `RegistrationRequest.continueRegistration()` / `cancelRegistration()` flow and `RegistrationRequestError`, for registration initiated by Meta AI app. | Optional Meta-AI-initiated registration; defer request/consent APIs, preserve current app-initiated flow and document the limitation. |
| Added | [API] `DeviceSessionError.insufficientSDKVersion`: A terminal error indicating that developers must release a newer version of their app built with the current SDK. | Relevant: forward insufficientSDKVersion and treat it as terminal in the example. |
| Added | [API] `DeviceSessionError.dwaOutOfStuRange`: Adds a nonblocking compatibility warning. Apps can continue normally and may show a rate-limited update suggestion. | Relevant: forward dwaOutOfStuRange as a nonblocking warning; do not restart/stop the stream. |
| Added | [API] Display buttons support `ActionRole.primary`; the first primary action receives focus when content first renders. | Out of scope under the skill; no display API or mock-display exposure. |
| Added | [Feature] **Mock display preview.** `GlassesModel.metaRayBanDisplay` and `MockDisplayKit` render the Display session locally on the phone, with `createPreviewView()` for the preview view and `sendClick(identifier:)` for click injection. Pairing uses the existing `pairGlasses` API. | Out of scope under the skill; no display API or mock-display exposure. |
| Added | [Feature] MockDeviceKit gains `MockCameraCaptureKit`, `MockInputKit`, `MockMotionKit`, `MockSpeechKit` and `MockVoiceInvocationKit` so the new capabilities can be exercised without physical glasses, reachable from `MockGlassesServices`. Adds `MockDevice.setBatteryLevel(_:)`, `setChargingState(_:)` and `setThermalLevel(_:)` for simulating device state, and `startTestServer(port:)` with `MockDeviceKitError.testServerUnavailable`. | Mixed: adopt updated mock binary; defer new mock controls and experimental capability APIs. |
| Added | [API] `MockDeviceKit.disable()` and `MockDeviceKit.unpairDevice(_:)` gain `async` overloads that return once teardown completes, giving tests a deterministic teardown point. | Relevant: await iOS mock teardown so existing Futures complete after cleanup. |
| Added | [API] `MockDeviceTestClient.sendLaunchAppAction(deviceId:)` and `sendIncompleteAction(deviceId:)` drive Hey Meta voice invocations from the UI test process. | Not relevant: test-client framework is not vendored; no action. |
| Changed | [API] `DeviceState` gained `linkState`, `compatibility`, `batteryLevel`, `chargingState`, `donState` and `hingeState` alongside the existing `thermalLevel`. | Relevant: migrate thermal observation to Device listeners/metadata; retain thermal-only Dart contract, defer additional state fields. |
| Changed | [API] `StreamError` replaces `.thermalCritical`, `.thermalEmergency`, `.peakPowerShutdown` and `.batteryCritical` with `.thermalHot`, `.peakPowerLimit` and `.batteryLow`, matching the case names already used on Android. Map `.thermalCritical` and `.thermalEmergency` to `.thermalHot`, `.peakPowerShutdown` to `.peakPowerLimit`, and `.batteryCritical` to `.batteryLow`. Adds `.audioStreamingError` for audio failures. | Relevant: map renamed iOS cases to existing Dart codes; add audioStreamingError mapping defensively; update docs. |
| Changed | [API] `NavigationError` now conforms to `DatError` rather than `Error`. | Already covered by existing typed error mapping; verify compilation. |
| Removed | [API] `Wearables.deviceStateStream(for:)` — device state now lives on `Device`. Use `deviceForIdentifier(_:)` and observe `Device.addDeviceStateListener(_:)`, reading the delivered `DeviceState`. | Relevant: migrate thermal observation to Device listeners/metadata; retain thermal-only Dart contract, defer additional state fields. |
| Fixed | No entries in upstream 1.0.0 changelog. | No action. |

### ANDROID

| Category | Upstream item | Relevance and action |
| --- | --- | --- |
| Added | Muse Code support. Use your Muse Code tools to build with DAT. | Not relevant to plugin runtime; no action. |
| Added | [Experimental] **Inputs.** The new `mwdat-inputs` module adds `Inputs`, reporting glasses input to a session as `InputEvent` values, described by `InputSource`, `NavDirection`, `DragAction`, `ButtonType` and `CapturePressType`, with `InputsConfiguration`, `InputsState` and `InputsError`. | Optional new capability; defer new Dart APIs and dependencies in this compatibility update. |
| Added | [Experimental] **Motion.** The new `mwdat-motion` module adds `Motion`, streaming device orientation and movement as `MotionSample` values built from `Vector3` and `Quaternion`, configured with `MotionConfiguration`, `MotionSamplingRate` and `MotionSource`, with `MotionState` and `MotionError`. | Optional new capability; defer new Dart APIs and dependencies in this compatibility update. |
| Added | [Experimental] **Speech.** The new `mwdat-speech` module adds `Speech`, delivering on-device transcription as `TranscriptionResult`, configured with `SpeechConfiguration` and reporting `SpeechState` and `SpeechError`. Requires `Permission.MICROPHONE`. | Optional new capability; defer new Dart APIs and dependencies in this compatibility update. |
| Added | [Experimental] **Voice invocations.** In `mwdat-core`, `VoiceInvocationsStream` delivers `VoiceInvocation` requests to a session, starting with `LaunchApp`, answered through `ResponseHandle`. `SessionState` and `VoiceInvocationError` report lifecycle and failures. | Optional new capability; defer new Dart APIs and dependencies in this compatibility update. |
| Added | [Experimental] **Photo capture.** In `mwdat-camera`, `Camera.photo` captures standalone high-quality photos, delivering `PhotoCaptureData` and reporting `PhotoTransferProgress` while the image transfers. `PhotoConfiguration`, `PhotoResolution` and `PhotoQuality` control capture; `PhotoState` and `PhotoError` report lifecycle and failures. | Optional new capability; defer new Dart APIs and dependencies in this compatibility update. |
| Added | [Experimental] **Camera audio streaming.** In `mwdat-camera`, `StreamConfiguration.audioCodec` and `Stream.audioStream` deliver `AudioFrame` data alongside video, described by `AudioCodec` and `AudioSampleRate`. | Optional new capability; defer new Dart APIs and dependencies in this compatibility update. |
| Added | [API] **Device state on `Device`.** New accessors `batteryLevel` (`Int`), `chargingState` (`ChargingState`), `donState` (`DonState`), `hingeState` (`HingeState`) and `thermalLevel` (`ThermalLevel`), observable via `Wearables.devicesMetadata[id]`. | Relevant: migrate thermal observation to Device listeners/metadata; retain thermal-only Dart contract, defer additional state fields. |
| Added | [API] `DeviceSession.deviceInfo: StateFlow<Device>` — the in-session device snapshot with live state updates. | Relevant: migrate thermal observation to Device listeners/metadata; retain thermal-only Dart contract, defer additional state fields. |
| Added | [API] `Wearables.handleIntent(intent, onRegistrationRequest)`, `RegistrationRequest` and `RegistrationRequestError` for accepting or cancelling registration requests initiated by Meta AI app. | Optional Meta-AI-initiated registration; defer request/consent APIs, preserve current app-initiated flow and document the limitation. |
| Added | [API] `DeviceSessionError.INSUFFICIENT_SDK_VERSION`: A terminal error indicating that developers must release a newer version of their app built with the current SDK. | Relevant: forward insufficientSDKVersion and treat it as terminal in the example. |
| Added | [API] `DeviceSessionError.DWA_OUT_OF_STU_RANGE`: Adds a nonblocking compatibility warning. Apps can continue normally and may show a rate-limited update suggestion. | Relevant: forward dwaOutOfStuRange as a nonblocking warning; do not restart/stop the stream. |
| Added | [API] Display buttons support `ActionRole.PRIMARY`; the first primary action receives focus when content first renders. | Out of scope under the skill; no display API or mock-display exposure. |
| Added | [Feature] **Mock display preview.** `GlassesModel.META_RAYBAN_DISPLAY` and `MockDisplayKit` render the Display session locally on the phone, with `createPreviewView(context)` for the preview view and `sendClick(identifier)` for click injection. Pairing uses the existing `pairGlasses` API. | Out of scope under the skill; no display API or mock-display exposure. |
| Added | [Feature] MockDeviceKit gains `MockCameraCaptureKit`, `MockInputKit`, `MockMotionKit`, `MockSpeechKit` and `MockVoiceInvocationKit` so the new capabilities can be exercised without physical glasses, reachable from `MockGlassesServices`. Adds `MockDevice.setBatteryLevel(Int)`, `setChargingState(ChargingState)` and `setThermalLevel(ThermalLevel)` for simulating device state, and `startTestServer(port)` / `stopTestServer()` / `simulateRegistrationOutcome(Boolean)` with `MockDeviceKitError.TestServerUnavailable`. | Mixed: adopt updated mock binary; defer new mock controls and experimental capability APIs. |
| Changed | [API] `Device` gained `thermalLevel`, `batteryLevel`, `chargingState`, `donState` and `hingeState` properties. | Relevant: migrate thermal observation to Device listeners/metadata; retain thermal-only Dart contract, defer additional state fields. |
| Removed | [API] `Wearables.getDeviceState(deviceIdentifier): StateFlow<DeviceState>` and the `DeviceState` type — device state now lives on `Device`. Observe `Wearables.devicesMetadata[id]` and read `device.thermalLevel` / `device.batteryLevel` / etc. | Relevant: migrate thermal observation to Device listeners/metadata; retain thermal-only Dart contract, defer additional state fields. |
| Fixed | MockDeviceKit stream-start rejections now report why they failed instead of failing without detail. A `setCameraFeed(CameraFacing)` feed blocked by a missing runtime `android.permission.CAMERA` grant now names that permission. | Relevant upstream fix: adopt binary; check missing-camera-permission behavior in mock QA. |

## Implementation sequence

1. **Native dependencies and snapshots.** Replace all three verified iOS xcframeworks, thin simulator slices, and preserve reference headers in `doc/ios/*.swift`. Set DAT 1.0.0 in both Android build.gradle files. Keep iOS 17.2 / Android API 29 unless binary/build evidence requires otherwise.
2. **Thermal observation.** In the iOS `DeviceStateStreamHandler`, replace removed `deviceStateStream(for:)` with `Device.addDeviceStateListener`, cancel tokens on device changes/cancel/restart, and prevent stale callbacks reaching the current sink. On Android observe `Wearables.devicesMetadata[id]`; remove the deleted native DeviceState import. Preserve Dart payload and selected-device behavior.
3. **Errors.** Update iOS StreamError cases while retaining existing Dart codes used on Android: thermalHot → thermalCritical, batteryLow → batteryCritical, peakPowerLimit → peakPowerShutdown. Use SDK descriptions rather than asserting a new severity from renamed cases. Session-level emergency remains deviceThermalEmergency. Map insufficientSDKVersion and dwaOutOfStuRange on both platforms, checking the latter before Android's generic DWA match. Document warning versus terminal handling.
4. **Mock teardown.** Await the new iOS async disable/unpair overloads; preserve existing Dart signatures.
5. **Example.** Handle insufficientSDKVersion as terminal; show the compatibility warning without clearing textures or cancelling recovery. Remove legacy GitHub repository/token plumbing from Android settings. Keep app-initiated registration and current streaming/photo controls.
6. **Versions/docs/CI.** Bump both pubspecs and podspecs to 0.10.0; both changelogs; update install snippets and DAT version references. Sweep README, llms.txt, AGENTS.md, consumer agent rules, CLAUDE.md and maintainer guide for Maven Central and current errors. Remove Android CI token requirements/fork restriction now that artifacts are public; do not alter remote secrets.
7. **Verify.** Dart formatting, analysis and tests for both packages and affected example behavior; iOS release build via SwiftPM and a throwaway CocoaPods app; Android release build; both pub publish dry-runs. Restore any global Flutter setting exactly as found; avoid unrelated lockfile churn. Then PR and isolated review, max three rounds.

## Scope and open evidence

- Extra battery/charging/don/hinge fields, experimental audio/standalone capture/input/motion/speech/voice, display and Meta-AI-initiated registration are deferred. No extra permissions or consumer APIs are needed for the compatibility update.
- Generated interfaces confirm existing app-initiated iOS handleUrl overload remains; the new callback is required only for Meta-AI-initiated requests. Do not silently accept those requests.
- Runtime outcomes remain unverified until hardware QA. Renamed thermal cases alone do not prove pause vs terminal behavior; validate lifecycle with real state events and preserve existing channel compatibility.
- Any unexpected API or build finding that materially changes this plan must be recorded and clarified before dependent implementation.

## Hardware handoff checks

1. Register from the app and return through its callback; confirm paired-device discovery on iOS and Android.
2. Subscribe before starting, start/stop/restart preview, capture a photo, and verify the new texture after restart.
3. Switch selected glasses and cancel/resubscribe to device state; ensure updates belong only to the selected pair. Mock thermal simulation cannot establish real thermal timing.
4. Test removal, folding, and power-off separately. Removal need not stop streaming: on the tested Meta Ray-Ban Display with DAT 1.0.0 it continues, as expected by the maintainer. Folding/power-off should clear an ended stream and allow restart after correction. Do not intentionally overheat hardware.
5. Background/lock without opt-in: stoppedForBackground then stopped, no auto-resume. With opt-in: frame delivery continues, preview resumes on foreground.
6. Exercise mock configure/pair/stream/unpair/disable and missing camera permission; ensure teardown completes before re-pairing.
7. Compatibility warning must preserve preview; insufficientSDKVersion must require app update rather than repeated restart. Use controlled simulated channel events where hardware cannot produce these conditions safely.

## Skill improvements this run

- Version-aware Android artifact host, verify both POM and AAR, fail rather than skip missing legacy credentials; 404 now directs inspection of upstream setup instructions.
- Anonymous curl options compatible with macOS Bash 3.

## Additional binary findings

- iOS removed RegistrationError.timeout and UnregistrationError.timeout without changelog entries. Remove obsolete switch cases; preserve the Flutter registration error codes.
- Android inserted audioCodec ahead of existing StreamConfiguration parameters. Use named frameRate to preserve video-only configuration.
- First builds failed on these two source compatibility changes; rebuild after fixing them.

## Local verification

- Dart MCP analysis: both packages and example, no errors (rerun after final edits).
- Tests: core 24, mock 4, example 7 (including warning vs terminal compatibility regression coverage).
- iOS SwiftPM release build passed without signing; CocoaPods throwaway consumer release build passed without signing.
- Android release APK build passed. Flutter warns existing Gradle/AGP/Kotlin versions will lose support in a future Flutter release; no toolchain bump needed for this migration.
- Flutter SwiftPM global setting restored to true. Example lockfile changes only the two path package versions.
- Both publishing dry-runs passed with zero warnings on the committed tree.
- Physical iPhone verification started; see the hardware results below. Android hardware remains untested.

Android native verification executed 8 tests with zero failures/skips. Example regression tests are included in the CI test matrix.

## Independent review

One P2 finding: the example cleared insufficientSDKVersion after the generic 15-second physical-recovery grace or device reappearance. Fixed by preserving its update-required latch across both; an explicit user stop can still reset the session. Focused tests assert the retained app-update hint and disabled Start after 20 seconds and reconnect; both passed, with clean focused analysis. Fresh round 2 found no actionable issues. All 14 hosted CI checks passed at b40391f.

## Hardware results — 2026-09-25 (remaining tests deferred)

- Installed signed debug example on iPhone 17, iOS 27.0, using the existing Bluetooth Classic configuration and DAT 1.0.0.
- Restored registration, discovered one real Meta Ray-Ban Display pair, received thermalLevel=none, and confirmed camera permission granted. Device metadata reported connected, compatible, and active. This does not verify a fresh registration callback or live thermal changes.
- Initial stream attempt and a second attempt after the maintainer confirmed readiness both failed before any video size/frame evidence or streaming state: starting → unexpectedError ("Session ended by device") → stopping → timeout → stopped. The example attempted automatic recovery; testing explicitly stopped it and confirmed streaming intent, texture, and teardown state were cleared.
- startStreamSession returned a texture while state remained starting. Treat texture allocation as startup acceptance, not proof of working video.
- Root cause remains undetermined. Do not attribute the failure to the SDK migration, firmware, transport, or wear detection without further evidence. The maintainer confirmed the same error followed by timeout.
- Lock/unlock with background opt-in has mixed results (see below). Device switching and mock teardown remain unverified on hardware. Green builds alone do not establish release readiness.
- Launch also logged duplicate Objective-C classes between the upstream MWDATCamera and MWDATMockDevice binaries; no crash was observed. Causality with stream failure has not been established.
- Process-filtered native logs reproduced texture allocation at 12:20:44.465, then device-session error and SDK camera timeout at 12:20:54.751 (about 10.3 seconds). The timeout is the SDK StreamError.timeout, not the plugin's DeviceSession startup deadline. Native teardown then unregistered the texture.
- Pulled Library/Caches/MetaWearablesDAT/Logs/MetaWearablesDAT.log from this app's container. An unchanged idle snapshot followed by a bounded reproduction appended 12 DeviceHealthChannel.swift:40 errors: "shared DWA channel error 49153". This confirms the channel errors are current, but the undocumented numeric code does not establish a root cause. Older untimestamped linkNotEstablished/BLE errors did not recur in that delta and must not be attributed to today's attempts.
- **Recovery confirmed by maintainer:** deleting the example app and rerunning it in debug mode restored working streaming. No transport configuration change was made; the example remains configured for Bluetooth Classic. Reconnected to the new IDE debug session afterward; at inspection it was stopped, with no error and thermalLevel=none. Successful moving video is maintainer-observed, not independently captured by tooling. Reinstallation implicates installation/persisted state as a possibility but does not identify the cause or establish upgrade-in-place reliability.
- **Stop/restart passed (maintainer-observed):** two consecutive Stop → Start cycles returned moving video successfully after the clean installation. The debug connection was unavailable during these cycles, so texture-ID replacement and native event ordering were not independently inspected.
- **Photo capture passed (maintainer-observed):** captured a photo during streaming, confirmed it displayed correctly, and confirmed video continued afterward. Photo bytes/format and native event ordering were not independently inspected.
- **Background without opt-in passed (maintainer-observed):** started video with background streaming disabled, went Home for 5 seconds, and returned. The stream remained stopped; explicit Start restored moving video. Native stoppedForBackground → stopped event ordering was not independently inspected.
- **Checklist test 1 passed (maintainer-observed):** lock/unlock without background opt-in leaves streaming stopped, and explicit Start restores video.
- **Checklist test 2 passed (maintainer-observed):** with background streaming enabled, going Home for 15 seconds and returning restores moving preview without manual restart. Continuous background frame delivery was not instrumented.
- **Checklist test 3 failed (maintainer-observed):** with background streaming enabled, locking the phone loses the stream after approximately 8–10 seconds. Investigating with process-filtered native logs; root cause and exact post-unlock state remain undetermined.
- **Checklist test 3 repeat passed (maintainer-observed):** video resumed correctly after 20 seconds locked. Before the repeat, VM inspection confirmed background=true, RAW codec, streaming state, texture=11, and no error. After the report, VM inspection showed no active session/texture and no error; native log capture yielded no app events, so neither uninterrupted frame delivery nor event ordering was established. Keep test 3 as intermittent/unresolved; no runtime code was changed between the reported failure and pass. Repeat without an attached debugger before final background acceptance.
- **Checklist test 3 further repetitions (maintainer-observed):** first 30-second lock passed; the second failed after approximately 15 seconds with "Session ended by device". This confirms intermittent failure; successful repetitions do not close it.
- **Checklist test 4 passed (maintainer-observed):** HVC1 streaming and background/lock recovery passed. This is not yet sufficient evidence to attribute test 3's intermittent failure to RAW specifically.
- **Checklist test 5 expected behavior confirmed (maintainer-observed):** removing the glasses leaves the stream running. The earlier checklist expectation was incorrect for this device/setup. Consumer instructions and public API documentation now qualify removal behavior by device/firmware while preserving terminal handling when hingesClosed is actually emitted.
- **Checklist test 6 passed (maintainer-observed):** folding/unfolding the glasses gives the expected stream cleanup and successful explicit restart.

### Follow-up investigation plan (before runtime changes)

1. Capture a failing lock cycle with verified app-process logs, SDK-log before/after snapshots, frame-arrival timing, audio interruption/route events, and device/stream transitions. Distinguish camera termination from app suspension or preview-only failure.
2. Compare RAW and HVC1 under the same transport and background settings, then repeat without an attached debugger. Do not infer codec causality from one HVC1 pass.
3. If failure persists, compare against the pre-migration SDK on the same hardware before selecting a fix. Qualify doff documentation to distinguish observed device behavior from the meaning of an emitted hingesClosed error. Present any runtime fix plan before implementation and rerun the affected lock/background checks afterward.
