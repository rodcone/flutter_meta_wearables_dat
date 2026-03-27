Audit and configure this Flutter project for flutter_meta_wearables_dat integration.

## Steps

1. Check if `flutter_meta_wearables_dat` is in `pubspec.yaml`. If not, run `flutter pub add flutter_meta_wearables_dat`.

2. Check if `app_links` is in `pubspec.yaml`. If not, run `flutter pub add app_links`.

3. **iOS audit** — Read `ios/Runner/Info.plist` and verify these keys exist:
   - `NSBluetoothAlwaysUsageDescription`
   - `LSApplicationQueriesSchemes` containing `fb-viewapp`
   - `UISupportedExternalAccessoryProtocols` containing `com.meta.ar.wearable`
   - `UIBackgroundModes` containing `bluetooth-peripheral` and `external-accessory`
   - `CFBundleURLTypes` with a URL scheme
   - `MWDAT` dict with `AppLinkURLScheme`, `MetaAppID`, `ClientToken`, `TeamID`, `Analytics`

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
