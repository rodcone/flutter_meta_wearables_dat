# Getting started with flutter_meta_wearables_dat

## Add dependency

```bash
flutter pub add flutter_meta_wearables_dat
flutter pub add app_links  # For deep link handling
```

## iOS configuration

**Minimum deployment target:** iOS 17.0

Add to `ios/Runner/Info.plist`:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Needed to connect to Meta AI Glasses</string>

<key>LSApplicationQueriesSchemes</key>
<array>
    <string>fb-viewapp</string>
</array>

<!-- Camera transport is configured separately — see "iOS camera transport" below. -->
<key>UIBackgroundModes</key>
<array>
    <string>bluetooth-peripheral</string>
    <!-- Optional: required only if you call MetaWearablesDat.enableBackgroundStreaming()
         to keep the stream alive while backgrounded or the phone is locked. -->
    <!-- <string>audio</string>                -->
    <!-- <string>bluetooth-central</string>   -->
</array>

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
    <string>0</string>
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

Replace `myexampleapp` with your app's URL scheme. Use `0` for MetaAppID in Developer Mode, or your real ID from the Meta Wearables Developer Center for production.

### iOS camera transport: Wi‑Fi (recommended) or Bluetooth Classic

Pick one (selected purely via `Info.plist` + entitlements — no runtime switch):

- **Wi‑Fi (recommended)** — higher bandwidth. Add `NSLocalNetworkUsageDescription` and `NSBonjourServices` (`_bonjour._tcp`) to `Info.plist`, plus the `com.apple.developer.networking.HotspotConfiguration` and `com.apple.developer.networking.wifi-info` entitlements (Xcode → Signing & Capabilities → **Access Wi‑Fi Information** + **Hotspot Configuration**). The first stream shows a one-time "Join Wi‑Fi Network" prompt. Do **not** add the ExternalAccessory keys — they force Bluetooth Classic.
- **Bluetooth Classic** — no prompt, works offline, lower bandwidth. Add `UISupportedExternalAccessoryProtocols` (`com.meta.ar.wearable`) and `external-accessory` to `UIBackgroundModes`.

Transport does not affect App Store eligibility — the SDK links `ExternalAccessory.framework` either way, and Meta limits public publishing to select partners until GA.

## Android configuration

**android/app/src/main/AndroidManifest.xml:**

```xml
<uses-permission android:name="android.permission.BLUETOOTH" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.INTERNET" />

<application>
    <meta-data
        android:name="com.meta.wearable.mwdat.APPLICATION_ID"
        android:value="0" />

    <meta-data
        android:name="com.meta.wearable.mwdat.ANALYTICS_OPT_OUT"
        android:value="true" />

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

**android/settings.gradle.kts** — Add imports at the top:

```kotlin
import java.util.Properties
import kotlin.io.path.div
import kotlin.io.path.exists
import kotlin.io.path.inputStream
```

Add GitHub Packages repository:

```kotlin
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

Use `PREFER_SETTINGS` (not `FAIL_ON_PROJECT_REPOS`) because Flutter's Gradle plugin adds repositories at the project level.

**GitHub token:** Set `GITHUB_TOKEN` env var or add `github_token=your_token` to `local.properties`. The token needs `read:packages` scope.

**MainActivity** — Must extend `FlutterFragmentActivity`:

```kotlin
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity()
```

## Deep link setup

```dart
import 'package:app_links/app_links.dart';
import 'package:flutter_meta_wearables_dat/flutter_meta_wearables_dat.dart';

final appLinks = AppLinks();
appLinks.uriLinkStream.listen((uri) {
  MetaWearablesDat.handleUrl(uri.toString());
});
```

## Developer Mode

During development, enable Developer Mode in the Meta AI app (Settings > Your glasses > Developer Mode). This allows registration without a real MetaAppID — use `0` as the MetaAppID value. Developer Mode resets after firmware updates.

## Meta Wearables Developer Center

For production, register your app at https://wearables.developer.meta.com/devcenter to get your MetaAppID and ClientToken.
