Audit and configure this Flutter project for flutter_meta_wearables_dat integration.

## Steps

1. Check if `flutter_meta_wearables_dat` is in `pubspec.yaml`. If not, run `flutter pub add flutter_meta_wearables_dat`.

2. Check if `app_links` is in `pubspec.yaml`. If not, run `flutter pub add app_links`.

3. **iOS audit** — Read `ios/Runner/Info.plist` and verify these keys exist:
   - `NSBluetoothAlwaysUsageDescription`
   - `LSApplicationQueriesSchemes` containing `fb-viewapp`
   - `UIBackgroundModes` containing `bluetooth-peripheral`
   - `CFBundleURLTypes` with a URL scheme
   - `MWDAT` dict with `AppLinkURLScheme`, `MetaAppID`, `ClientToken`, `TeamID`, `Analytics`

   Then check the **camera transport** (exactly one must be configured):
   - **Wi‑Fi (recommended):** in `Info.plist`, `NSLocalNetworkUsageDescription` + `NSBonjourServices` (`_bonjour._tcp`); the `com.apple.developer.networking.HotspotConfiguration` + `com.apple.developer.networking.wifi-info` entitlements in the app's `.entitlements` file; and the ExternalAccessory keys **absent** (while present they force Bluetooth Classic and disable Wi‑Fi). **An `.entitlements` file is ignored unless it is wired to the target** — checking its contents is not enough. Confirm `CODE_SIGN_ENTITLEMENTS` points at it in *every* Runner app build configuration: grep `ios/Runner.xcodeproj/project.pbxproj` for `CODE_SIGN_ENTITLEMENTS` (it must appear in the Debug, Release, and Profile configs of the Runner app target), or run `cd ios && xcodebuild -showBuildSettings -target Runner | grep CODE_SIGN_ENTITLEMENTS`. If the file is missing or unwired, the audit must **not** pass — create the file and add `CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;` to each Runner config (or add the two capabilities via Xcode → Signing & Capabilities, which wires it automatically).
   - **Bluetooth Classic:** `UISupportedExternalAccessoryProtocols` containing `com.meta.ar.wearable`, and `external-accessory` in `UIBackgroundModes`.

   (Transport does not affect App Store eligibility — the SDK links `ExternalAccessory.framework` regardless, and Meta limits public publishing to select partners until GA.)

   **If neither transport is configured** (fresh project), do not silently default to one — ask the user which they'd prefer before adding either recipe. Mention the trade-off: Wi‑Fi has higher bandwidth but `startStreamSession()` takes roughly 10 seconds longer to first frame (the phone must associate with the glasses' AP first); Bluetooth Classic connects almost instantly, needs no Wi‑Fi prompt, and works offline, but is lower bandwidth.

   **If one transport is already configured** and the user wants to switch (migrating an older app to Wi‑Fi, or troubleshooting a transport that isn't working — e.g. Wi‑Fi never prompts, or streaming is unreliable), this is a config-only change: remove that transport's keys/entitlements, add the other's from the recipes above, and — if switching to Wi‑Fi — verify the `CODE_SIGN_ENTITLEMENTS` wiring per the Wi‑Fi check above before declaring it done. No Dart/plugin code changes are needed either way.

   Report any missing keys and offer to add them.

4. **Android audit** — Read `android/app/src/main/AndroidManifest.xml` and verify:
   - `BLUETOOTH`, `BLUETOOTH_CONNECT`, `INTERNET` permissions
   - `com.meta.wearable.mwdat.APPLICATION_ID` meta-data
   - Intent filter with `android.intent.action.VIEW` and a URL scheme matching the iOS scheme

   Report any missing entries and offer to add them.

5. **Android Gradle audit** — Read `android/settings.gradle.kts` and verify:
   - GitHub Packages repository for `maven.pkg.github.com/facebook/meta-wearables-dat-android`
   - Credential configuration using `GITHUB_TOKEN` or `local.properties`

   Report if missing and offer to add it.

6. **MainActivity audit** — Find the MainActivity file and verify it extends `FlutterFragmentActivity` (not `FlutterActivity`). This is required for DAT permission handling on Android.

7. **Summary** — Report what was found, what was missing, and what was fixed. Remind the user to:
   - Set their URL scheme consistently across iOS and Android
   - Configure their MetaAppID in the Meta Wearables Developer Center (or use `0` for Developer Mode)
   - Set a GitHub token with `read:packages` scope for Android builds
