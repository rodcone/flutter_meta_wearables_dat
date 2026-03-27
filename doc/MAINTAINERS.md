# Maintainer Guide: Updating Meta Wearables DAT

This plugin manages the native Meta Wearables DAT for both iOS and Android platforms. Follow the platform-specific steps below to update the DAT version.

## iOS

The iOS implementation uses vendored frameworks. Follow these steps to update the DAT version.

### 1. Download Latest Binaries

The Meta Wearables DAT is distributed as pre-compiled binaries.

- Go to the [official repository](https://github.com/facebook/meta-wearables-dat-ios) → **Releases** → **Tags**
- Download the desired version (no need to clone the entire repo)
- Extract and locate the `.xcframework` folders:
  - `MWDATCamera.xcframework`
  - `MWDATCore.xcframework`
  - `MWDATMockDevice.xcframework`

### 2. Replace Local Files

Update the binaries in the plugin's internal structure:

1. Navigate to `ios/Frameworks/` in this repository
2. Delete the existing `.xcframework` folders
3. Paste the new versions you extracted

### 3. Sync Example App

Force the example app to recognize the updated files:

1. Navigate to the example's iOS folder: `cd example/ios`
2. Update Pods: Run `pod update` (not just `pod install`) to re-link the local vendored files
3. Clean Build: Open Xcode and perform a Clean Build Folder (`Cmd+Shift+K`)

### 4. Implement API Changes

Review the DAT release notes for breaking changes, new APIs, or deprecations. Update the plugin implementation (native Swift and Dart) to adopt new features and fix any issues introduced by the update.

### 5. Test Build

- Clean build: `cd example && flutter build ios --release --no-codesign`
- Run the example app on a device or simulator to verify everything works with the new version

## Android

The Android implementation uses Maven dependencies from GitHub Packages. Follow these steps to update the DAT version.

### 1. Check Latest Version

- Check the [official Android repository](https://github.com/facebook/meta-wearables-dat-android) for the latest release version
- Review the [GitHub Packages](https://github.com/orgs/facebook/packages?repo_name=meta-wearables-dat-android) to verify available versions

### 2. Update Plugin Version

Update the version in `android/build.gradle` (single place for all three DAT libraries):

```groovy
ext.mwdat_version = "0.3.0"  # Update to the latest version
```

The `mwdat-core`, `mwdat-camera`, and `mwdat-mockdevice` dependencies all use this variable.


### 3. Sync Dependencies

1. Navigate to the example's Android folder: `cd example/android`
2. Sync Gradle: Run `./gradlew build --refresh-dependencies` or use Android Studio's "Sync Project with Gradle Files"
3. Verify the new dependencies are resolved correctly

### 4. Implement API Changes

Review the DAT release notes for breaking changes, new APIs, or deprecations. Update the plugin implementation (native Kotlin and Dart) to adopt new features and fix any issues introduced by the update.

Key Android-specific implementation files:
- `MetaWearablesDatPlugin.kt` — main plugin with method/event channel handling
- `FrameProcessor.kt` — I420→ARGB frame conversion and FPS throttling
- `ActiveDeviceStreamHandler.kt` — active device event channel
- `RegistrationStateStreamHandler.kt` — registration state event channel
- `StreamSessionStateStreamHandler.kt` — stream session state event channel (maps `StreamSessionState` enum to int)
- `StreamSessionErrorStreamHandler.kt` — stream session error event channel (programmable sink, Android SDK has no native error publisher)

### 5. Test Build

- Clean build: `./gradlew clean build`
- Run the example app to ensure everything works with the new version

## Update Documentation

After updating either platform:

- **Changelog**: Add a new entry in `CHANGELOG.md` reflecting the DAT version bump and platform
- **Pubspec**: Increment the plugin version in `pubspec.yaml` if preparing for a release
- **README**: Update any version-specific instructions if the DAT API has changed
