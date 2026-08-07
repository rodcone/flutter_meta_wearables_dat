# Verification commands and environment traps

## Swapping the xcframeworks safely

The xcframeworks live in the **tag** trees of the iOS clone (its `main` has only sources). Preflight
already confirmed the tag carries all three, but order the swap so a mid-way failure can never leave
the repo with no frameworks: **extract and verify first, delete last.**

```bash
ROOT="$(git rev-parse --show-toplevel)"
IOS="$ROOT/doc/ios/meta-wearables-dat-ios"
CORE_FW="$ROOT/ios/flutter_meta_wearables_dat/Frameworks"
MOCK_FW="$ROOT/flutter_meta_wearables_dat_mock_device/ios/flutter_meta_wearables_dat_mock_device/Frameworks"
STAGE="$(mktemp -d)"

# 1. Extract to a staging dir
git -C "$IOS" archive "$VERSION" \
  MWDATCore.xcframework MWDATCamera.xcframework MWDATMockDevice.xcframework | tar -x -C "$STAGE"

# 2. Verify all three arrived with both slices before touching the vendored copies
for fw in MWDATCore MWDATCamera MWDATMockDevice; do
  [ -d "$STAGE/$fw.xcframework/ios-arm64" ] || { echo "FAIL: $fw missing device slice"; exit 1; }
done

# 3. Swap
rm -rf "$CORE_FW/MWDATCore.xcframework" "$CORE_FW/MWDATCamera.xcframework"
rm -rf "$MOCK_FW/MWDATMockDevice.xcframework"
mv "$STAGE/MWDATCore.xcframework" "$STAGE/MWDATCamera.xcframework" "$CORE_FW/"
mv "$STAGE/MWDATMockDevice.xcframework" "$MOCK_FW/"
rmdir "$STAGE"

# 4. Thin (idempotent; converts ios-arm64_x86_64-simulator -> ios-arm64-simulator)
"$ROOT/scripts/thin-xcframeworks.sh"
```

If anything fails before step 3, the vendored frameworks are untouched and `git status` is clean.
If it fails after, `git checkout -- <Frameworks dir>` restores them — they are tracked.

## The full verification matrix

Run all of it. Order matters only in that the SwiftPM build must be followed by the CocoaPods
restore below.

```bash
ROOT="$(git rev-parse --show-toplevel)"; cd "$ROOT"

# 0. Capture the maintainer's GLOBAL Flutter SPM setting so it can be put back.
#    `flutter config` writes ~/.config/flutter/settings — machine state, not repo state.
SPM_WAS=$(flutter config --list | sed -n 's/.*enable-swift-package-manager: *//p')

# 1. Analyze both packages
dart analyze && (cd flutter_meta_wearables_dat_mock_device && dart analyze)

# 2. Test both packages (from each package root — see the cwd trap below)
flutter test && (cd flutter_meta_wearables_dat_mock_device && flutter test)

# 3. iOS, CocoaPods — the example app's committed baseline
flutter config --no-enable-swift-package-manager
(cd example && flutter clean && flutter build ios --release --no-codesign)

# 4. iOS, Swift Package Manager
flutter config --enable-swift-package-manager
rm -rf example/ios/Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm
rm -rf example/ios/Runner.xcworkspace/xcshareddata/swiftpm
(cd example && flutter clean && flutter build ios --release --no-codesign)

# 5. Restore the committed CocoaPods baseline (see below) — MANDATORY
flutter config --no-enable-swift-package-manager

# 6. Android
(cd example && flutter build apk --release)

# 7. Publish dry-runs
dart pub publish --dry-run
(cd flutter_meta_wearables_dat_mock_device && dart pub publish --dry-run)

# 8. Put the maintainer's global setting back exactly as found
[ "$SPM_WAS" = "true" ] && flutter config --enable-swift-package-manager \
                        || flutter config --no-enable-swift-package-manager
flutter config --list | grep swift-package-manager   # confirm it matches $SPM_WAS
```

A dry-run warning about uncommitted changes is expected and fine. Any other warning is not.

Step 0/8 matter even though the repo baseline is CocoaPods: if the maintainer normally works with
SPM enabled, finishing the run with it disabled silently changes how *their other projects* build.

## Trap: the SwiftPM build rewrites committed files

`flutter build ios` under SwiftPM mode rewrites two tracked files:

- `example/ios/Podfile.lock` — gutted, because plugins stop coming through CocoaPods
- `example/ios/Runner.xcodeproj/project.pbxproj` — migrated to SwiftPM refs

The committed baseline is **CocoaPods**. After step 4 above:

```bash
git checkout example/ios/Runner.xcodeproj/project.pbxproj
```

…and then **re-apply any intentional pbxproj edit you made this release** (the deployment target is
the usual one — `git checkout` reverts that too). Verify the final diff is only your intended lines:

```bash
git diff --stat example/ios/Runner.xcodeproj/project.pbxproj   # expect a tiny diff, e.g. 3 lines
```

For `Podfile.lock`, regenerate it properly rather than reverting — the plugin versions inside it
legitimately change every release:

```bash
(cd example && flutter clean && flutter pub get)
(cd example/ios && LANG=en_US.UTF-8 pod install)
```

The resulting diff should be just the two plugin versions plus checksums.

## Trap: `pod` needs a UTF-8 locale

Run directly in a non-interactive shell, CocoaPods dies with
`Unicode Normalization not appropriate for ASCII-8BIT`. Always prefix:

```bash
LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 pod install
```

`flutter build ios` runs `pod install` itself with a correct environment, so this only matters when
invoking `pod` by hand.

## Trap: the shell working directory persists between commands

A `cd` in one Bash call carries into the next. After `cd flutter_meta_wearables_dat_mock_device`,
a bare `flutter test` runs the *mock* package's tests, which look superficially like a pass.
Use absolute paths or subshells (`(cd x && …)`) for anything where the wrong cwd would be silently
wrong rather than an error.

## Trap: Android needs a GitHub Packages token

The DAT Android artifacts come from GitHub Packages. A `401 Unauthorized` on
`com.meta.wearable:mwdat-*` means the token expired — it's `GITHUB_TOKEN` in the environment or
`github_token` in `example/android/local.properties`, and needs `read:packages` scope. CI reads the
`MWDAT_PACKAGES_TOKEN` repo secret for the same reason.

## Inspecting the Android SDK surface

To diff the Kotlin API across versions, extract both AARs from the Gradle cache and use `javap`:

```bash
CACHE=~/.gradle/caches/modules-2/files-2.1/com.meta.wearable
find $CACHE -name 'mwdat-camera-*.aar'      # locate old and new
mkdir -p /tmp/aar/new && (cd /tmp/aar/new && unzip -o <new>.aar && unzip -o classes.jar -d classes)
(cd /tmp/aar/new/classes && javap -cp . com.meta.wearable.dat.camera.Camera)
```

Do the same for the old version and diff the class lists. This is how the plugin's migration claims
get verified — for example, confirming that stopping a `Stream` removes only the `Stream` capability
while the `Camera` stays attached.

Do this work under the session scratchpad rather than `/tmp` when possible, and clean up after.

## Inspecting the iOS SDK surface

The authoritative source is the vendored interface, not the `doc/ios/*.swift` snapshot:

```bash
ios/flutter_meta_wearables_dat/Frameworks/MWDATCamera.xcframework/ios-arm64/MWDATCamera.framework/Modules/MWDATCamera.swiftmodule/arm64-apple-ios.swiftinterface
```

Two things it tells you that the changelog won't: whether an enum is `@frozen` (which decides
whether `@unknown default` is valid) and the exact deployment target the binary was built against.

Strings in the binary are occasionally the only way to confirm a behaviour change — e.g. finding
`NSBluetoothAlwaysUsageDescription` inside `MWDATCore` confirmed 0.9.0's mock-device Info.plist
enforcement.
