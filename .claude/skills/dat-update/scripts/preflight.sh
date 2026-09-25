#!/usr/bin/env bash
# Preflight for a DAT SDK update. Verifies everything that, if wrong, would either
# corrupt the repo or waste hours before surfacing. Exits non-zero on any failure.
#
#   ./preflight.sh 0.10.0
#
# Checks, in order:
#   1. argument is exactly X.Y.Z
#   2. repo root resolves and the working tree is clean
#   3. both Meta clones exist and fast-forward cleanly
#   4. the iOS release tag exists AND carries all three xcframeworks
#   5. all three Android Maven artifacts are published at that version
#   6. the four plugin version locations agree with each other
# Prints a summary (current versions, explicit release-target reminder, iOS floor) on success.

set -euo pipefail

fail() { printf '\n\033[31mPREFLIGHT FAILED:\033[0m %s\n' "$1" >&2; exit 1; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }

VERSION="${1:-}"

# 1. Argument -----------------------------------------------------------------
# Strict, anchored. This value is interpolated into git/curl commands below, so
# anything other than a bare semver is rejected outright.
[[ -n "$VERSION" ]] || fail "no version given. Usage: preflight.sh <X.Y.Z>"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  || fail "'$VERSION' is not a bare semver version (expected X.Y.Z, digits only)."
ok "target DAT version: $VERSION"

# 2. Repo root and clean tree -------------------------------------------------
# Everything below is absolute. Relative paths are unsafe here: the shell's cwd
# persists between agent commands and these steps include rm -rf.
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || fail "not inside a git repository."
[[ -f "$ROOT/pubspec.yaml" && -d "$ROOT/flutter_meta_wearables_dat_mock_device" ]] \
  || fail "repo root '$ROOT' does not look like flutter_meta_wearables_dat."
cd "$ROOT"
[[ -z "$(git status --porcelain)" ]] \
  || fail "working tree is dirty. Commit or stash first — later steps delete and regenerate files."
ok "repo root: $ROOT (clean)"

# 3. Meta clones --------------------------------------------------------------
IOS_CLONE="$ROOT/doc/ios/meta-wearables-dat-ios"
AND_CLONE="$ROOT/doc/android/meta-wearables-dat-android"
for c in "$IOS_CLONE" "$AND_CLONE"; do
  [[ -d "$c/.git" ]] || fail "missing reference clone: $c
  Clone it there (it is gitignored) before running the update:
    git clone https://github.com/facebook/meta-wearables-dat-${c##*-} $c"
done
for c in "$IOS_CLONE" "$AND_CLONE"; do
  git -C "$c" pull --ff-only --quiet \
    || fail "'$c' would not fast-forward. Resolve it manually (it should never have local commits)."
  git -C "$c" fetch --tags --quiet
done
ok "reference clones updated (--ff-only)"

# 4. iOS tag and its payload --------------------------------------------------
# The xcframeworks live in the TAG trees, not on main. Verify the tag exists and
# actually carries all three BEFORE anything deletes the vendored copies.
git -C "$IOS_CLONE" rev-parse -q --verify "refs/tags/$VERSION" >/dev/null \
  || fail "iOS tag '$VERSION' does not exist upstream. Available: $(git -C "$IOS_CLONE" tag --list | sort -V | tail -3 | tr '\n' ' ')"
TAG_FILES="$(git -C "$IOS_CLONE" ls-tree --name-only "$VERSION")"
for fw in MWDATCore MWDATCamera MWDATMockDevice; do
  grep -qx "$fw.xcframework" <<<"$TAG_FILES" \
    || fail "tag '$VERSION' does not contain $fw.xcframework — do not delete the vendored copies."
done
ok "iOS tag $VERSION carries all three xcframeworks"

# 5. Android artifacts --------------------------------------------------------
# All three must be published. Discovering a missing mwdat-mockdevice after the
# iOS work is done costs hours.
# DAT 1.0.0 moved to Maven Central; pre-1.0 releases use GitHub Packages.
# Keep credentials confined to the legacy host, and never skip this check.
CURL_AUTH=()
if [[ "${VERSION%%.*}" -ge 1 ]]; then
  BASE="https://repo.maven.apache.org/maven2/com/meta/wearable"
else
  TOKEN="${GITHUB_TOKEN:-$(sed -n 's/^github_token=//p' "$ROOT/example/android/local.properties" 2>/dev/null || true)}"
  [[ -n "$TOKEN" ]] || fail "pre-1.0 DAT requires a GitHub Packages token (read:packages)."
  BASE="https://maven.pkg.github.com/facebook/meta-wearables-dat-android/com/meta/wearable"
  CURL_AUTH=(-u "x:$TOKEN")
fi
for art in mwdat-core mwdat-camera mwdat-mockdevice; do
  for ext in pom aar; do
    # Check metadata and the actual binary, without downloading the AAR.
    code="$(curl -sS -I --connect-timeout 15 --max-time 60 -o /dev/null -w '%{http_code}' \
      ${CURL_AUTH[@]+"${CURL_AUTH[@]}"} "$BASE/$art/$VERSION/$art-$VERSION.$ext")" \
      || fail "network failure checking $art $VERSION ($ext)."
    case "$code" in
      200) ;;
      401|403) fail "artifact repository rejected access ($code): $BASE. Check authentication for legacy GitHub Packages releases." ;;
      404) fail "$art $VERSION ($ext) returned 404 at $BASE. Check the target release README for repository or coordinate changes before concluding it is unpublished." ;;
      *) fail "unexpected HTTP $code resolving $art $VERSION ($ext) at $BASE." ;;
    esac
  done
done
ok "Android POMs and AARs published: mwdat-core, mwdat-camera, mwdat-mockdevice @ $VERSION"

# 6. Plugin version consistency -----------------------------------------------
# All four must already agree before selecting the next stable or prerelease version.
CORE_PUB="$(sed -n 's/^version: *//p' "$ROOT/pubspec.yaml" | head -1)"
MOCK_PUB="$(sed -n 's/^version: *//p' "$ROOT/flutter_meta_wearables_dat_mock_device/pubspec.yaml" | head -1)"
CORE_POD="$(sed -n "s/.*s\.version *= *'\([^']*\)'.*/\1/p" "$ROOT/ios/flutter_meta_wearables_dat.podspec" | head -1)"
MOCK_POD="$(sed -n "s/.*s\.version *= *'\([^']*\)'.*/\1/p" "$ROOT/flutter_meta_wearables_dat_mock_device/ios/flutter_meta_wearables_dat_mock_device.podspec" | head -1)"
[[ "$CORE_PUB" == "$MOCK_PUB" && "$CORE_PUB" == "$CORE_POD" && "$CORE_PUB" == "$MOCK_POD" ]] \
  || fail "the four plugin version locations disagree — fix that before bumping:
    pubspec.yaml                    $CORE_PUB
    mock pubspec.yaml               $MOCK_PUB
    core podspec                    $CORE_POD
    mock podspec                    $MOCK_POD"
ok "plugin version consistent at $CORE_PUB (all four locations)"

# Summary ---------------------------------------------------------------------
FLOOR="$(grep -ho 'target arm64-apple-ios[0-9.]*' \
  "$ROOT"/ios/flutter_meta_wearables_dat/Frameworks/MWDATCamera.xcframework/ios-arm64/*/Modules/*.swiftmodule/*.swiftinterface \
  2>/dev/null | head -1 | sed 's/.*ios//')"
MWDAT_NOW="$(sed -n 's/.*ext\.mwdat_version *= *"\([^"]*\)".*/\1/p' "$ROOT/android/build.gradle" | head -1)"

cat <<EOF

Preflight passed.
  DAT:     $MWDAT_NOW  ->  $VERSION
  Plugin:  $CORE_PUB  ->  select the maintainer's target (preserve any prerelease suffix)
  iOS floor currently ${FLOOR:-unknown} — re-check after swapping the frameworks.
EOF
