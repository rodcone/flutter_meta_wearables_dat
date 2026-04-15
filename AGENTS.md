# flutter_meta_wearables_dat

Flutter plugin providing a bridge to Meta's Wearables Device Access Toolkit (DAT) for integration with Meta AI Glasses (Ray-Ban Meta). Supports iOS (17.0+) and Android (API 29+).

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

### Classes

| Class | Key properties |
|-------|---------------|
| `StreamSessionError` | `code` (String), `message` (String), `isThermalCritical`, `isHingesClosed`, `isPermissionDenied` |
| `CameraPermissionException` | `code`, `message`, `details`, `isDeviceDisconnected`, `isPermissionDenied`, `isInternalError` |
| `CapturedPhoto` | `bytes` (Uint8List), `format` (String), `fileExtension`, `mimeType` |
| `CapturedFrame` | `bytes` (Uint8List), `width`, `height`, `format` (FrameFormat) |

### Error codes (StreamSessionError)

| Code | Meaning |
|------|---------|
| `internalError` | Internal SDK error |
| `deviceNotFound` | No matching device available |
| `deviceNotConnected` | Device is not connected |
| `timeout` | Operation timed out |
| `videoStreamingError` | Video stream failed |
| `permissionDenied` | Camera permission denied |
| `hingesClosed` | User folded the glasses |
| `thermalCritical` | Device overheating — streaming pauses automatically |

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
static Future<bool> restartActiveDeviceMonitoring()  // No-op on iOS

// Streaming
static Future<int> startStreamSession(
  String? deviceUUID, {
  double fps = 30.0,
  StreamQuality streamQuality = StreamQuality.high,
  VideoCodec videoCodec = VideoCodec.raw,
})  // Returns textureId for Texture widget
static Future<bool> stopStreamSession(String? deviceUUID)
static Stream<StreamSessionState> streamSessionStateStream()
static Stream<StreamSessionError> streamSessionErrorStream()

// Photo capture
static Future<CapturedPhoto> capturePhoto(
  String? deviceUUID, {
  PhotoCaptureFormat format = PhotoCaptureFormat.jpeg,
})

// Frame capture (Dart-side rasterization, no native call)
static Future<CapturedFrame?> captureStreamFrame(
  int textureId, {
  int width = 720,
  int height = 1280,
  FrameFormat format = FrameFormat.rawRgba,
})

// Mock device (testing without physical glasses)
static Future<String?> pairMockRayBanMeta()
static Future<bool> unpairMockRayBanMeta(String deviceUUID)
static Future<bool> mockDevicePowerOn(String deviceUUID)
static Future<bool> mockDevicePowerOff(String deviceUUID)
static Future<bool> mockDeviceDon(String deviceUUID)
static Future<bool> mockDeviceDoff(String deviceUUID)
static Future<bool> setMockCameraFeed(String deviceUUID, String? videoPath)
static Future<bool> setMockCapturedImage(String deviceUUID, String? imagePath)
```

## Dev environment setup

### 1. Add dependency

```bash
flutter pub add flutter_meta_wearables_dat
```

### 2. iOS configuration

**Minimum deployment target:** iOS 17.0

Add to `Info.plist`:

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

### Background streaming (iOS, `hvc1` only)

With `VideoCodec.hvc1` on iOS, the stream session survives app backgrounding — the plugin auto-manages the HEVC decoder lifecycle. No developer action required; do NOT stop/restart the stream session on app lifecycle changes. The underlying `StreamSession` stays alive, rendering resumes instantly on foreground return, and the last frame is preserved so there's no flicker.

Not supported: Android (no `hvc1`), `VideoCodec.raw` (SDK stops frame delivery on background). `captureStreamFrame` returns `null` while backgrounded — pause any frame-capture loops on `AppLifecycleState.paused` using Flutter's `WidgetsBindingObserver`.

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
| Video codec `raw` | Yes | Yes |
| Video codec `hvc1` | Yes — survives backgrounding (decoder auto-paused, session stays alive) | No (ignored, falls back to raw) |
| `requestAndroidPermissions()` | No-op | Required before any DAT call |
| `restartActiveDeviceMonitoring()` | No-op | Required after registration |
| Photo format selection | HEIC or JPEG | Device-determined (param ignored) |
| Stream quality | low/medium/high | low/medium/high |
| Valid FPS | 2, 7, 15, 24, 30 | 2, 7, 15, 24, 30 |
| MainActivity requirement | N/A | Must extend `FlutterFragmentActivity` |

## Testing with MockDeviceKit

Develop and test without physical Meta glasses:

```dart
// Create a mock device
final deviceUUID = await MetaWearablesDat.pairMockRayBanMeta();

// Simulate glasses lifecycle
await MetaWearablesDat.mockDevicePowerOn(deviceUUID!);
await MetaWearablesDat.mockDeviceDon(deviceUUID);

// Set mock camera feed (video must be H.265/HEVC)
await MetaWearablesDat.setMockCameraFeed(deviceUUID, videoPath);

// Set mock captured image (for capturePhoto)
await MetaWearablesDat.setMockCapturedImage(deviceUUID, imagePath);

// Start streaming with specific device
final textureId = await MetaWearablesDat.startStreamSession(deviceUUID);

// Clean up
await MetaWearablesDat.unpairMockRayBanMeta(deviceUUID);
```

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
```

## Links

- [Official DAT API reference (llms.txt)](https://wearables.developer.meta.com/llms.txt?full=true)
- [AI-Assisted Development](https://wearables.developer.meta.com/docs/ai-assisted)
- [Developer Documentation](https://wearables.developer.meta.com/docs/develop/)
- [Known Issues](https://wearables.developer.meta.com/docs/knownissues)
- [Version Dependencies](https://wearables.developer.meta.com/docs/version-dependencies)
- [Example app](https://github.com/rodcone/flutter_meta_wearables_dat/tree/main/example)
- [pub.dev](https://pub.dev/packages/flutter_meta_wearables_dat)
