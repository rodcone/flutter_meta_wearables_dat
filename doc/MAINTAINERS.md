# Maintainer Guide: Updating Meta Wearables DAT

This repo ships **two federated plugins** that both consume the Meta Wearables DAT:

- `flutter_meta_wearables_dat/` (root) — vendors `MWDATCore` + `MWDATCamera` (iOS) and depends on `mwdat-core` + `mwdat-camera` (Android).
- `flutter_meta_wearables_dat_mock_device/` (sibling) — vendors `MWDATMockDevice` (iOS) and depends on `mwdat-mockdevice` (Android).

Update **both** packages together when bumping the DAT version, otherwise the host app will mix incompatible binaries from the two SDKs. Follow the platform-specific steps below.

> **Do not skip the mock add-on.** A DAT bump means replacing **all three** iOS xcframeworks (`MWDATCore`, `MWDATCamera`, **and** `MWDATMockDevice`) and bumping `ext.mwdat_version` in **both** Android `build.gradle` files. Leaving `MWDATMockDevice` / `mwdat-mockdevice` on an older DAT release will break the example app and any consumer that depends on `flutter_meta_wearables_dat_mock_device`.

> **Doing this with Claude Code?** The `/dat-update <version>` skill
> ([`.claude/skills/dat-update/`](../.claude/skills/dat-update/SKILL.md)) runs this whole guide end
> to end — changelog analysis, binaries, API-surface diffing, implementation, verification, PR and
> review — stopping before merge and publish. This document remains the source of truth for the
> mechanics; the skill follows it.

## iOS

The iOS implementation uses vendored frameworks. Follow these steps to update the DAT version.

### 1. Get the Latest Binaries

The Meta Wearables DAT is distributed as pre-compiled binaries. You need **all three**:

- `MWDATCore.xcframework` → core plugin
- `MWDATCamera.xcframework` → core plugin
- `MWDATMockDevice.xcframework` → mock add-on (`flutter_meta_wearables_dat_mock_device`)

Skip `MWDATDisplay` and `MWDATMockDeviceTestClient` — not vendored.

**Fastest path — extract from the release tag.** The xcframeworks live in the *tag* trees of
[`facebook/meta-wearables-dat-ios`](https://github.com/facebook/meta-wearables-dat-ios) (its `main`
branch has only sources and samples). If you have the repo cloned at
`doc/ios/meta-wearables-dat-ios` (gitignored), steps 1 and 2 collapse into:

```bash
IOS=doc/ios/meta-wearables-dat-ios
MOCK=flutter_meta_wearables_dat_mock_device/ios/flutter_meta_wearables_dat_mock_device/Frameworks
(cd $IOS && git fetch --tags)

rm -rf ios/flutter_meta_wearables_dat/Frameworks/MWDAT{Core,Camera}.xcframework
rm -rf $MOCK/MWDATMockDevice.xcframework

(cd $IOS && git archive <version> MWDATCore.xcframework MWDATCamera.xcframework) \
  | tar -x -C ios/flutter_meta_wearables_dat/Frameworks/
(cd $IOS && git archive <version> MWDATMockDevice.xcframework) | tar -x -C $MOCK
```

Verified byte-identical to the published archives. Continue at step 2b.

**Manual path** — if you don't have the clone: go to the repo → **Tags** → pick the version →
download, and copy the three `.xcframework` folders in by hand.

### 2. Replace Local Files

Update the binaries across **both** plugins (core alone is not enough):

1. **Core plugin** — replace `MWDATCore.xcframework` and `MWDATCamera.xcframework` in `ios/flutter_meta_wearables_dat/Frameworks/`.
2. **Mock add-on** — replace `MWDATMockDevice.xcframework` in `flutter_meta_wearables_dat_mock_device/ios/flutter_meta_wearables_dat_mock_device/Frameworks/`.

Delete the existing folders before pasting the new versions to avoid stale slices.

The same xcframework files back both the CocoaPods (`vendored_frameworks` in each `*.podspec`) and Swift Package Manager (`.binaryTarget(path:)` in each `Package.swift`) paths — there's only one source of truth on disk.

### 2b. Thin the xcframeworks (required for pub.dev publish)

Meta ships universal arm64+x86_64 simulator binaries inside each xcframework. Combined with the device slice that pushes the pub.dev archive past the 100 MiB uncompressed limit. Run the thinning script after dropping in new binaries:

```bash
./scripts/thin-xcframeworks.sh
```

The script strips x86_64 from each simulator slice, renames the directory from `ios-arm64_x86_64-simulator` → `ios-arm64-simulator`, and patches each xcframework's `Info.plist` accordingly. Idempotent (running twice is a no-op). Typical savings: ~36 MB across the three frameworks.

**Tradeoff this implies**: iOS Simulator development requires an Apple Silicon Mac. Intel-Mac iOS dev is end-of-life as of 2026 so this is the realistic baseline; if you need x86_64 sim support back you'll have to find another way under pub.dev's size limit.

### 3. Sync Example App

Force the example app to recognize the updated files:

The example app builds via SwiftPM, so delete the cached SwiftPM state to force a fresh resolve against the new binaries:

```bash
rm -rf example/ios/Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm
rm -rf example/ios/Runner.xcworkspace/xcshareddata/swiftpm
cd example && flutter clean
```

Then a Clean Build Folder in Xcode (`Cmd+Shift+K`) if you build from there.

Note this is hygiene rather than a checksum problem: both plugins use `.binaryTarget(path:)`, which carries no checksum, and neither committed `Package.resolved` contains an MWDAT entry at all (they only pin the remote packages that `image_picker` and friends pull in). Clearing the workspace state forces Xcode to re-read the replaced xcframeworks instead of reusing a stale build graph.

### 4. Implement API Changes

Review the DAT release notes for breaking changes, new APIs, or deprecations. Update the plugin implementation (native Swift and Dart) to adopt new features and fix any issues introduced by the update.

Meta ships its own AI skills alongside the SDK at [`plugins/mwdat-ios/skills/`](https://github.com/facebook/meta-wearables-dat-ios/tree/main/plugins/mwdat-ios), updated with each release. They're often the fastest, most concrete migration reference — usually ahead of the prose docs. They document the *native* Swift API, so treat them as a migration guide for `MetaWearablesDatPlugin.swift`, not as content to copy into our Dart-facing [`agent/`](../agent/) skills.

### 5. Test Build

Verify the iOS build from a clean state:

```bash
cd example && flutter clean && flutter build ios --release --no-codesign
```

Then run the example app on a device or simulator to verify the new DAT version actually works at runtime. CI's `ios-build` job covers this on every PR.

**The podspec path is covered by CI, not by the example app.** The example app is deintegrated from CocoaPods, so a local example build only ever exercises SwiftPM. The `cocoapods-build` CI job scaffolds a throwaway app, adds both plugins as path dependencies, disables SwiftPM and builds through the podspecs, then asserts both appear in the generated `Podfile.lock`. Changes to source paths, system frameworks, or vendored frameworks still have to be applied to *both* manifests, but a podspec break will now fail CI rather than reaching consumers.

To reproduce it locally, follow the same steps the job does: `flutter config --no-enable-swift-package-manager`, `flutter create` a scratch app, `flutter pub add` both plugins by path, raise `IPHONEOS_DEPLOYMENT_TARGET` and the Podfile `platform` to 17.2, then build. Re-enable SwiftPM afterwards.

## iOS resolver layout

The iOS side supports CocoaPods and Swift Package Manager from the same on-disk layout:

- **Sources** live under `ios/flutter_meta_wearables_dat/Sources/flutter_meta_wearables_dat/` (and the mock equivalent). Any new Swift file goes there — don't recreate the legacy `ios/Classes/` directory.
- **Vendored xcframeworks** live under `ios/flutter_meta_wearables_dat/Frameworks/` (and the mock equivalent). Same files back both resolvers.
- **Manifests**: each plugin ships both `*.podspec` (CocoaPods) and `Package.swift` (SwiftPM). Any change to source paths, system frameworks, or vendored frameworks must be applied to *both* manifests in lockstep.
- **Cross-plugin dependency**: the mock plugin's `Package.swift` reaches the core via `.package(name: "flutter_meta_wearables_dat", path: "../flutter_meta_wearables_dat")` — a sibling-relative path that resolves through Flutter's symlinked plugin umbrella regardless of whether the plugins live in this monorepo or under a consumer's pub-cache. The core plugin re-exports `MWDATCore` as a separate `.library(name: "MWDATCore", targets: ["MWDATCore"])` product so the mock can `import MWDATCore`. The equivalent CocoaPods linkage is the `s.dependency 'flutter_meta_wearables_dat'` line in the mock's podspec.
- **Privacy manifest** lives inside the SwiftPM source target dir (`ios/flutter_meta_wearables_dat/Sources/flutter_meta_wearables_dat/PrivacyInfo.xcprivacy`) — SwiftPM requires resources to be inside the target's `path`. The podspec's `s.resource_bundles` points at the same file.

## Android

The Android implementation uses Maven dependencies from GitHub Packages. Follow these steps to update the DAT version.

### 1. Check Latest Version

- Check the [official Android repository](https://github.com/facebook/meta-wearables-dat-android) for the latest release version
- Review the [GitHub Packages](https://github.com/orgs/facebook/packages?repo_name=meta-wearables-dat-android) to verify available versions

### 2. Update Plugin Version

Update the version in **both** `build.gradle` files (each plugin owns its own `ext.mwdat_version`):

```groovy
// android/build.gradle (core)
ext.mwdat_version = "0.9.0"  // mwdat-core, mwdat-camera

// flutter_meta_wearables_dat_mock_device/android/build.gradle
ext.mwdat_version = "0.9.0"  // mwdat-mockdevice
```

Keep the two values in sync — mixing versions across the two plugins risks ABI breakage at runtime.


### 3. Sync Dependencies

1. Navigate to the example's Android folder: `cd example/android`
2. Sync Gradle: Run `./gradlew build --refresh-dependencies` or use Android Studio's "Sync Project with Gradle Files"
3. Verify the new dependencies are resolved correctly

If Gradle fails with `401 Unauthorized` resolving `com.meta.wearable:mwdat-*`, your GitHub token (`GITHUB_TOKEN` or `github_token` in `local.properties`) is expired — regenerate one with `read:packages` scope.

**The same applies in CI.** The `android-build` job in [`ci.yml`](../.github/workflows/ci.yml) builds the example APK, which is the only job that compiles either plugin's Kotlin. It reads the token from `MWDAT_PACKAGES_TOKEN` (a repo secret — a PAT with `read:packages`) and falls back to the workflow's built-in `GITHUB_TOKEN`. The built-in token is scoped to this repository and is not reliably accepted for `facebook/meta-wearables-dat-android`, so **if `android-build` starts failing with `401 Unauthorized`, add or refresh the `MWDAT_PACKAGES_TOKEN` secret** (Settings → Secrets and variables → Actions). The job is skipped on fork PRs, where no secrets are available.

### 4. Implement API Changes

Review the DAT release notes for breaking changes, new APIs, or deprecations. Update the plugin implementation (native Kotlin and Dart) to adopt new features and fix any issues introduced by the update.

Meta ships its own AI skills alongside the SDK at [`plugins/mwdat-android/skills/`](https://github.com/facebook/meta-wearables-dat-android/tree/main/plugins/mwdat-android/skills), updated with each release. `camera-streaming` and `session-lifecycle` in particular are often the fastest, most concrete migration reference — usually ahead of the prose docs. They document the *native* Kotlin API, so treat them as a migration guide for `MetaWearablesDatPlugin.kt`, not as content to copy into our Dart-facing [`agent/`](../agent/) skills. Diffing them across releases is also a useful signal for behaviour changes our consumer skills should mention (constraints, state machines, error taxonomy).

Key Android-specific implementation files:
- `MetaWearablesDatPlugin.kt` — main plugin with method/event channel handling
- `FrameProcessor.kt` — I420→ARGB frame conversion and FPS throttling
- `ActiveDeviceStreamHandler.kt` — active device event channel
- `RegistrationStateStreamHandler.kt` — registration state event channel
- `StreamStateStreamHandler.kt` — stream state event channel (maps DAT 0.7.0 `StreamState` enum to int; Dart-facing channel name stays `stream_session_state` for backwards compat)
- `StreamSessionErrorStreamHandler.kt` — stream session error event channel. Funnels three sources: `Stream.errorStream` (`StreamError`), `DeviceSession.errors` (`DeviceSessionError`, since DAT 0.7.0), and pre-stream `sendError(code, message)` calls
- `DeviceStateStreamHandler.kt` — per-device thermal state stream (switches its inner subscription when `AutoDeviceSelector` swaps the active device)
- `VideoFrameStreamHandler.kt` — per-frame I420 byte forwarder for `video_frames` event channel
- `VideoStreamSizeStreamHandler.kt` — emits `{width, height}` on stream start and resolution changes
- `BackgroundStreamingService.kt` — foreground service (`connectedDevice` type, API 30+) + wake lock for background streaming

### 5. Test Build

- Clean build: `./gradlew clean build`
- Run the example app to ensure everything works with the new version

## Releasing a new version

The two packages release **in lockstep at the same version number**. CI enforces this on PRs (the `versions-in-sync` job in [`.github/workflows/ci.yml`](../.github/workflows/ci.yml) fails if the two pubspecs drift), and the publish workflow ([`.github/workflows/publish.yml`](../.github/workflows/publish.yml)) publishes both packages to pub.dev when you push a tag of the form `v<x>.<y>.<z>`.

### When to release

Any user-visible change to either package — DAT SDK bump, API addition, bug fix, README rewrite that ships on pub.dev, etc. The two CHANGELOGs can have asymmetric entries (one side may legitimately say "no user-visible changes" on a given release), but the version number is always shared.

### Pre-flight checklist

Before tagging, confirm:

1. **All four version locations match.** Bump together:
   - `pubspec.yaml`
   - `ios/flutter_meta_wearables_dat.podspec` (`s.version`)
   - `flutter_meta_wearables_dat_mock_device/pubspec.yaml`
   - `flutter_meta_wearables_dat_mock_device/ios/flutter_meta_wearables_dat_mock_device.podspec` (`s.version`)
2. **If this release bumps the DAT SDK:** all three iOS xcframeworks are updated (`MWDATCore` + `MWDATCamera` in the core plugin **and** `MWDATMockDevice` in the mock add-on), `./scripts/thin-xcframeworks.sh` has been run, and both Android `ext.mwdat_version` values match.
3. **Both `CHANGELOG.md` files have a `## <new-version>` entry.** The publish workflow's `github-release` job extracts these for the GitHub release notes — missing entries produce an empty release body.
4. **Both packages are clean locally:**
   ```bash
   dart analyze && (cd flutter_meta_wearables_dat_mock_device && dart analyze)
   dart pub publish --dry-run && (cd flutter_meta_wearables_dat_mock_device && dart pub publish --dry-run)
   ```
5. **The example app still builds** — `cd example && flutter build ios --release --no-codesign` and `flutter build apk --release`.
6. **You're tagging from `main` with no uncommitted changes.** Tags are not branch-scoped on push; whatever commit you tag is what gets published.

### Steps

```bash
# 1. On a feature branch, do the version bumps + changelog entries.
#    Open a PR, get it reviewed, merge to main.

# 2. After merge, tag from main.
git checkout main
git pull --ff-only
TAG="v$(grep '^version:' pubspec.yaml | awk '{print $2}')"
git tag "$TAG"
git push origin "$TAG"

# 3. Watch the publish workflow.
gh run watch -R rodcone/flutter_meta_wearables_dat
```

The workflow will:

- Verify the tag matches **both** pubspec versions (fails fast if they drift).
- Run `dart analyze --fatal-infos` and tests on both packages.
- Publish the core package to pub.dev.
- Publish the mock add-on to pub.dev.
- Create a GitHub release whose body combines both CHANGELOG entries for this version.

### First-time release of the mock add-on (one-time setup)

The very first publish of `flutter_meta_wearables_dat_mock_device` **cannot** go through the existing OIDC-based publish workflow as-is — pub.dev's "Trusted publishing" requires the package to exist *before* you can configure GitHub Actions as a trusted publisher for it. Two options:

- **Recommended — manual first publish.** From a maintainer's machine, after `dart pub login`:
  ```bash
  cd flutter_meta_wearables_dat_mock_device
  dart pub publish        # confirm prompts
  ```
  Then on pub.dev, open the new package's *Admin* tab and add `rodcone/flutter_meta_wearables_dat` + the `pub.dev` GitHub environment as a trusted publisher (matching what's already set for the core package). After that, every subsequent release goes through the workflow automatically.
- **Alternative — `PUB_TOKEN` for one run.** Generate a publishing token, add it as a `PUB_TOKEN` secret in the repo, temporarily swap `dart pub publish --force` for a token-based call, run the workflow, then remove the secret and revert the workflow.

The core package (`flutter_meta_wearables_dat`) is already live on pub.dev and presumably already has trusted publishing configured, so the OIDC path works for it on this release.

### Recovering from a half-published release

The publish job runs sequentially: core first, then mock. pub.dev versions are **immutable** — you can't re-upload the same version after fixing a problem. So if core publishes successfully but the mock add-on step fails:

1. Fix the cause of the mock-publish failure on a hotfix branch.
2. Bump both packages to the next patch version (e.g. `0.4.0` → `0.4.1`) — all four version locations + both CHANGELOGs. The core CHANGELOG entry can be a one-liner like *"Republish to align with `flutter_meta_wearables_dat_mock_device 0.4.1`"*.
3. Merge, tag `v0.4.1`, push.

This should be rare in practice — both publishes have already passed `dart pub publish --dry-run` in CI by the time you tag — but the failure mode exists and forward-bump is the only recovery path.

## Updating documentation

When releasing — beyond the CHANGELOG and pubspec bumps covered in the checklist above:

- **README**: update version-specific instructions in the root [`README.md`](../README.md) and [`flutter_meta_wearables_dat_mock_device/README.md`](../flutter_meta_wearables_dat_mock_device/README.md) if any DAT API changed.
- **Agent files**: if API surface changed, sync [`AGENTS.md`](../AGENTS.md), [`agent/claude/`](../agent/claude/), [`agent/cursor/`](../agent/cursor/), and [`agent/github/`](../agent/github/). These are installed into consumer projects via [`install-skills.sh`](../install-skills.sh), so out-of-date copies leak into other repos.
