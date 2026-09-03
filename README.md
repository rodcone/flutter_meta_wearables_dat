[![Pub Version](https://img.shields.io/pub/v/flutter_meta_wearables_dat)](https://pub.dev/packages/flutter_meta_wearables_dat)
[![Pub Likes](https://img.shields.io/pub/likes/flutter_meta_wearables_dat)](https://pub.dev/packages/flutter_meta_wearables_dat)
[![Pub Points](https://img.shields.io/pub/points/flutter_meta_wearables_dat)](https://pub.dev/packages/flutter_meta_wearables_dat)
[![Pub Downloads](https://img.shields.io/pub/dm/flutter_meta_wearables_dat)](https://pub.dev/packages/flutter_meta_wearables_dat)
[![style: very good analysis](https://img.shields.io/badge/style-very_good_analysis-B22C89.svg)](https://pub.dev/packages/very_good_analysis)

[![Docs](https://img.shields.io/badge/API_Reference-0.9-blue?logo=meta)](https://wearables.developer.meta.com/docs/reference/ios_swift/dat/0.9)

# flutter_meta_wearables_dat

<!-- <img width="500" height="95" alt="flutter_dat" src="https://github.com/user-attachments/assets/b3958072-1bb5-434d-8006-8f35ae054213" /> -->

Build Flutter camera experiences for Meta AI glasses. Register a device, request camera access, and render its live video stream on iOS and Android through one Dart API.

![Demo of the example app](https://github.com/user-attachments/assets/4947911e-5a37-4369-acb7-fdc005899821)

```dart
// After registration and camera permission have completed:
final textureId = await MetaWearablesDat.startStreamSession(null);
Texture(textureId: textureId); // Live feed from the active glasses
```

No app-side platform-channel or native video-rendering code, JPEG encoding, or Dart-side video decoding is required for live rendering.

## Highlights

- **Native-to-Flutter video rendering:** Directly render the native stream in a Flutter `Texture`.
- **Complete camera workflow:** Registration, camera permission, streaming, photo capture, device selection, and device-state monitoring.
- **Developer-ready frame access:** Consume raw RGBA, YUV, or HEVC payloads for OCR, on-device ML, computer vision, or recording.
- **Background streaming:** Keep a session alive when the app is backgrounded or the phone is locked, on iOS and Android.
- **Optional mock glasses:** Develop with a simulated pair driven by the phone's camera, without including mock-device dependencies in production.
- **Reactive API:** Follow registration, availability, session, error, and thermal state with Dart `Stream`s.

## Quick start

### 1. Install

```yaml
dependencies:
  flutter_meta_wearables_dat: ^0.9.0
```

### 2. Configure iOS or Android

Complete the [platform setup](#setup), including a deep-link handler, and register your app in the [Meta Wearables Developer Center](https://wearables.developer.meta.com/devcenter). On iOS, choose either the recommended Wi-Fi transport or Bluetooth Classic; the [transport guide](#choose-your-camera-transport-wifi-recommended-or-bluetooth-classic) explains the trade-offs.

### 3. Register and stream

Registration completes asynchronously through a Meta AI deep-link callback. Start it from your UI:

```dart
// Required before every other DAT call on Android; a no-op on iOS.
await MetaWearablesDat.requestAndroidPermissions();

// One-time registration opens Meta AI.
await MetaWearablesDat.startRegistration();
```

Then, in your app's deep-link handler, forward the callback and continue only after it has been handled:

```dart
Future<int?> completeRegistration(Uri callbackUri) async {
  final handled = await MetaWearablesDat.handleUrl(callbackUri.toString());
  if (!handled) return null;

  // Restart device monitoring after returning from Meta AI.
  await MetaWearablesDat.restartActiveDeviceMonitoring();

  final granted = await MetaWearablesDat.requestCameraPermission();
  if (!granted) return null;

  // `null` automatically selects the active pair of glasses.
  return MetaWearablesDat.startStreamSession(null);
}
```

Render the returned ID with `Texture(textureId: textureId)`, and stop the session with `await MetaWearablesDat.stopStreamSession(null)` when finished. Since 0.9.1, stopping ends the whole device session — the glasses play their stream-ended tone, and the next start is a full reconnect rather than an instant re-attach.

For a complete implementation, see the [example app](https://github.com/rodcone/flutter_meta_wearables_dat/tree/main/example), which ports Meta's native Camera Access sample to Flutter.

> **Mock device support is in a separate package.** Real-device pairing, registration, streaming and photo capture all live in this core plugin. The simulated Ray-Ban Meta (driven by the phone's camera) lives in the optional add-on **[`flutter_meta_wearables_dat_mock_device`](flutter_meta_wearables_dat_mock_device/)** — pull it in only for development. Production apps that omit it ship without `MWDATMockDevice.xcframework` (iOS) or `mwdat-mockdevice` (Android), so they don't need to declare `NSCameraUsageDescription` or the `CAMERA` permission. See [Optional: mock device add-on](#optional-mock-device-add-on) for the one-line install.

## Table of contents
- [flutter\_meta\_wearables\_dat](#flutter_meta_wearables_dat)
  - [Highlights](#highlights)
  - [Quick start](#quick-start)
    - [1. Install](#1-install)
    - [2. Configure iOS or Android](#2-configure-ios-or-android)
    - [3. Register and stream](#3-register-and-stream)
  - [Table of contents](#table-of-contents)
  - [Publishing and availability](#publishing-and-availability)
  - [Compatible devices](#compatible-devices)
  - [Setup](#setup)
    - [Glasses setup (Developer mode)](#glasses-setup-developer-mode)
    - [Deep-link callback](#deep-link-callback)
    - [iOS Configuration](#ios-configuration)
      - [Choose your camera transport: Wi‑Fi (recommended) or Bluetooth Classic](#choose-your-camera-transport-wifi-recommended-or-bluetooth-classic)
      - [Migrating or switching camera transport](#migrating-or-switching-camera-transport)
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

## Publishing and availability

Meta controls DAT access and public-publishing eligibility. Under its developer-preview terms:

- You can use the SDK to **build, prototype, and test** your app.
- You can **distribute to testers** within your organization or team (e.g. via the beta testing platform in the [Meta Wearables Developer Center](https://wearables.developer.meta.com/)).
- **Publishing to the general public is limited**: only select partners can publish their DAT integrations to public app stores. Most apps using DAT cannot be published publicly yet.

Before planning a public launch, confirm your current eligibility with Meta. See [Introducing the Meta Wearables Device Access Toolkit](https://developers.meta.com/blog/introducing-meta-wearables-device-access-toolkit/) and the [Meta Wearables FAQ](https://developer.meta.com/wearables/faq).

## Compatible devices

- Ray-Ban Meta (Gen 1 & 2)
- Ray-Ban Meta Optics
- Meta Ray-Ban Display
- Oakley Meta HSTN
- Oakley Meta Vanguard
- Meta AI Glasses (Starfire, Adventurer, Fury)

## Setup

### Glasses setup (Developer mode)

To set up your glasses for development, you must enable **Developer mode** in the Meta AI app. See [Enable developer mode in the Meta AI app](https://wearables.developer.meta.com/docs/getting-started-toolkit/#enable-developer-mode-in-the-meta-ai-app) for instructions.

### Deep-link callback

Registration and disconnection complete when Meta AI opens the URL scheme configured in your platform files. Route that URI to `MetaWearablesDat.handleUrl(uri.toString())`. For example, with [`app_links`](https://pub.dev/packages/app_links):

```dart
late final StreamSubscription<Uri> _deepLinkSubscription;

@override
void initState() {
  super.initState();
  _deepLinkSubscription = AppLinks().uriLinkStream.listen((uri) async {
    await MetaWearablesDat.handleUrl(uri.toString());
    await MetaWearablesDat.restartActiveDeviceMonitoring();
  });
}

@override
void dispose() {
  _deepLinkSubscription.cancel();
  super.dispose();
}
```

Add a Dart-3.9-compatible release of `app_links` (for example, `app_links: ^6.4.1`) to your app and import both `package:app_links/app_links.dart` and `dart:async`. If you use another deep-link package or router, route its callback URI the same way.

### iOS Configuration

**Minimum deployment target:** iOS 17.2

**iOS Simulator:** Apple Silicon Macs only. The vendored Meta DAT xcframeworks are shipped with arm64-only simulator slices to stay under pub.dev's 100 MiB package-size limit; x86_64 (Intel Mac) iOS Simulator builds are not supported.

Add the following to your `Info.plist`:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Needed to connect to Meta AI Glasses</string>

<key>LSApplicationQueriesSchemes</key>
<array>
    <string>fb-viewapp</string>
</array>

<!-- Camera transport (Wi-Fi or Bluetooth Classic) is configured separately —
     see "Choose your camera transport" below. -->
<key>UIBackgroundModes</key>
<array>
    <string>bluetooth-peripheral</string>
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

#### Choose your camera transport: Wi‑Fi (recommended) or Bluetooth Classic

The DAT SDK streams video over one of two high-bandwidth links to the glasses, and on iOS **you select which one purely through `Info.plist` + entitlements — there is no runtime switch.** Configure exactly one.

**Wi‑Fi (recommended).** Higher bandwidth (better resolution / frame rate, faster photo capture). On the first stream the SDK joins the glasses' Wi‑Fi access point, so iOS shows a one-time *"Join Wi‑Fi Network"* prompt and the phone associates to that AP — its internet then rides cellular, which matters if you also upload frames to the cloud. **Trade-off:** that Wi‑Fi association makes `startStreamSession()` noticeably slower — expect roughly **10 seconds** more before the first frame arrives, vs. Bluetooth Classic's near-instant connect. Add to `Info.plist`:

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>Allows your phone to find and connect to your glasses over Wi-Fi.</string>
<key>NSBonjourServices</key>
<array>
    <string>_bonjour._tcp</string>
</array>
```

and add these to your app's `.entitlements` (in Xcode: **Signing & Capabilities → + Capability → Access Wi‑Fi Information** and **Hotspot Configuration** — which wires the file to the target via `CODE_SIGN_ENTITLEMENTS` and provisions the capabilities on your App ID; a hand-created `.entitlements` file is silently ignored until that build setting points at it in every Runner build configuration):

```xml
<key>com.apple.developer.networking.HotspotConfiguration</key>
<true/>
<key>com.apple.developer.networking.wifi-info</key>
<true/>
```

Do **not** add the ExternalAccessory keys below — while they are present the SDK fills its high-bandwidth lease over Bluetooth Classic and never brings up Wi‑Fi.

**Bluetooth Classic.** Connects almost instantly (no Wi‑Fi association step), no Wi‑Fi prompt, keeps the phone on its normal Wi‑Fi, and needs no Wi‑Fi infrastructure — but lower bandwidth. Add to `Info.plist`:

```xml
<key>UISupportedExternalAccessoryProtocols</key>
<array>
    <string>com.meta.ar.wearable</string>
</array>

<key>UIBackgroundModes</key>
<array>
    <string>bluetooth-peripheral</string>
    <string>external-accessory</string>
</array>
```

> The example app is configured for **Bluetooth Classic**, not the Wi‑Fi transport recommended above, and that is deliberate: Wi‑Fi needs the *Access WiFi information* and *Hotspot* capabilities, and per Apple's [supported capabilities table](https://developer.apple.com/help/account/reference/supported-capabilities-ios/) neither is available to a free Apple Developer account. Bluetooth Classic needs no entitlements at all (`UISupportedExternalAccessoryProtocols` is an `Info.plist` key, not a capability), so the example signs and runs on a free account. It also connects near-instantly, where Wi‑Fi adds roughly 10 seconds before the first frame while the phone associates to the glasses' access point.
>
> Wi‑Fi remains the recommendation for production apps that need the bandwidth. Both recipes are one comment-block apart in [`example/ios/Runner/Info.plist`](example/ios/Runner/Info.plist) and [`example/ios/Runner/Runner.entitlements`](example/ios/Runner/Runner.entitlements) — switch, then delete the app from the device before reinstalling so stale accessory pairing state doesn't keep the old transport.

> **App Store note.** Transport choice does **not** affect App Store eligibility. The DAT SDK links `ExternalAccessory.framework` regardless of transport (Apple's binary scanner flags this MFi dependency); see [Publishing and availability](#publishing-and-availability) for current program eligibility. Wi‑Fi's advantage is bandwidth, not publishability.

#### Migrating or switching camera transport

Switching transport — whether upgrading an older app or troubleshooting one that isn't working — is a **config-only change**: remove one recipe's keys above, add the other's, rebuild. No plugin update or Dart code change is involved.

- **Upgrading an app configured before this transport choice was documented.** Your `Info.plist` likely already has `UISupportedExternalAccessoryProtocols` (`com.meta.ar.wearable`) and `external-accessory` — that's the Bluetooth Classic recipe above, and it keeps working unchanged. Wi‑Fi is optional; migrate whenever it's convenient using the steps below.
- **One transport isn't working.** Wi‑Fi never shows the join prompt, the phone won't associate to the glasses' AP, or Bluetooth Classic streaming is unreliable: switch to the other transport with the same steps — the two are otherwise interchangeable.

**To switch to Wi‑Fi:**
1. Remove `UISupportedExternalAccessoryProtocols` and `external-accessory` (from `UIBackgroundModes`) from `Info.plist`.
2. Add the two Wi‑Fi `Info.plist` keys and the two entitlements from the Wi‑Fi recipe above.
3. **Don't skip the entitlements wiring** — the most common reason this migration silently "does nothing" is an `.entitlements` file that was created but never attached to the target. Add the capabilities via Xcode (**Signing & Capabilities → + Capability → Access Wi‑Fi Information** + **Hotspot Configuration**), which wires `CODE_SIGN_ENTITLEMENTS` automatically — or if editing `project.pbxproj` by hand, confirm `CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;` is set in **every** Runner build configuration (Debug, Release, Profile): `grep CODE_SIGN_ENTITLEMENTS ios/Runner.xcodeproj/project.pbxproj`.
4. Delete the app from your test device before reinstalling — this clears any stale Bluetooth Classic accessory pairing state — then rebuild. The first stream should show the "Join Wi‑Fi Network" prompt.

**To switch to Bluetooth Classic:** remove the Wi‑Fi `Info.plist` keys and entitlements, add the ExternalAccessory keys from the Bluetooth Classic recipe above, rebuild. No prompt, no entitlements needed.

### Android Configuration

**Minimum SDK:** Android API 29 (Android 10).

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

    <!-- For a registered app (not Developer Mode), add its client token. -->
    <meta-data
        android:name="com.meta.wearable.mwdat.CLIENT_TOKEN"
        android:value="YOUR_CLIENT_TOKEN" />

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

### Opting out of DAT crash reporting

The DAT SDK reports its own crashes to Meta by default. Opting out is host-app configuration only — there is no plugin API for it.

iOS: add a `CrashReporting` entry **inside the `MWDAT` dictionary you already declared above**, alongside `Analytics` — do not add a second `MWDAT` key.

```xml
<key>MWDAT</key>
<dict>
    <!-- ...AppLinkURLScheme, MetaAppID, ClientToken, TeamID as above... -->
    <key>Analytics</key>
    <dict>
        <key>OptOut</key>
        <true/>
    </dict>
    <key>CrashReporting</key>
    <dict>
        <key>OptOut</key>
        <true/>
    </dict>
</dict>
```

Android, in `AndroidManifest.xml` inside `<application>`:

```xml
<meta-data
    android:name="com.meta.wearable.mwdat.CRASH_REPORTING_OPT_OUT"
    android:value="true" />
```

## Integration Lifecycle

The plugin follows Meta's integration lifecycle as documented in the [Meta Wearables Developer Documentation](https://wearables.developer.meta.com/docs/build-overview):

### 0. Android Permissions (Android only)
- Call `MetaWearablesDat.requestAndroidPermissions()` before any other DAT calls
- This requests the Bluetooth runtime permission and initializes the DAT SDK. `INTERNET` must also be declared in the manifest, but Android grants it at install time.
- **Important:** On Android, the DAT SDK is not initialized until these permissions are granted. This is critical for device discovery to work correctly.
- No-op on iOS

### 1. Registration (One-time)
- User taps a call-to-action in your app (e.g., "Connect my glasses")
- Call `MetaWearablesDat.startRegistration()` to open the Meta AI app
- User confirms the connection in Meta AI app
- Meta AI returns to your app via deep link
- Handle the callback URL with `MetaWearablesDat.handleUrl(url)` to complete registration
- Call `MetaWearablesDat.restartActiveDeviceMonitoring()` after registration so device discovery resumes on both platforms
- Monitor registration state via `MetaWearablesDat.registrationStateStream()`
- Monitor active device availability via `MetaWearablesDat.activeDeviceStream()`
- List the paired glasses (name, model, and which pair is streaming) via `MetaWearablesDat.getDevices()` — useful when more than one pair is paired. The list stays empty until registration has completed *and* camera permission has been granted
- To unregister later, call `MetaWearablesDat.disconnect()` — like registration, it opens the Meta AI app and completes through the same deep-link → `handleUrl` callback

### 2. Permissions (First-time camera access)
- When your app first attempts to access the camera, request permission
- Call `MetaWearablesDat.requestCameraPermission()` to show the Meta AI permission bottom sheet
- User can allow always, allow once, or deny
- A `false` return means the user denied the request; SDK-side failures (glasses unreachable, Meta AI app missing, …) throw a typed `CameraPermissionException` instead
- Check the current status at any time with `MetaWearablesDat.getCameraPermissionStatus()`

### 3. Session (After registration and permissions)
- Once registered and permissions are granted, start a streaming session
- Call `MetaWearablesDat.startStreamSession(deviceId)` — pass a `WearableDevice.id` from `getDevices()` to stream from a specific pair, or `null` to auto-select the active one. Returns a `textureId`
- Render the live video feed using Flutter's `Texture` widget with the returned ID
- Size it correctly with `MetaWearablesDat.videoStreamSizeStream()` — it emits the stream's pixel dimensions on start and on resolution changes; wrap the `Texture` in an `AspectRatio` driven by `VideoStreamSize.aspectRatio` so frames aren't stretched
- Monitor session state via `MetaWearablesDat.streamSessionStateStream()`
- Monitor errors via `MetaWearablesDat.streamSessionErrorStream()`
- (Optional) Pin which pair streams by passing its `WearableDevice.id`; switching to a *different* pair while one is streaming throws a `PlatformException` with code `STREAM_ACTIVE` — stop the current stream first
- (Optional) Monitor device thermal level via `MetaWearablesDat.deviceStateStream()` to warn the user *before* a thermal error stops the stream
- (Optional) On `datAppOnTheGlassesUpdateRequired`, call `MetaWearablesDat.openDATGlassesAppUpdate()` to drive a "tap to update" UI
- Call `MetaWearablesDat.stopStreamSession(deviceId)` to end the session

```dart
// Start streaming — returns a texture ID for zero-copy rendering.
// Pass null to auto-select the active pair, or a WearableDevice.id from
// getDevices() to stream from a specific pair.
final textureId = await MetaWearablesDat.startStreamSession(
  null,
  fps: 24,
  streamQuality: StreamQuality.low,
  videoCodec: VideoCodec.raw, // or VideoCodec.hvc1 (iOS only, supports background streaming)
);

// Render the live video feed — wrap the Texture in an AspectRatio driven by
// videoStreamSizeStream() so frames aren't stretched.
Texture(textureId: textureId);
MetaWearablesDat.videoStreamSizeStream().listen((size) {
  // => AspectRatio(aspectRatio: size.aspectRatio, child: Texture(...))
  print('Video: ${size.width}x${size.height}');
});

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

// (Optional) List the paired glasses — names, models, and which pair is
// streaming. Handy when two pairs of the same model are paired.
final devices = await MetaWearablesDat.getDevices();
for (final d in devices) {
  print('${d.name} (${d.type.code})'
      '${d.isStreamingDevice ? ' — streaming' : ''}');
}

// Capture a photo during streaming
final photo = await MetaWearablesDat.capturePhoto(
  null,
  // iOS: choose jpeg or heic. Android: the device chooses the returned format.
  format: PhotoCaptureFormat.jpeg,
);

// Stop streaming when done
await MetaWearablesDat.stopStreamSession(null);
```

Video frames are pushed directly from native (CVPixelBuffer on iOS, SurfaceTexture on Android) to the Flutter engine — no JPEG encoding, no byte copying, no Dart-side decoding.

Store every `StreamSubscription` created for registration, device, session, error, thermal, or frame streams, and cancel it from your widget or provider's `dispose()` method.

#### Video codecs

| Codec             | Platform      | Description                                                                                                                                                                                                                                                                                          |
|-------------------|---------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `VideoCodec.raw`  | iOS & Android | Raw uncompressed frames. iOS: BGRA pixel data. Android: I420 planar YUV. Default.                                                                                                                                                                                                                    |
| `VideoCodec.hvc1` | iOS only      | Compressed HEVC (`hvc1` NAL units) decoded via `VTDecompressionSession`. Smaller over-the-wire payload than `raw`. The hardware decoder is paused on background entry and recreated on the first frame after foreground, so a resumed stream stalls briefly waiting for a keyframe. Ignored on Android. |

For full background streaming (app backgrounded, phone locked, or both) on **either** platform and **either** codec, see [Background streaming](#background-streaming) below.

#### Background streaming

**By default, the plugin stops the stream session when your app is no longer visible.** Call `enableBackgroundStreaming()` **before** `startStreamSession()` to keep it alive instead.

| `enableBackgroundStreaming()` | App backgrounded, or phone locked |
| --- | --- |
| **not called** (default) | Session is **stopped**. You get `stoppedForBackground` on `streamSessionErrorStream()`, then a terminal `stopped`, and the texture is released. Nothing resumes on foreground. |
| **called** | Session stays alive. The preview resumes on foreground (brief keyframe-wait stall on `hvc1`). |

This covers all three "not visible" states: the app sent to background, the screen locked while the app is in front, and both combined.

**Bluetooth Classic cost (iOS).** On the Bluetooth Classic transport, expect reduced frame rates the whole time background streaming is enabled — foreground included (measured: a 24 fps medium stream averages ~14 fps), and under marginal radio conditions high-fps streams can stall. Prefer 15 fps or lower while enabled, or the Wi-Fi transport, which does not carry this cost. Android is unaffected. The frame-rate cost is measured; the mechanism is not settled — radio contention is the leading explanation, but the session no longer requests Bluetooth HFP and should not be claiming a Bluetooth route at all. See [Diagnosing the audio route](#diagnosing-the-audio-route-ios) to check what your app's session actually claims.

**What counts as backgrounded.** Only a genuine background transition. These do **not** stop a stream: Control Center, the notification shade, the app-switcher preview, an incoming-call banner, Face ID and system alerts on iOS; rotation, split-screen and multi-window on Android. Lingering in Android's Recents *does*, because the Activity genuinely stops — a platform difference with no equivalent on iOS.

**You must handle the terminal `stopped`.** Subscribe to `streamSessionStateStream()` and clear your texture id when it arrives:

```dart
MetaWearablesDat.streamSessionStateStream().listen((state) {
  if (state == StreamSessionState.stopped) {
    setState(() { _textureId = null; _isStreaming = false; });
  }
});
```

An app that caches the texture id without listening will render an unregistered texture — black or frozen — after any background round trip.

**Do not add your own lifecycle handling.** The plugin observes lifecycle natively; driving stop/start from a `WidgetsBindingObserver` on top would double-tear-down. And do not auto-retry on `stoppedForBackground`: it is not a failure, and `startStreamSession()` refuses with `APP_BACKGROUNDED` while the app is backgrounded anyway.

You can read the current state with `MetaWearablesDat.isBackgroundStreamingEnabled()`, which reads the native flag. Seed any UI toggle from it rather than from Dart state — a hot restart resets the isolate while the audio session or foreground service keeps running. Don't persist the toggle across launches: neither keep-alive survives process death, so it is genuinely off on a cold start.

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

final textureId = await MetaWearablesDat.startStreamSession(null);

// ...later, when you no longer need background execution:
await MetaWearablesDat.stopStreamSession(null);
await MetaWearablesDat.disableBackgroundStreaming();
```

**iOS — required `Info.plist` additions.** In addition to the default entries from [Setup → iOS](#ios-configuration), add `audio` and `bluetooth-central` to `UIBackgroundModes`:

```xml
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
    <string>bluetooth-central</string>
    <string>bluetooth-peripheral</string>
    <string>external-accessory</string> <!-- only if using the Bluetooth Classic transport -->
</array>
```

Also add `NSMicrophoneUsageDescription` if your app doesn't already declare it. The keep-alive session uses the `.playAndRecord` category, so iOS treats the app as microphone-capable and terminates it on activation without a usage string — even though the plugin records no audio and engages no input:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>Keeps the connection to your glasses alive while the app is in the background.</string>
```

**Android — no manual manifest changes needed.** The plugin's manifest auto-merges the required permissions (`FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_CONNECTED_DEVICE`, `WAKE_LOCK`, `POST_NOTIFICATIONS`) and declares the internal foreground service. On Android 13+ (API 33+), the first call to `enableBackgroundStreaming()` prompts the user for `POST_NOTIFICATIONS` — if denied, the foreground service still runs (so the stream survives), but its notification is suppressed by the OS until the user enables notifications for your app in system settings.

**How it works.** On iOS the plugin activates an `AVAudioSession` (`.playAndRecord` / `.videoRecording` + `.mixWithOthers`), which keeps the process scheduled in background. Bluetooth HFP is deliberately **not** requested: it exists for glasses-mic capture and would flip the glasses from A2DP to an 8 kHz SCO link that contends with the video transport. Configure HFP yourself if your app needs the glasses microphone. The HEVC hardware decoder is invalidated on background entry (iOS forbids GPU access from backgrounded apps) and lazily recreated on the first frame after foreground — you'll see a brief stall while the decoder waits for the next keyframe, then streaming resumes cleanly. While backgrounded, the raw hvc1 NAL bytes still reach `videoFramesStream()` for recording. On Android the plugin starts a foreground service of type `connectedDevice` with your notification and holds a `PARTIAL_WAKE_LOCK` until you disable it.

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

Valid FPS values: 2, 7, 15, 24, 30. Defaults: `StreamQuality.high` at 30 FPS with `VideoCodec.raw`.

Bandwidth is adaptive: on a constrained link the SDK first steps the resolution down one tier, then reduces the frame rate (never below 15 FPS), and applies per-frame compression throughout — so a stream can report `high` yet look soft. Requesting a lower resolution or FPS often yields *better* visual quality on a constrained link.

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
  flutter_meta_wearables_dat: ^0.9.0
  flutter_meta_wearables_dat_mock_device: ^0.9.0
```

```dart
import 'package:flutter_meta_wearables_dat_mock_device/flutter_meta_wearables_dat_mock_device.dart';

// Grant the perms the SDK normally asks for at runtime so the mock flow doesn't
// bounce through Meta AI for registration during dev.
await MetaWearablesDatMockDevice.configure(
  initiallyRegistered: true,
  initialPermissionsGranted: true,
);

// Pick any model via GlassesModel; defaults to GlassesModel.rayBanMeta.
final uuid = await MetaWearablesDatMockDevice.pairGlasses();
await MetaWearablesDatMockDevice.powerOn(uuid);
await MetaWearablesDatMockDevice.don(uuid);
await MetaWearablesDatMockDevice.setCameraFacing(uuid, CameraFacing.back);

// From here, the core plugin's normal streaming API works against this UUID:
final textureId = await MetaWearablesDat.startStreamSession(uuid);
```

Apps that pull in this package **must** declare `NSCameraUsageDescription` (iOS) and the `CAMERA` permission (Android) — the mock device uses the phone's camera as the simulated glasses feed. The `Permission`, `PermissionStatus`, `CameraFacing`, and `GlassesModel` enums all live in this package.

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
- **Wi‑Fi never prompts, or one transport streams unreliably** — see [Migrating or switching camera transport](#migrating-or-switching-camera-transport); switching between Wi‑Fi and Bluetooth Classic is a config-only change, no code required.
- **Registration deep link not returning** — If registration opens the Meta AI app but the callback does not return to your app, verify that your URL scheme matches the one registered in the [Meta Wearables Developer Center](https://wearables.developer.meta.com/devcenter). On iOS, ensure `CFBundleURLSchemes` in `Info.plist` (and `AppLinkURLScheme` in the `MWDAT` dict) use the same scheme. On Android, ensure the `data android:scheme` in your activity's intent-filter matches that scheme.

### Diagnosing the audio route (iOS)

Relevant when background streaming is enabled and frame rates drop on the Bluetooth Classic transport. The keep-alive `AVAudioSession` logs its route on activation and on every route change, so you can see what your app's session actually claims without a reproduction:

```
[MWDAT-ROUTE] after activation — in=[MicrophoneBuiltIn:iPhone Microphone] out=[Receiver:Receiver]
```

Filter the device console for `[MWDAT-ROUTE]`. What to look for:

- **Only built-in ports**, as above — the session is not on the Bluetooth link. Frame-rate loss here is *not* audio-route contention; report it with the log attached.
- **Any `Bluetooth…` port** in `in=` or `out=` — the session has claimed the Bluetooth radio the video transport needs. This is what a misconfigured category looks like; the plugin itself no longer requests HFP, so the usual cause is the host app configuring its own `AVAudioSession` elsewhere.

If your app manages its own audio session, it is the last writer that wins — the plugin sets the category once at activation and does not reassert it.

**Still having issues?** — Open a [GitHub issue](https://github.com/rodcone/flutter_meta_wearables_dat/issues) with all the details you can provide. This helps us pinpoint the problem and assist you more efficiently.

## Example app

The [example app](https://github.com/rodcone/flutter_meta_wearables_dat/tree/main/example) is a Flutter port of Meta's native Camera Access sample. It exercises the full lifecycle — registration, permissions, streaming, photo capture, background streaming, thermal monitoring, and the mock device add-on.

## Contributing

Contributions are welcome! Feel free to open [issues](https://github.com/rodcone/flutter_meta_wearables_dat/issues) for bugs or feature requests, and [pull requests](https://github.com/rodcone/flutter_meta_wearables_dat/pulls) for improvements.

## License

MIT License — see [LICENSE](LICENSE) for details.
