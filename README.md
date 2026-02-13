![Pub Version](https://img.shields.io/pub/v/flutter_meta_wearables_dat)
![Pub Likes](https://img.shields.io/pub/likes/flutter_meta_wearables_dat)
![Pub Points](https://img.shields.io/pub/points/flutter_meta_wearables_dat)
![Pub Downloads](https://img.shields.io/pub/dm/flutter_meta_wearables_dat)
[![style: very good analysis](https://img.shields.io/badge/style-very_good_analysis-B22C89.svg)](https://pub.dev/packages/very_good_analysis)

# flutter_meta_wearables_dat

<img width="500" height="95" alt="flutter_dat" src="https://github.com/user-attachments/assets/b3958072-1bb5-434d-8006-8f35ae054213" />

A Flutter plugin that provides a bridge to Meta's Wearables Device Access Toolkit (DAT), enabling integration with Meta AI Glasses for iOS and Android.

## Table of contents
- [flutter\_meta\_wearables\_dat](#flutter_meta_wearables_dat)
  - [Table of contents](#table-of-contents)
  - [Publishing disclaimer](#publishing-disclaimer)
  - [Setup](#setup)
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
  - [Example app](#example-app)
  - [Contributing](#contributing)
  - [License](#license)

## Publishing disclaimer

The Meta Wearables Device Access Toolkit is currently in **developer preview**. During this phase:

- You can use the SDK to **build, prototype, and test** your app.
- You can **distribute to testers** within your organization or team (e.g. via the beta testing platform in the [Meta Wearables Developer Center](https://wearables.developer.meta.com/)).
- **Publishing to the general public is limited**: only select partners can publish their DAT integrations to public app stores. Most apps using DAT cannot be published publicly yet.

Meta is running the preview to test, learn, and refine the toolkit; broader publishing (general availability) is planned for 2026. For full details, see [Introducing the Meta Wearables Device Access Toolkit](https://developers.meta.com/blog/introducing-meta-wearables-device-access-toolkit/) and the [Meta Wearables FAQ](https://developer.meta.com/wearables/faq).

## Setup

### iOS Configuration

**Minimum deployment target:** iOS 17.0

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

**Security:** Do not commit real `MetaAppID` or `ClientToken` values to public
repositories. Use placeholders in doc/ and a gitignored config file for local
development (see the [example app README](example/README.md#secrets-setup-required-to-run)
for the xcconfig / secrets.properties pattern used in this project).

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
- Call `MetaWearablesDat.startStreamSession(deviceUUID)` to begin receiving video frames
- Listen to video frames via the `flutter_meta_wearables_dat/video_frames` event channel
- Call `MetaWearablesDat.stopStreamSession(deviceUUID)` to end the session

**Note:** See the example app for a complete implementation.

## Example app

The example app is a clone of the Meta's sample Camera Access native app.

Here's a demo showing how the DAT integration looks like:

![demo](https://github.com/user-attachments/assets/4947911e-5a37-4369-acb7-fdc005899821)

## Contributing

Contributions are welcome! Feel free to open [issues](https://github.com/rodcone/flutter_meta_wearables_dat/issues) for bugs or feature requests, and [pull requests](https://github.com/rodcone/flutter_meta_wearables_dat/pulls) for improvements.

## License

MIT License — see [LICENSE](LICENSE) for details.
