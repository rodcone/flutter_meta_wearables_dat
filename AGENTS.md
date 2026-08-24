# flutter_meta_wearables_dat

Flutter plugin providing a bridge to Meta's Wearables Device Access Toolkit (DAT) for integration with Meta AI Glasses (Ray-Ban Meta). Supports iOS (17.2+) and Android (API 29+).

- **pub.dev**: https://pub.dev/packages/flutter_meta_wearables_dat
- **GitHub**: https://github.com/rodcone/flutter_meta_wearables_dat
- **Example app**: https://github.com/rodcone/flutter_meta_wearables_dat/tree/main/example

## Code style

- All DAT calls go through `MetaWearablesDat` static methods — never instantiate the class
- Use `Provider`/`ChangeNotifier` for state management (see example app)
- Use `async`/`await` for all DAT operations
- Use `Stream` subscriptions for reactive state (registration, device availability, session state, errors)
- Dispose all stream subscriptions in your provider/widget `dispose()`
- Handle `PlatformException` for method channel errors

## Architecture

```
MetaWearablesDat (static API facade)
    ↓
MetaWearablesDatPlatform (abstract contract)
    ↓
MethodChannelMetaWearablesDat (method/event channel impl)
    ↓
Native: iOS (Swift) | Android (Kotlin)
```

Single import: `import 'package:flutter_meta_wearables_dat/flutter_meta_wearables_dat.dart';`

Communication:
- **Method channel** `flutter_meta_wearables_dat` — request/response calls
- **Event channels** — reactive streams for state changes

## Key types

### Enums

| Enum | Values |
|------|--------|
| `RegistrationState` | `unavailable(0)`, `available(1)`, `registering(2)`, `registered(3)` |
| `VideoCodec` | `raw('raw')`, `hvc1('hvc1')` |
| `StreamQuality` | `high('high')`, `medium('medium')`, `low('low')` |
| `StreamSessionState` | `stopping(0)`, `stopped(1)`, `waitingForDevice(2)`, `starting(3)`, `streaming(4)`, `paused(5)` |
| `PhotoCaptureFormat` | `heic('heic')`, `jpeg('jpeg')` |
| `FrameFormat` | `rawRgba`, `rawStraightRgba`, `png` |
| `ThermalLevel` | `unknown(0)`, `none(1)`, `light(2)`, `moderate(3)`, `severe(4)`, `critical(5)`, `emergency(6)`, `shutdown(7)` |
| `WearableDeviceType` | `rayBanMeta`, `oakleyMetaHSTN`, `oakleyMetaVanguard`, `metaRayBanDisplay`, `rayBanMetaOptics`, `unknown` |
| `WearableLinkState` | `disconnected`, `connecting`, `connected`, `unknown` |
| `WearableCompatibility` | `undefined`, `compatible`, `deviceUpdateRequired`, `sdkUpdateRequired` |

### Classes

| Class | Key properties |
|-------|---------------|
| `StreamSessionError` | `code` (String), `message` (String), `isThermalCritical`, `isHingesClosed`, `isPermissionDenied` |
| `CameraPermissionException` | `code`, `message`, `details`, `isDeviceDisconnected`, `isPermissionDenied`, `isInternalError` |
| `CapturedPhoto` | `bytes` (Uint8List), `format` (String), `fileExtension`, `mimeType` |
| `CapturedFrame` | `bytes` (Uint8List), `width`, `height`, `format` (FrameFormat) |
| `VideoStreamSize` | `width`, `height`, `aspectRatio` |
| `VideoFrame` | `codec` (VideoCodec), `bytes` (Uint8List), `width`, `height`, `presentationTimestampUs`, `isKeyframe` |
| `BackgroundNotification` | `title`, `text`, `channelId`, `channelName`, `iconResourceName?` (Android only) |
| `DeviceState` | `thermalLevel` (ThermalLevel) |
| `WearableDevice` | `id`, `name`, `type` (WearableDeviceType), `linkState` (WearableLinkState), `compatibility` (WearableCompatibility), `supportsDisplay`, `isActive`, `isStreamingDevice`, `firmwareInfo?` |

### Error codes (StreamSessionError)

| Code | Meaning |
|------|---------|
| `internalError` | Internal SDK error |
| `deviceNotFound` | No matching device available |
| `deviceNotConnected` | Device is not connected |
| `timeout` | Operation timed out |
| `videoStreamingError` | Video stream failed |
| `permissionDenied` | Camera permission denied |
| `hingesClosed` | Glasses folded shut **or taken off**. The SDK does not auto-resume — the user puts them back on, then you start a new session |
| `thermalCritical` | Device thermal state is critical — streaming pauses |
| `thermalEmergency` | Device thermal state is emergency — streaming stopped. **iOS only**; on Android this arrives as `deviceThermalEmergency` |
| `peakPowerShutdown` | Device exceeded peak power limit — streaming stopped |
| `batteryCritical` | Device battery critically low — streaming stopped |
| `deviceThermalEmergency` / `devicePeakPowerShutdown` / `deviceBatteryCritical` | Device-session-level variants of the above — the session itself goes down, not just the stream |
| `deviceThermalCritical` | Device-session-level thermal warning. Like `thermalCritical`, it **pauses**; the session stays up |
| `sessionEndedByDevice` | The device ended the session; the stream stops with it. **Android only** |
| `capabilityDenied` | The device refused the requested capability. **Android only** |
| `datAppOnTheGlassesUpdateRequired` | The on-device DAT app needs updating. Call `MetaWearablesDat.openDATGlassesAppUpdate()` to prompt the user. |
| `dwaUnavailable` | The DAT Wearables App is unavailable on the glasses |

Photo-capture failure never appears here — it rejects the `capturePhoto()` future instead (`CAPTURE_PHOTO_FAILED`, with `details` carrying the granular reason).

Codes that leave the stream dead with no auto-resume need a **teardown**, not a retry: clear your texture ID and streaming flag, or the `Texture` widget freezes on its last frame. Those are `hingesClosed`, `permissionDenied`, `thermalEmergency`, `peakPowerShutdown`, `batteryCritical`, `deviceThermalEmergency`, `devicePeakPowerShutdown`, `deviceBatteryCritical` and `sessionEndedByDevice`.

`thermalCritical` and `deviceThermalCritical` are **not** in that list — they pause rather than end the stream, and the session stays up. Treat them as a warning (surface it, keep rendering) and use `deviceStateStream()` to react before the device reaches the emergency tier.

## API reference

```dart
// Registration
static Future<bool> startRegistration()
static Future<bool> handleUrl(String url)
static Future<bool> disconnect()
static Future<RegistrationState> getRegistrationState()
static Stream<RegistrationState> registrationStateStream()

// Permissions
static Future<bool> requestAndroidPermissions()   // No-op on iOS
static Future<bool> requestCameraPermission()
static Future<bool> getCameraPermissionStatus()

// Device monitoring
static Stream<bool> activeDeviceStream()
static Future<List<WearableDevice>> getDevices()  // paired glasses; isStreamingDevice/isActive flag the streaming/selected pair. Android throws NOT_INITIALIZED before BT permission
static Future<bool> restartActiveDeviceMonitoring()  // No-op on iOS

// Streaming
static Future<int> startStreamSession(
  String? deviceId, { // WearableDevice.id (getDevices) pins a pair; null = auto-select
  double fps = 30.0,
  StreamQuality streamQuality = StreamQuality.high,
  VideoCodec videoCodec = VideoCodec.raw,
})  // Returns textureId. Throws PlatformException 'STREAM_ACTIVE' if a different device is already streaming
static Future<bool> stopStreamSession(String? deviceId)
static Stream<StreamSessionState> streamSessionStateStream()
static Stream<StreamSessionError> streamSessionErrorStream()
static Stream<VideoStreamSize> videoStreamSizeStream()

// Background streaming (opt-in; call before startStreamSession)
static Future<void> enableBackgroundStreaming({
  BackgroundNotification? androidNotification, // required on Android
})
static Future<void> disableBackgroundStreaming()
static Stream<VideoFrame> videoFramesStream()   // foreground + background

// Device state (thermal) — live ThermalLevel updates from the active device.
// Useful for warning the user *before* a thermalCritical error stops the stream.
static Stream<DeviceState> deviceStateStream()

// Navigation — opens the Meta AI app to the DAT-app-update screen on the
// glasses. Pair with the `datAppOnTheGlassesUpdateRequired` error code to drive
// a "tap to update" UI; the SDK refuses to stream until the on-device DAT app
// is current. Throws `metaAINotInstalled` or `notRegistered` PlatformException.
static Future<bool> openDATGlassesAppUpdate()

// Photo capture
static Future<CapturedPhoto> capturePhoto(
  String? deviceId, {
  PhotoCaptureFormat format = PhotoCaptureFormat.jpeg,
})

// Frame capture (Dart-side rasterization, no native call)
static Future<CapturedFrame?> captureStreamFrame(
  int textureId, {
  int width = 720,
  int height = 1280,
  FrameFormat format = FrameFormat.rawRgba,
})

// Mock device APIs live in the optional companion package
// `flutter_meta_wearables_dat_mock_device` — see "Testing with MockDeviceKit".
```

## Dev environment setup

### 1. Add dependency

```bash
flutter pub add flutter_meta_wearables_dat
```

### 2. iOS configuration

**Minimum deployment target:** iOS 17.2

Add to `Info.plist`:

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

<!-- Deep link callback from Meta AI app -->
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>myexampleapp</string>
        </array>
    </dict>
</array>

<key>MWDAT</key>
<dict>
    <key>AppLinkURLScheme</key>
    <string>myexampleapp://</string>
    <key>MetaAppID</key>
    <string>0</string> <!-- Use 0 for Developer Mode -->
    <key>ClientToken</key>
    <string>YOUR_CLIENT_TOKEN</string>
    <key>TeamID</key>
    <string>$(DEVELOPMENT_TEAM)</string>
    <key>Analytics</key>
    <dict>
        <key>OptOut</key>
        <true/>
    </dict>
</dict>
```

#### Choose your camera transport: Wi‑Fi (recommended) or Bluetooth Classic

The SDK streams over one of two high-bandwidth links; on iOS you pick which **purely via `Info.plist` + entitlements** (no runtime switch). Configure exactly one.

**Wi‑Fi (recommended)** — higher bandwidth. Triggers a one-time *"Join Wi‑Fi Network"* prompt and joins the glasses' AP (phone internet then rides cellular). **Trade-off:** that AP association makes `startStreamSession()` roughly **10 seconds** slower to first frame than Bluetooth Classic's near-instant connect. Add to `Info.plist`:

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>Allows your phone to find and connect to your glasses over Wi-Fi.</string>
<key>NSBonjourServices</key>
<array>
    <string>_bonjour._tcp</string>
</array>
```

plus a `.entitlements` file wired to the target via `CODE_SIGN_ENTITLEMENTS` (Xcode → Signing & Capabilities → add **Access Wi‑Fi Information** + **Hotspot Configuration** does this automatically; a hand-created file is silently ignored until that build setting points at it in every Runner configuration):

```xml
<key>com.apple.developer.networking.HotspotConfiguration</key>
<true/>
<key>com.apple.developer.networking.wifi-info</key>
<true/>
```

Do **not** add the ExternalAccessory keys below — while present, the SDK uses Bluetooth Classic and never brings up Wi‑Fi.

**Bluetooth Classic** — connects almost instantly, no prompt, keeps the phone on its normal Wi‑Fi, works offline, but lower bandwidth. Add to `Info.plist`:

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

> **App Store note:** transport does not affect App Store eligibility — the DAT SDK links `ExternalAccessory.framework` regardless of transport (an MFi binary-scanner concern), and Meta limits public publishing to select partners until GA. Wi‑Fi's advantage is bandwidth, not publishability.

#### Migrating or switching camera transport

Switching transport is a **config-only change** — no plugin update or Dart code involved. Two scenarios:

- **Upgrading an app configured before this transport choice was documented** — it already has `com.meta.ar.wearable` + `external-accessory` (Bluetooth Classic) and keeps working unchanged; migrating to Wi‑Fi is optional.
- **One transport isn't working** — Wi‑Fi never prompts / won't join the AP, or Bluetooth Classic streaming is unreliable — switch to the other the same way.

**To switch to Wi‑Fi:** remove `UISupportedExternalAccessoryProtocols` + `external-accessory`, add the Wi‑Fi `Info.plist` keys + entitlements above, then **verify the entitlements wiring** — a `.entitlements` file is silently ignored unless `CODE_SIGN_ENTITLEMENTS` points at it in every Runner build configuration (Xcode → Signing & Capabilities → add the two capabilities does this automatically; check by hand with `grep CODE_SIGN_ENTITLEMENTS ios/Runner.xcodeproj/project.pbxproj`). Delete the app from the test device before reinstalling to clear stale Bluetooth Classic accessory state, then rebuild.

**To switch to Bluetooth Classic:** remove the Wi‑Fi keys + entitlements, add the ExternalAccessory keys above, rebuild.

### 3. Android configuration

**AndroidManifest.xml:**

```xml
<uses-permission android:name="android.permission.BLUETOOTH" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.INTERNET" />

<application>
    <meta-data
        android:name="com.meta.wearable.mwdat.APPLICATION_ID"
        android:value="0" /> <!-- Use 0 for Developer Mode -->

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

**settings.gradle.kts** — Add GitHub Packages repository:

```kotlin
import java.util.Properties
import kotlin.io.path.div
import kotlin.io.path.exists
import kotlin.io.path.inputStream

val localProperties =
    Properties().apply {
        val localPropertiesPath = rootDir.toPath() / "local.properties"
        if (localPropertiesPath.exists()) {
            load(localPropertiesPath.inputStream())
        }
    }

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.PREFER_SETTINGS)
    repositories {
        google()
        mavenCentral()
        maven {
            url = uri("https://maven.pkg.github.com/facebook/meta-wearables-dat-android")
            credentials {
                username = ""
                password = System.getenv("GITHUB_TOKEN") ?: localProperties.getProperty("github_token")
            }
        }
    }
}
```

Set a GitHub token with `read:packages` scope via `GITHUB_TOKEN` env var or `github_token` in `local.properties`.

**MainActivity** — Must extend `FlutterFragmentActivity` (not `FlutterActivity`):

```kotlin
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity()
```

### 4. Deep link setup

Add the `app_links` package to handle registration callbacks:

```bash
flutter pub add app_links
```

Listen for incoming URIs and forward them to the DAT plugin:

```dart
final appLinks = AppLinks();
appLinks.uriLinkStream.listen((uri) {
  MetaWearablesDat.handleUrl(uri.toString());
});
```

## Integration lifecycle

Four-phase flow. Order matters.

### Phase 0: Android permissions (Android only)

```dart
// Must be called before any other DAT call on Android.
// Gates SDK initialization — critical for device discovery.
// No-op on iOS, safe to always call.
await MetaWearablesDat.requestAndroidPermissions();
```

### Phase 1: Registration (one-time)

```dart
// Listen to state changes BEFORE starting
final sub = MetaWearablesDat.registrationStateStream().listen((state) {
  // RegistrationState: unavailable, available, registering, registered
});

// Opens Meta AI app for user confirmation
await MetaWearablesDat.startRegistration();

// Handle deep link callback (in your app_links listener)
await MetaWearablesDat.handleUrl(uri.toString());

// Critical on Android: restart device monitoring after registration
await MetaWearablesDat.restartActiveDeviceMonitoring();
```

### Phase 2: Camera permission (first-time)

```dart
// Shows Meta AI permission bottom sheet
final granted = await MetaWearablesDat.requestCameraPermission();
```

### Phase 3: Streaming

```dart
// Monitor device availability
MetaWearablesDat.activeDeviceStream().listen((hasDevice) {
  // Enable/disable start button
});

// Start streaming — returns texture ID for zero-copy rendering
final textureId = await MetaWearablesDat.startStreamSession(
  null, // null = AutoDeviceSelector (recommended)
  fps: 24,
  streamQuality: StreamQuality.low,
  videoCodec: VideoCodec.raw,
);

// Render live video feed
Texture(textureId: textureId)

// Monitor session state
MetaWearablesDat.streamSessionStateStream().listen((state) {
  // StreamSessionState: stopping, stopped, waitingForDevice, starting, streaming, paused
});

// Monitor errors
MetaWearablesDat.streamSessionErrorStream().listen((error) {
  if (error.isThermalCritical) { /* device overheating */ }
  if (error.isHingesClosed) { /* glasses folded */ }
});

// Capture photo during streaming
final photo = await MetaWearablesDat.capturePhoto(null);

// Stop when done
await MetaWearablesDat.stopStreamSession(null);
```

### Background streaming (optional — both platforms, both codecs)

Opt in **before** `startStreamSession()` to keep the session alive when the app is backgrounded, the phone is locked, or both.

```dart
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

// ...when done:
await MetaWearablesDat.stopStreamSession(null);
await MetaWearablesDat.disableBackgroundStreaming();
```

**Additional iOS `Info.plist` entries** (required only if you call `enableBackgroundStreaming`): add `audio` and `bluetooth-central` alongside `bluetooth-peripheral` (and `external-accessory` only if you use the Bluetooth Classic transport):

```xml
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
    <string>bluetooth-central</string>
    <string>bluetooth-peripheral</string>
    <string>external-accessory</string> <!-- only if using the Bluetooth Classic transport -->
</array>
```

**Android manifest:** nothing to change — the plugin manifest auto-merges `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_CONNECTED_DEVICE`, `WAKE_LOCK` permissions and the internal foreground service. `BackgroundNotification` is required on Android (the OS requires a visible notification for the foreground service).

**How it works.** iOS activates an `AVAudioSession` (`.playAndRecord` / `.videoRecording` + `.allowBluetoothHFP` + `.mixWithOthers`) to keep the process scheduled. The HEVC hardware decoder is invalidated on background entry (iOS forbids GPU access while backgrounded) and lazily recreated on the first frame after foreground — there's a brief stall waiting for the next keyframe but no permanent freeze. While backgrounded, the raw hvc1 NAL bytes are still forwarded to `videoFramesStream()` for recording. Android starts a foreground service of type `connectedDevice` with the provided notification and holds a `PARTIAL_WAKE_LOCK` until you disable it.

**Frames in background.** The `Texture` widget can't render in background (no GPU access). Subscribe to `videoFramesStream()` to receive every frame in both foreground and background — useful for recording, ML, re-muxing:

```dart
final framesSub = MetaWearablesDat.videoFramesStream().listen((frame) {
  // frame.codec                   → VideoCodec.raw | VideoCodec.hvc1
  // frame.bytes                   → Uint8List of the raw codec payload
  // frame.width / frame.height    → pixel dimensions
  // frame.presentationTimestampUs → monotonic, in microseconds
  // frame.isKeyframe              → always true for raw; hvc1 keyframes carry VPS/SPS/PPS
});
```

Codec payload layout:

| Codec | iOS | Android |
|-------|-----|---------|
| `raw` | BGRA, `bytesPerRow * height` bytes (rows may be padded — use `VideoFrame.bytesPerRow`) | I420 planar YUV, `width * height * 3/2` bytes (tightly packed; `bytesPerRow` is `null`) |
| `hvc1` | raw HEVC NAL units (self-contained: keyframes carry VPS/SPS/PPS) | n/a — Android SDK doesn't support `hvc1` |

`videoFramesStream()` is zero-cost when no subscriber is attached. Subscribe **before** `startStreamSession()` to capture the opening keyframe.

**Without `enableBackgroundStreaming()`**, backgrounding the app or locking the phone **stops the stream session** on both platforms as of 0.9.0. The plugin emits `stoppedForBackground` on `streamSessionErrorStream()` followed by a terminal `stopped`, and releases the texture. Nothing resumes on foreground — show a placeholder and let the user restart. `startStreamSession()` refuses with `APP_BACKGROUNDED` while backgrounded. `captureStreamFrame` always returns `null` while backgrounded — use `videoFramesStream()` instead if you need pixel data in background.

### Raw frame capture for ML/OCR

```dart
// Dart-side rasterization — no native call, near-instantaneous
final frame = await MetaWearablesDat.captureStreamFrame(
  textureId,
  width: 720,
  height: 1280,
  format: FrameFormat.rawRgba,
);
// frame.bytes is raw RGBA — feed to ML Kit, Vision, etc.
// ~3.7 MB per frame at 720x1280. Capture every 200-500ms, not every frame.
```

## Platform differences

| Feature | iOS | Android |
|---------|-----|---------|
| Video codec `raw` | Yes (BGRA on the `videoFramesStream`) | Yes (I420 planar YUV on the `videoFramesStream`) |
| Video codec `hvc1` | Yes — decoder auto-paused on background and recreated on foreground (brief keyframe-wait stall) | No (ignored, falls back to raw) |
| `enableBackgroundStreaming()` | Activates `AVAudioSession` to keep the process alive in background. HEVC hardware decoder is invalidated on background and recreated on foreground (brief keyframe-wait stall, no freeze). Requires `audio` + `bluetooth-central` in `UIBackgroundModes` | Starts a foreground service (type `connectedDevice`) + holds a `PARTIAL_WAKE_LOCK`. Requires `BackgroundNotification`. Manifest permissions auto-merge |
| `videoFramesStream()` | Emits BGRA (`raw`) or HEVC NAL units (`hvc1`) | Emits I420 planar YUV (`raw` only) |
| `requestAndroidPermissions()` | No-op | Required before any DAT call |
| `restartActiveDeviceMonitoring()` | No-op | Required after registration |
| Photo format selection | HEIC or JPEG | Device-determined (param ignored) |
| Stream quality | low/medium/high | low/medium/high |
| Valid FPS | 2, 7, 15, 24, 30 | 2, 7, 15, 24, 30 |
| MainActivity requirement | N/A | Must extend `FlutterFragmentActivity` |

## Testing with MockDeviceKit

Develop and test without physical Meta glasses. Mock support lives in the optional companion package `flutter_meta_wearables_dat_mock_device` so production builds don't have to link `MWDATMockDevice` (iOS) or `mwdat-mockdevice` (Android), and therefore don't need `NSCameraUsageDescription` or the `CAMERA` permission.

```yaml
# pubspec.yaml — add only in dev/staging configs
dependencies:
  flutter_meta_wearables_dat: ^0.9.0
  flutter_meta_wearables_dat_mock_device: ^0.9.0
```

```dart
import 'package:flutter_meta_wearables_dat/flutter_meta_wearables_dat.dart';
import 'package:flutter_meta_wearables_dat_mock_device/flutter_meta_wearables_dat_mock_device.dart';

// Pre-grant registration + camera so the mock flow doesn't bounce through Meta AI
await MetaWearablesDatMockDevice.configure(
  initiallyRegistered: true,
  initialPermissionsGranted: true,
);

// Pair a simulated pair of glasses backed by the phone's camera.
// `model` defaults to GlassesModel.rayBanMeta — pass any GlassesModel
// (rayBanMeta, oakleyMetaHSTN, oakleyMetaVanguard, rayBanMetaOptics, metaGlasses).
final deviceUUID = await MetaWearablesDatMockDevice.pairGlasses();

// Simulate glasses lifecycle
await MetaWearablesDatMockDevice.powerOn(deviceUUID!);
await MetaWearablesDatMockDevice.don(deviceUUID);
await MetaWearablesDatMockDevice.setCameraFacing(deviceUUID, CameraFacing.back);

// Override the live camera feed with a video file (must be H.265/HEVC)
await MetaWearablesDatMockDevice.setCameraFeed(deviceUUID, videoPath);

// Override the photo returned by capturePhoto()
await MetaWearablesDatMockDevice.setCapturedImage(deviceUUID, imagePath);

// Streaming, photo capture, etc. all go through the core plugin against this UUID
final textureId = await MetaWearablesDat.startStreamSession(deviceUUID);

// Clean up
await MetaWearablesDatMockDevice.unpairGlasses(deviceUUID);
```

Mock-only types (`Permission`, `PermissionStatus`, `CameraFacing`) are exported from `flutter_meta_wearables_dat_mock_device`. Apps using the mock package **must** declare `NSCameraUsageDescription` (iOS) and the `CAMERA` permission (Android), since the simulated glasses use the phone's camera as their feed.

## Debugging

```
App not connecting?
├── Developer Mode enabled in Meta AI app? (resets after firmware updates)
├── Meta AI app and glasses firmware up to date?
├── Called requestAndroidPermissions() first? (Android only)
├── Registration deep link returning? Check URL scheme matches Developer Center
├── Camera permission granted? Check getCameraPermissionStatus()
└── Device showing as active? Check activeDeviceStream()

Stream not starting?
├── Check streamSessionStateStream() for current state
├── Check streamSessionErrorStream() for errors
├── On Android: MainActivity extends FlutterFragmentActivity?
├── On Android: GitHub token configured for Maven dependency?
└── Try restarting glasses: power off → hold capture button → power on → release when LED turns red

iOS: Wi-Fi never prompts, or one transport streams unreliably?
└── Switch transports — see "Migrating or switching camera transport" (config-only, no code change)
```

## Links

- [Official DAT API reference (llms.txt)](https://wearables.developer.meta.com/llms.txt?full=true)
- [AI-Assisted Development](https://wearables.developer.meta.com/docs/ai-assisted)
- [Developer Documentation](https://wearables.developer.meta.com/docs/develop/)
- [Known Issues](https://wearables.developer.meta.com/docs/knownissues)
- [Version Dependencies](https://wearables.developer.meta.com/docs/version-dependencies)
- [Example app](https://github.com/rodcone/flutter_meta_wearables_dat/tree/main/example)
- [pub.dev](https://pub.dev/packages/flutter_meta_wearables_dat)
