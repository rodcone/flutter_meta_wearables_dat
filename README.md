![Pub Version](https://img.shields.io/pub/v/flutter_meta_wearables_dat)
![Pub Likes](https://img.shields.io/pub/likes/flutter_meta_wearables_dat)
![Pub Points](https://img.shields.io/pub/points/flutter_meta_wearables_dat)
![Pub Downloads](https://img.shields.io/pub/dm/flutter_meta_wearables_dat)
[![style: very good analysis](https://img.shields.io/badge/style-very_good_analysis-B22C89.svg)](https://pub.dev/packages/very_good_analysis)

# flutter_meta_wearables_dat

<img width="500" height="95" alt="flutter_dat" src="https://github.com/user-attachments/assets/b3958072-1bb5-434d-8006-8f35ae054213" />


A Flutter plugin that provides a bridge to Meta's Wearables Device Access Toolkit (DAT), enabling integration with Meta AI Glasses for iOS and Android.

> **Mock device support is in a separate package.** Real-device pairing, registration, streaming and photo capture all live in this core plugin. The simulated Ray-Ban Meta (driven by the phone's camera) lives in the optional add-on **[`flutter_meta_wearables_dat_mock_device`](flutter_meta_wearables_dat_mock_device/)** — pull it in only for development. Production apps that omit it ship without `MWDATMockDevice.xcframework` (iOS) or `mwdat-mockdevice` (Android), so they don't need to declare `NSCameraUsageDescription` or the `CAMERA` permission. See [Optional: mock device add-on](#optional-mock-device-add-on) for the one-line install.

## Table of contents
- [flutter\_meta\_wearables\_dat](#flutter_meta_wearables_dat)
  - [Table of contents](#table-of-contents)
  - [Publishing disclaimer](#publishing-disclaimer)
  - [Compatible devices](#compatible-devices)
  - [Setup](#setup)
    - [Glasses setup (Developer mode)](#glasses-setup-developer-mode)
    - [iOS Configuration](#ios-configuration)
    - [Android Configuration](#android-configuration)
      - [1. AndroidManifest.xml](#1-androidmanifestxml)
      - [2. Repository Configuration](#2-repository-configuration)
      - [3. MainActivity configuration](#3-mainactivity-configuration)
    - [Meta Wearables Developer Center](#meta-wearables-developer-center)
  - [Integration Lifecycle](#integration-lifecycle)
    - [0. Android Permissions (Android only)](#0-android-permissions-android-only)
    - [1. Registration (One-time)](#1-registration-one-time)
    - [2. Permissions (First-time camera access)](#2-permissions-first-time-camera-access)
    - [3. Session (After registration and permissions)](#3-session-after-registration-and-permissions)
      - [Video codecs](#video-codecs)
      - [Background streaming](#background-streaming)
      - [Stream quality](#stream-quality)
      - [Accessing raw frame bytes](#accessing-raw-frame-bytes)
  - [Optional: mock device add-on](#optional-mock-device-add-on)
  - [AI Assistant Integration](#ai-assistant-integration)
  - [Troubleshooting](#troubleshooting)
  - [Example app](#example-app)
  - [Contributing](#contributing)
  - [License](#license)

## Publishing disclaimer

The Meta Wearables Device Access Toolkit is currently in **developer preview**. During this phase:

- You can use the SDK to **build, prototype, and test** your app.
- You can **distribute to testers** within your organization or team (e.g. via the beta testing platform in the [Meta Wearables Developer Center](https://wearables.developer.meta.com/)).
- **Publishing to the general public is limited**: only select partners can publish their DAT integrations to public app stores. Most apps using DAT cannot be published publicly yet.

Meta is running the preview to test, learn, and refine the toolkit; broader publishing (general availability) is planned for 2026. For full details, see [Introducing the Meta Wearables Device Access Toolkit](https://developers.meta.com/blog/introducing-meta-wearables-device-access-toolkit/) and the [Meta Wearables FAQ](https://developer.meta.com/wearables/faq).

## Compatible devices

- Ray-Ban Meta (Gen 1 & 2)
- Meta Ray-Ban Display
- Oakley Meta HSTN
- Oakley Meta Vanguard

## Setup

### Glasses setup (Developer mode)

To set up your glasses for development, you must enable **Developer mode** in the Meta AI app. See [Enable developer mode in the Meta AI app](https://wearables.developer.meta.com/docs/getting-started-toolkit/#enable-developer-mode-in-the-meta-ai-app) for instructions.

### iOS Configuration

**Minimum deployment target:** iOS 17.0

**iOS Simulator:** Apple Silicon Macs only. The vendored Meta DAT xcframeworks are shipped with arm64-only simulator slices to stay under pub.dev's 100 MiB package-size limit; x86_64 (Intel Mac) iOS Simulator builds are not supported.

Add the following to your `Info.plist`:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Needed to connect to Meta AI Glasses</string>

<key>LSApplicationQueriesSchemes</key>
<array>
    <string>fb-viewapp</string>
</array>

<key>UISupportedExternalAccessoryProtocols</key>
<array>
    <string>com.meta.ar.wearable</string>
</array>

<key>UIBackgroundModes</key>
<array>
    <string>bluetooth-peripheral</string>
    <string>external-accessory</string>
</array>

<!-- Deep link callback from Meta AI app - scheme must match AppLinkURLScheme below -->
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>myexampleapp</string>
        </array>
    </dict>
</array>

<!-- Meta Wearables Device Access Toolkit Setup -->
<key>MWDAT</key>
<dict>
    <key>AppLinkURLScheme</key>
    <!-- Must match CFBundleURLSchemes above so Meta AI redirects to a URL this app handles -->
    <string>myexampleapp://</string>
    <key>MetaAppID</key>
    <!-- Without Developer Mode, use the ID from the app registered in Wearables Developer Center -->
    <string>YOUR_APP_ID</string>
    <key>ClientToken</key>
    <!-- Without Developer Mode, use the ClientToken from Wearables Developer Center -->
    <string>YOUR_CLIENT_TOKEN</string>
    <key>TeamID</key>
    <!-- Your Apple Developer Team ID - Set this in Xcode under Signing & Capabilities -->
    <string>$(DEVELOPMENT_TEAM)</string>
    <key>Analytics</key>
    <dict>
        <key>OptOut</key>
        <true/>
    </dict>
</dict>
```

### Android Configuration

#### 1. AndroidManifest.xml

Add the following to your app's `AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.BLUETOOTH" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.INTERNET" />

<application>
    <!-- Required: Your application ID from Wearables Developer Center -->
    <!-- Use "0" for Developer Mode -->
    <meta-data
        android:name="com.meta.wearable.mwdat.APPLICATION_ID"
        android:value="0" />

    <!-- Optional: Disable analytics -->
    <meta-data
        android:name="com.meta.wearable.mwdat.ANALYTICS_OPT_OUT"
        android:value="true" />

    <!-- Deep link callback from Meta AI app -->
    <activity android:name=".MainActivity" android:launchMode="singleTop">
        <intent-filter>
            <action android:name="android.intent.action.VIEW" />
            <category android:name="android.intent.category.BROWSABLE" />
            <category android:name="android.intent.category.DEFAULT" />
            <data android:scheme="myexampleapp" />
        </intent-filter>
    </activity>
</application>
```

#### 2. Repository Configuration

Add the GitHub Packages repository to your `settings.gradle.kts`. First, add the necessary imports at the top of the file:

```kotlin
import java.util.Properties
import kotlin.io.path.div
import kotlin.io.path.exists
import kotlin.io.path.inputStream
```

Then add the repository configuration:

```kotlin
val localProperties =
    Properties().apply {
        val localPropertiesPath = rootDir.toPath() / "local.properties"
        if (localPropertiesPath.exists()) {
            load(localPropertiesPath.inputStream())
        }
    }

dependencyResolutionManagement {
    // Flutter's Gradle plugin adds a maven repo at the project level.
    repositoriesMode.set(RepositoriesMode.PREFER_SETTINGS)
    repositories {
        google()
        mavenCentral()
        maven {
            url = uri("https://maven.pkg.github.com/facebook/meta-wearables-dat-android")
            credentials {
                username = "" // not needed
                password = System.getenv("GITHUB_TOKEN") ?: localProperties.getProperty("github_token")
            }
        }
    }
}
```

**Note:** We use `PREFER_SETTINGS` instead of `FAIL_ON_PROJECT_REPOS` because Flutter's Gradle plugin needs to add repositories at the project level.

Set a GitHub token with `read:packages` scope via:
- Environment variable: `GITHUB_TOKEN`
- Or in `local.properties`: `github_token=your_token_here`

#### 3. MainActivity configuration

Wearables permission requests use `Wearables.RequestPermissionContract`, which requires
the hosting Android `Activity` to be a `ComponentActivity`. In a Flutter app this means
you **must** extend `FlutterFragmentActivity` (which itself extends `FragmentActivity`
→ `ComponentActivity`), not `FlutterActivity`.

Update your `android/app/src/main/kotlin/.../MainActivity.kt` (or `.java`) to:

```kotlin
package com.yourcompany.yourapp

import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity()
```

If you keep using `FlutterActivity`, the DAT permission sheet will not be able to
register an `ActivityResultLauncher` and camera permission requests will fail.

### Meta Wearables Developer Center

Add and configure your app in the [Meta Wearables Developer Center](https://wearables.developer.meta.com/devcenter) to obtain your `MetaAppID` and complete the setup.

## Integration Lifecycle

The plugin follows Meta's integration lifecycle as documented in the [Meta Wearables Developer Documentation](https://wearables.developer.meta.com/docs/build-overview):

### 0. Android Permissions (Android only)
- Call `MetaWearablesDat.requestAndroidPermissions()` before any other DAT calls
- This requests Bluetooth and Internet runtime permissions required by the DAT SDK
- **Important:** On Android, the DAT SDK is not initialized until these permissions are granted. This is critical for device discovery to work correctly.
- No-op on iOS

### 1. Registration (One-time)
- User taps a call-to-action in your app (e.g., "Connect my glasses")
- Call `MetaWearablesDat.startRegistration()` to open the Meta AI app
- User confirms the connection in Meta AI app
- Meta AI returns to your app via deep link
- Handle the callback URL with `MetaWearablesDat.handleUrl(url)` to complete registration
- Monitor registration state via `MetaWearablesDat.registrationStateStream()`
- Monitor active device availability via `MetaWearablesDat.activeDeviceStream()`

### 2. Permissions (First-time camera access)
- When your app first attempts to access the camera, request permission
- Call `MetaWearablesDat.requestCameraPermission()` to show the Meta AI permission bottom sheet
- User can allow always, allow once, or deny

### 3. Session (After registration and permissions)
- Once registered and permissions are granted, start a streaming session
- Call `MetaWearablesDat.startStreamSession(deviceUUID)` — returns a `textureId`
- Render the live video feed using Flutter's `Texture` widget with the returned ID
- Monitor session state via `MetaWearablesDat.streamSessionStateStream()`
- Monitor errors via `MetaWearablesDat.streamSessionErrorStream()`
- (Optional) Monitor device thermal level via `MetaWearablesDat.deviceStateStream()` to warn the user *before* a thermal error stops the stream
- (Optional) On `datAppOnTheGlassesUpdateRequired`, call `MetaWearablesDat.openDATGlassesAppUpdate()` to drive a "tap to update" UI
- Call `MetaWearablesDat.stopStreamSession(deviceUUID)` to end the session

```dart
// Start streaming — returns a texture ID for zero-copy rendering
final textureId = await MetaWearablesDat.startStreamSession(
  deviceUUID,
  fps: 24,
  streamQuality: StreamQuality.low,
  videoCodec: VideoCodec.raw, // or VideoCodec.hvc1 (iOS only, supports background streaming)
);

// Render the live video feed
Texture(textureId: textureId);

// Monitor session state
MetaWearablesDat.streamSessionStateStream().listen((state) {
  // StreamSessionState: stopped, waitingForDevice, starting, streaming, paused, stopping
  print('Session state: $state');
});

// Monitor errors (e.g., thermalCritical, hingesClosed, permissionDenied,
// datAppOnTheGlassesUpdateRequired, batteryCritical, peakPowerShutdown, …)
MetaWearablesDat.streamSessionErrorStream().listen((error) {
  print('Session error: ${error.code} — ${error.message}');
  if (error.isThermalCritical) {
    // Device overheating — streaming paused automatically
  } else if (error.code == 'datAppOnTheGlassesUpdateRequired') {
    // Glasses need an app update — bounce the user to Meta AI to handle it
    MetaWearablesDat.openDATGlassesAppUpdate();
  }
});

// (Optional) Live thermal level — drive a "device is getting hot" indicator
// before a thermal error stops the stream entirely.
MetaWearablesDat.deviceStateStream().listen((state) {
  // state.thermalLevel: unknown, none, light, moderate, severe, critical, emergency, shutdown
  print('Thermal: ${state.thermalLevel}');
});

// Capture a photo during streaming
final photo = await MetaWearablesDat.capturePhoto(
  deviceUUID,
  format: PhotoCaptureFormat.jpeg, // or PhotoCaptureFormat.heic
);

// Stop streaming when done
await MetaWearablesDat.stopStreamSession(deviceUUID);
```

Video frames are pushed directly from native (CVPixelBuffer on iOS, SurfaceTexture on Android) to the Flutter engine — no JPEG encoding, no byte copying, no Dart-side decoding.

#### Video codecs

| Codec             | Platform      | Description                                                                                                                                                                                                                                                                                          |
|-------------------|---------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `VideoCodec.raw`  | iOS & Android | Raw uncompressed frames. iOS: BGRA pixel data. Android: I420 planar YUV. Default.                                                                                                                                                                                                                    |
| `VideoCodec.hvc1` | iOS only      | Compressed HEVC (`hvc1` NAL units) decoded via `VTDecompressionSession`. Smaller over-the-wire payload than `raw` and the only codec that survives a brief background transition without any opt-in (hardware decoder is paused on background and auto-recreated on foreground). Ignored on Android. |

For full background streaming (app backgrounded, phone locked, or both) on **either** platform and **either** codec, see [Background streaming](#background-streaming) below.

#### Background streaming

By default the host OS suspends your app shortly after it's no longer visible, and the DAT stream dies with it. Call `enableBackgroundStreaming()` **before** `startStreamSession()` to keep the session alive across all three "not visible" states:

1. Flutter app sent to background (user taps home / switches apps).
2. Screen locked while the app is in foreground.
3. Both combined.

```dart
// Enable before starting the session. Notification fields are required on Android
// (the OS needs them to display the mandatory foreground service notification).
await MetaWearablesDat.enableBackgroundStreaming(
  androidNotification: const BackgroundNotification(
    title: 'Streaming from your glasses',
    text: 'Keeps the camera stream alive in the background.',
    channelId: 'myapp.streaming',
    channelName: 'Camera Stream',
    // iconResourceName: 'ic_stat_recording', // optional, falls back to app icon
  ),
);

final textureId = await MetaWearablesDat.startStreamSession(deviceUUID);

// ...later, when you no longer need background execution:
await MetaWearablesDat.stopStreamSession(deviceUUID);
await MetaWearablesDat.disableBackgroundStreaming();
```

**iOS — required `Info.plist` additions.** In addition to the default entries from [Setup → iOS](#ios-configuration), add `audio` and `bluetooth-central` to `UIBackgroundModes`:

```xml
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
    <string>bluetooth-central</string>
    <string>bluetooth-peripheral</string>
    <string>external-accessory</string>
</array>
```

**Android — no manual manifest changes needed.** The plugin's manifest auto-merges the required permissions (`FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_CONNECTED_DEVICE`, `WAKE_LOCK`, `POST_NOTIFICATIONS`) and declares the internal foreground service. On Android 13+ (API 33+), the first call to `enableBackgroundStreaming()` prompts the user for `POST_NOTIFICATIONS` — if denied, the foreground service still runs (so the stream survives), but its notification is suppressed by the OS until the user enables notifications for your app in system settings.

**How it works.** On iOS the plugin activates an `AVAudioSession` configured for Bluetooth HFP + mixing, which keeps the process scheduled in background. The HEVC hardware decoder is invalidated on background entry (iOS forbids GPU access from backgrounded apps) and lazily recreated on the first frame after foreground — you'll see a brief stall while the decoder waits for the next keyframe, then streaming resumes cleanly. While backgrounded, the raw hvc1 NAL bytes still reach `videoFramesStream()` for recording. On Android the plugin starts a foreground service of type `connectedDevice` with your notification and holds a `PARTIAL_WAKE_LOCK` until you disable it.

**Accessing frames while backgrounded.** The normal `Texture` widget can't render in background (no GPU access), but the plugin exposes every decoded frame to Dart via `videoFramesStream()`, in both foreground and background. Useful for recording to disk, running ML, or re-muxing:

```dart
final sub = MetaWearablesDat.videoFramesStream().listen((frame) {
  // frame.codec                   → VideoCodec.raw or VideoCodec.hvc1
  // frame.bytes                   → Uint8List of the raw codec payload
  // frame.width / frame.height    → pixel dimensions
  // frame.presentationTimestampUs → monotonic, in microseconds
  // frame.isKeyframe              → always true for raw; hvc1 keyframes carry SPS/PPS/VPS
});
```

Frame bytes are codec-dependent:

- `VideoCodec.raw` — **iOS**: BGRA pixel data at `bytesPerRow * height` bytes; rows may carry trailing padding for alignment, so iterate rows with `VideoFrame.bytesPerRow` rather than assuming `width * 4`. **Android**: I420 planar YUV, tightly packed at `width * height * 3/2` bytes (Y plane, then U, then V; `bytesPerRow` is `null`).
- `VideoCodec.hvc1` (iOS only) — raw HEVC elementary stream (`hvc1` NAL units). Keyframes carry the parameter sets (VPS/SPS/PPS) inline, so the stream is self-contained and can be fed straight into `ffmpeg -i file.h265 out.mp4` or muxed into an mp4 track via `ffmpeg_kit_flutter`.

Subscribing to `videoFramesStream()` is zero-cost when there are no listeners — the plugin won't encode or emit anything until the first subscriber attaches. Always subscribe *before* calling `startStreamSession()` if you want to capture the opening keyframe.

**Notes and limitations:**

- **On-device muxing.** The plugin gives you raw frame bytes — muxing into mp4/mov is the host app's responsibility. For hvc1 on iOS this is usually a one-liner with `ffmpeg_kit_flutter`; for raw you'll want to transcode first.
- **Audio.** The iOS `AVAudioSession` is activated purely as a keep-alive. Microphone samples are not forwarded to Dart.
- **`captureStreamFrame`.** Rasterizes via the Flutter engine, which needs GPU access. Returns `null` while the app is backgrounded — use `videoFramesStream()` instead if you need pixel data in background.
- **Remember to disable.** `disableBackgroundStreaming()` tears down the `AVAudioSession` on iOS and stops the foreground service on Android. Calling it is idempotent and safe.

#### Stream quality

| Quality                | Resolution |
|------------------------|------------|
| `StreamQuality.low`    | 360 x 640  |
| `StreamQuality.medium` | 504 x 896  |
| `StreamQuality.high`   | 720 x 1280 |

Valid FPS values: 2, 7, 15, 24, 30.

#### Accessing raw frame bytes

For use cases that need pixel-level access — OCR, on-device ML inference, computer vision — use `captureStreamFrame`. This rasterizes the Flutter texture on the Dart side and returns raw RGBA bytes:

```dart
// After startStreamSession returns a textureId...
bool _processing = false;

Future<void> startFrameProcessing(int textureId) async {
  _processing = true;
  while (_processing) {
    final frame = await MetaWearablesDat.captureStreamFrame(textureId);
    if (frame != null) {
      // frame.bytes is raw RGBA — feed directly to ML Kit, Vision, etc.
      // frame.width  → 720
      // frame.height → 1280
      await runOcr(frame.bytes, frame.width, frame.height);
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }
}

void stopFrameProcessing() => _processing = false;
```

**Parameters:**
- `textureId` — the ID returned by `startStreamSession` (required)
- `width` / `height` — capture resolution, defaults to `720` × `1280` (glasses native resolution)
- `format` — `FrameFormat.rawRgba` (default), `FrameFormat.rawStraightRgba`, or `FrameFormat.png`

> **Memory note:** Raw RGBA at 720×1280 is ~3.7 MB per frame. Capture on demand (every 200–500 ms is typical for OCR/ML) rather than every rendered frame.

**Note:** See the [example app](https://github.com/rodcone/flutter_meta_wearables_dat/tree/main/example) for a complete implementation.

## Optional: mock device add-on

Meta gates registration on real glasses, so during development it's often handy to pair against a simulated Ray-Ban Meta backed by the phone's camera. That capability lives in the optional [`flutter_meta_wearables_dat_mock_device`](flutter_meta_wearables_dat_mock_device/) package — same repo, separate plugin. Apps that don't depend on it never link `MWDATMockDevice.xcframework` / `mwdat-mockdevice`, which is what allows the core plugin to ship without `NSCameraUsageDescription` (iOS) or the `CAMERA` permission (Android).

```yaml
# pubspec.yaml — add only in dev/staging builds
dependencies:
  flutter_meta_wearables_dat: ^0.5.0
  flutter_meta_wearables_dat_mock_device: ^0.5.0
```

```dart
import 'package:flutter_meta_wearables_dat_mock_device/flutter_meta_wearables_dat_mock_device.dart';

// Grant the perms the SDK normally asks for at runtime so the mock flow doesn't
// bounce through Meta AI for registration during dev.
await MetaWearablesDatMockDevice.configure(
  initiallyRegistered: true,
  initialPermissionsGranted: true,
);

final uuid = await MetaWearablesDatMockDevice.pairRayBanMeta();
await MetaWearablesDatMockDevice.powerOn(uuid);
await MetaWearablesDatMockDevice.don(uuid);
await MetaWearablesDatMockDevice.setCameraFacing(uuid, CameraFacing.back);

// From here, the core plugin's normal streaming API works against this UUID:
final textureId = await MetaWearablesDat.startStreamSession(uuid);
```

Apps that pull in this package **must** declare `NSCameraUsageDescription` (iOS) and the `CAMERA` permission (Android) — the mock device uses the phone's camera as the simulated glasses feed. The `Permission`, `PermissionStatus`, and `CameraFacing` enums all live in this package.

If you previously used the inline mock APIs (`MetaWearablesDat.pairMockRayBanMeta()` etc. in `flutter_meta_wearables_dat` 0.3.x), see the [0.4.0 migration table in the changelog](CHANGELOG.md).

## AI Assistant Integration

This plugin includes configuration files for AI coding assistants (Claude Code, Cursor, GitHub Copilot). Install them to give your AI assistant full context on DAT integration patterns:

```bash
# One-liner — installs all tools
curl -sL https://raw.githubusercontent.com/rodcone/flutter_meta_wearables_dat/main/install-skills.sh | bash

# Or install specific tools only
curl -sL https://raw.githubusercontent.com/rodcone/flutter_meta_wearables_dat/main/install-skills.sh | bash -s claude
curl -sL https://raw.githubusercontent.com/rodcone/flutter_meta_wearables_dat/main/install-skills.sh | bash -s cursor

# Or from cloned repo
./install-skills.sh all
```

Your AI assistant will auto-discover the config when you open the project. See also: [AI-Assisted Development](https://wearables.developer.meta.com/docs/ai-assisted)

## Troubleshooting

If you run into issues, try these steps first:

- **Update Meta AI app and glasses firmware**: Ensure you have the latest version of the Meta AI app installed on your phone, and within the app, check for and install any available firmware updates for your glasses. [See version dependencies](https://wearables.developer.meta.com/docs/version-dependencies).
- **Verify installation**: Ensure you have followed all installation steps above, including configuration in your code and in the [Meta Wearables Developer Center](https://wearables.developer.meta.com/devcenter).
- **Restart your glasses** — If the glasses don't connect or the stream doesn't start, try restarting them:
  1. Switch the power button to off.
  2. Press and hold the capture button, then slide the power switch on.
  3. Release the capture button when the LED turns red (don't wait until the LED turns white).
- **From official docs**: See [Known Issues](https://wearables.developer.meta.com/docs/knownissues), [FAQ](https://developers.meta.com/wearables/faq/) and [Report a bug](https://wearables.developer.meta.com/devcenter/feedback/).

Common issues:
- **Registration deep link not returning** — If registration opens the Meta AI app but the callback does not return to your app, verify that your URL scheme matches the one registered in the [Meta Wearables Developer Center](https://wearables.developer.meta.com/devcenter). On iOS, ensure `CFBundleURLSchemes` in `Info.plist` (and `AppLinkURLScheme` in the `MWDAT` dict) use the same scheme. On Android, ensure the `data android:scheme` in your activity's intent-filter matches that scheme.

**Still having issues?** — Open a [GitHub issue](https://github.com/rodcone/flutter_meta_wearables_dat/issues) with all the details you can provide. This helps us pinpoint the problem and assist you more efficiently.

## Example app

The [example app](https://github.com/rodcone/flutter_meta_wearables_dat/tree/main/example) is a clone of the Meta's sample Camera Access native app.

Here's a demo showing how the DAT integration looks like:

![demo](https://github.com/user-attachments/assets/4947911e-5a37-4369-acb7-fdc005899821)

## Contributing

Contributions are welcome! Feel free to open [issues](https://github.com/rodcone/flutter_meta_wearables_dat/issues) for bugs or feature requests, and [pull requests](https://github.com/rodcone/flutter_meta_wearables_dat/pulls) for improvements.

## License

MIT License — see [LICENSE](LICENSE) for details.
