# DAT 1.0.0 migration plan

Status: implemented; local verification passed where listed below; PR #48 open; independent review in progress. DAT 0.9.0 → 1.0.0; both Flutter packages 0.9.2 → 0.10.0.

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
4. Doff/fold and power off while streaming; check terminal cleanup and explicit restart after correction. Do not intentionally overheat hardware.
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
- No physical-device or live backend verification performed.

Android native verification executed 8 tests with zero failures/skips. Example regression tests are included in the CI test matrix.
