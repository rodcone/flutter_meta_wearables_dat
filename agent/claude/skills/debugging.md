# Debugging DAT integrations

## Quick diagnosis

```
App not connecting?
├── Developer Mode enabled in Meta AI app?
│   └── Resets after firmware updates — re-enable it
├── Meta AI app up to date? Glasses firmware up to date?
│   └── See https://wearables.developer.meta.com/docs/version-dependencies
├── Called requestAndroidPermissions() first? (Android only)
│   └── Must complete before any other DAT call
├── Registration deep link returning to app?
│   └── URL scheme must match between iOS/Android config and Developer Center
├── Camera permission granted?
│   └── Check getCameraPermissionStatus()
└── Device showing as active?
    └── Check activeDeviceStream()

Stream not starting?
├── Check streamSessionStateStream() — what state is it stuck in?
├── Check streamSessionErrorStream() — any errors?
├── On Android: MainActivity extends FlutterFragmentActivity?
│   └── FlutterActivity will NOT work — permission sheets fail
├── On Android: GitHub token configured?
│   └── GITHUB_TOKEN env var or github_token in local.properties
└── Try restarting glasses:
    1. Power switch OFF
    2. Press and hold capture button
    3. Slide power switch ON
    4. Release capture button when LED turns red
```

## Registration deep link not returning

If `startRegistration()` opens Meta AI but the app never returns:

1. Verify URL scheme in iOS `Info.plist` (`CFBundleURLSchemes` and `MWDAT > AppLinkURLScheme`)
2. Verify URL scheme in Android `AndroidManifest.xml` (`<data android:scheme="..."/>`)
3. Both must match the scheme registered in the Meta Wearables Developer Center
4. The `MWDAT > AppLinkURLScheme` must include the `://` suffix (e.g., `myexampleapp://`)

## Stream errors

| Error code | Meaning | Action |
|------------|---------|--------|
| `thermalCritical` | Device thermal state critical | Streaming pauses automatically. Wait for device to cool down. |
| `thermalEmergency` | Device thermal emergency (**iOS only** — Android reports `deviceThermalEmergency`) | Stream stopped. Wait for cool down before retrying. |
| `peakPowerShutdown` | Device exceeded peak power limit | Stream stopped. Reduce streaming intensity / wait. |
| `batteryCritical` | Device battery critically low | Stream stopped. Charge the glasses. |
| `deviceThermalCritical` / `deviceThermalEmergency` / `devicePeakPowerShutdown` / `deviceBatteryCritical` | Device-session-level variants (the session itself tore down, not just the stream) | Same actions as the stream-level variants; the plugin will recreate the session on the next `startStreamSession()`. |
| `datAppOnTheGlassesUpdateRequired` | The on-device DAT app needs updating before streaming can work | Call `MetaWearablesDat.openDATGlassesAppUpdate()` to bounce the user to Meta AI. |
| `sessionEndedByDevice` | The device ended the session; the stream stops with it (**Android only**) | Tear the session down and let the user restart it. |
| `capabilityDenied` | The device refused the requested capability (**Android only**) | Check permissions; re-request camera access. |
| `dwaUnavailable` | The DAT Wearables App is unavailable on the glasses | Restart the glasses; check firmware. |
| `hingesClosed` | Glasses closed **or taken off** (since DAT 0.9.0 doff raises this too) | Put them back on and start a new session. The SDK does not auto-resume. |
| `permissionDenied` | Camera permission denied | Request permission again or guide user to settings. |
| `deviceNotConnected` | Device disconnected | Check Bluetooth connection, restart glasses if needed. |
| `deviceNotFound` | No matching device | Ensure glasses are paired and in range. |
| `timeout` | Operation timed out | Retry the operation. |
| `videoStreamingError` | Stream failed | Stop and restart the session. |
| `internalError` | Internal SDK error | Check logs, restart the session. |

Photo-capture failure never reaches this stream — it rejects the `capturePhoto()` future with `CAPTURE_PHOTO_FAILED` instead, `details` carrying the granular reason (`photoCaptureFailed` / `photoCaptureTimeout` on iOS; `deviceDisconnected` / `notStreaming` / `captureInProgress` / `captureFailed` on Android).

### Frozen video after an error

A `Texture` widget keeps showing its last frame forever if you only surface the error. For codes that leave the stream dead with no auto-resume — `hingesClosed`, `permissionDenied`, `thermalEmergency`, `peakPowerShutdown`, `batteryCritical`, the four `device*` variants, `sessionEndedByDevice` — **tear the session down**: clear your texture ID and streaming flag so the placeholder renders and Start is available again. Losing the active device mid-stream needs the same handling, and it arrives on `activeDeviceStream()` rather than as an error.

## Android-specific issues

- **FlutterFragmentActivity required:** `FlutterActivity` does not extend `ComponentActivity`, so `ActivityResultLauncher` cannot register. Camera permissions will fail silently.
- **GitHub token missing:** Build will fail with dependency resolution errors. Set `GITHUB_TOKEN` env var or add `github_token` to `android/local.properties`.
- **SDK not initialized:** If `requestAndroidPermissions()` is not called (and granted) before other DAT calls, device discovery will not work.

## iOS-specific issues

- **Minimum iOS 17.2:** The DAT xcframeworks require iOS 17.2+. Set `IPHONEOS_DEPLOYMENT_TARGET = 17.2` in Xcode.
- **Missing Info.plist keys:** Missing Bluetooth or external accessory entries will cause silent failures.

## Glasses restart procedure

1. Switch the power button to off
2. Press and hold the capture button, then slide the power switch on
3. Release the capture button when the LED turns red (don't wait until white)

## Useful links

- [Known Issues](https://wearables.developer.meta.com/docs/knownissues)
- [Version Dependencies](https://wearables.developer.meta.com/docs/version-dependencies)
- [FAQ](https://developers.meta.com/wearables/faq/)
- [Report a bug](https://wearables.developer.meta.com/devcenter/feedback/)
