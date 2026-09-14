# Validating with Mock Device Kit

The smallest manual pass that proves the example app's pairing, camera input,
device state and auto-selection paths work, using Meta's Mock Device Kit
instead of physical glasses. Source: Meta's
[Mock Device Kit guide](https://wearables.developer.meta.com/docs/develop/dat/mock-device-kit/).

Run it on a phone or the iOS Simulator with the example app built from this
repo. The live-camera steps need a physical phone; the video and image steps
work on a simulator too.

## Automated slice

The provider bookkeeping behind steps 1 and 3 is covered without any device:

```bash
cd example && flutter test
```

`test/mock_device_provider_test.dart` checks pairing appends one device per
call and stops at three, power on also dons the device, and unpair removes
only the named device. `test/selection_policy_test.dart` checks that pairing
never changes the selection and that unpairing clears a pin only when it
pointed at the departed mock.

## Manual pass

Each step names the control to use and what the UI must show. Stop at the
first mismatch.

### 1. Pair

1. Launch the app. Tap the bug icon in the top-right.
2. Pick a model and tap **Pair glasses**. A controls card appears with the
   model name and a UUID. The header reads **1 of 3 paired**.
3. Close the sheet. The app now shows the stream screen: enabling Mock Device
   Kit reports the app as registered, so no Meta AI round trip is needed.
4. Tap the glasses icon to open **Paired glasses**. The mock is listed with a
   **Connecting** or **Connected** badge. **Automatic** is selected.

### 2. Configure camera input

Back in the bug sheet, tap **Power on** on the card. Power on also dons the
device, which the SDK requires before streaming. The **Camera feed** row
appears. Pick one:

- **Live camera**, then **Back camera** or **Front camera**. The phone asks
  for camera permission on first use. Physical phone only.
- **Media**, then **Select video**. The clip must be H.265. iOS converts on
  the fly; Android needs a pre-transcoded file (`ffmpeg -c:v libx265`).
- **Media**, then **Select image**. This sets the still that `capturePhoto`
  returns. Combine with a video for a full stream plus capture check.

### 3. Stream and capture

1. Close the sheet. The **Start streaming** button is enabled. If it still
   says **Waiting for an active device**, the mock is not powered on.
2. Tap **Start streaming**. Video from the chosen source renders within a
   few seconds and the state label reads **Streaming**.
3. Open **Paired glasses** while streaming. The mock carries a green
   **Streaming** badge. The refresh icon spins once when tapped.
4. Tap the capture button. The share sheet opens with the captured photo.
   With a media image set, the shared file is that image.
5. Tap **Stop streaming**. The texture clears and the button returns.

### 4. Simulate device state

1. Start streaming again, then open the bug sheet and tap **Power off**.
   The stream ends on its own and a banner reads
   **The glasses disconnected — streaming stopped.** This exercises the
   active-device watchdog, the only signal the app gets when glasses die
   mid-stream.
2. Tap **Power on**. The banner clears and **Start streaming** is enabled.
3. Tap **Unpair**. The card disappears and **Paired glasses** no longer
   lists the device. If the stream was running from this mock it is stopped
   first, which avoids a known crash in the SDK's session service.

### 5. Auto-selection across two mocks

1. Pair a second mock and power both on.
2. In **Paired glasses**, keep **Automatic** selected. Exactly one mock
   shows the outlined **Auto-pick** badge. That is the SDK's current choice.
3. Tap **Start streaming**. The **Auto-pick** mock gains the **Streaming**
   badge.
4. Stop, then tap the other mock in **Paired glasses**. It shows
   **Will stream**. Start again and confirm the badge moves to it.
5. Unpair the pinned mock. The selection falls back to **Automatic**.
   Unpair the other while a real pair is pinned and the pin is untouched.

## Hardware-only

These paths are not reachable with a mock, either because the SDK does not
simulate them or because this plugin does not expose the simulation yet.

| Path | Why a mock cannot exercise it |
|---|---|
| Registration through Meta AI, deep-link return, unregister | Mock Device Kit reports the app as registered up front. `configure(initiallyRegistered: false)` exists on the facade but the example does not wire it. |
| Camera permission bottom sheet | Granted by default on mocks. `setPermission` and `setPermissionRequestResult` can force a denial on iOS only; Android has no hook. |
| Thermal chip and `thermalCritical` errors | The mock reports no thermal levels. |
| `datAppOnTheGlassesUpdateRequired` and the **Update** action | Only a real pair running old on-device firmware raises it. |
| Hinges closed and doff pause | The SDK's `fold`, `unfold` and `doff` calls exist on `MockGlasses`, but the plugin's Dart facade does not expose fold or unfold, and the example's UI folds don into power on. |
| Temple tap to pause and tap-and-hold to stop | `MockCaptouchKit.tap` and `tapAndHold` are in the SDK but not on the plugin's facade. |
| Background streaming keep-alive | The mock stream survives backgrounding trivially. Only a real Bluetooth link shows the audio-session and foreground-service behaviour. |
| HEVC `hvc1` decode from glasses, Bluetooth bandwidth, resolution and frame-rate negotiation | The mock feeds phone camera or file frames. Codec and transport limits are properties of the real link. |
| Link states other than connected | Mock devices do not go through pairing, out-of-range or reconnect states. |
