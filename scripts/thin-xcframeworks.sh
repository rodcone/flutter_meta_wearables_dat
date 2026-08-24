#!/usr/bin/env bash
#
# Strips the x86_64 architecture from the iOS Simulator slice of every
# vendored Meta DAT xcframework. After Meta ships universal arm64+x86_64
# simulator binaries, each framework's simulator slice is ~50% larger than
# necessary; together with the device slice this pushes the published
# pub.dev archive past the 100 MiB uncompressed limit.
#
# Run this script ONCE after dropping in a new set of xcframeworks from a
# DAT SDK release. It rewrites the simulator slice in place — re-running
# is a no-op once the slice is already arm64-only.
#
# Trade-off: iOS Simulator development is supported on Apple Silicon Macs
# only. Intel-Mac iOS dev is end-of-life as of 2026 so this is the
# realistic baseline; if you need x86_64 sim support you'll have to vendor
# the original universal binaries and find another way under the size limit.
#
# Usage:
#   ./scripts/thin-xcframeworks.sh

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"

xcframeworks=(
  "$repo_root/ios/flutter_meta_wearables_dat/Frameworks/MWDATCore.xcframework"
  "$repo_root/ios/flutter_meta_wearables_dat/Frameworks/MWDATCamera.xcframework"
  "$repo_root/flutter_meta_wearables_dat_mock_device/ios/flutter_meta_wearables_dat_mock_device/Frameworks/MWDATMockDevice.xcframework"
)

thin_one() {
  local xcf="$1"
  local name
  name="$(basename "$xcf" .xcframework)"

  local fat_dir="$xcf/ios-arm64_x86_64-simulator"
  local thin_dir="$xcf/ios-arm64-simulator"

  if [[ ! -d "$fat_dir" ]]; then
    if [[ -d "$thin_dir" ]]; then
      echo "  $name: already thinned (no universal slice present), skipping"
      return
    fi
    echo "  $name: no simulator slice found at $fat_dir — skipping" >&2
    return
  fi

  local fat_binary="$fat_dir/$name.framework/$name"
  if [[ ! -f "$fat_binary" ]]; then
    echo "  $name: expected binary at $fat_binary, not found" >&2
    return
  fi

  # Capture before-size for the report
  local before_kb
  before_kb=$(du -k "$fat_binary" | awk '{print $1}')

  # Strip x86_64 → keep arm64 only
  local tmp="$fat_binary.thin"
  lipo -extract arm64 "$fat_binary" -output "$tmp"
  mv "$tmp" "$fat_binary"

  local after_kb
  after_kb=$(du -k "$fat_binary" | awk '{print $1}')

  # Drop the now-unused x86_64 module artifacts (swiftmodule + swiftdoc +
  # swiftinterface, both .private and public variants).
  local modules_dir="$fat_dir/$name.framework/Modules/$name.swiftmodule"
  if [[ -d "$modules_dir" ]]; then
    find "$modules_dir" -name 'x86_64-*' -delete
  fi

  # Rename the slice directory.
  mv "$fat_dir" "$thin_dir"

  # Update Info.plist: rewrite the LibraryIdentifier and drop the
  # `<string>x86_64</string>` from SupportedArchitectures.
  local plist="$xcf/Info.plist"
  /usr/libexec/PlistBuddy -c "Print" "$plist" >/dev/null # sanity check

  # Iterate AvailableLibraries entries and patch the matching one.
  local idx
  local count
  count=$(/usr/libexec/PlistBuddy -c "Print :AvailableLibraries" "$plist" \
    | grep -c '^    Dict {')
  for ((idx=0; idx<count; idx++)); do
    local lib_id
    lib_id=$(/usr/libexec/PlistBuddy -c "Print :AvailableLibraries:$idx:LibraryIdentifier" "$plist" 2>/dev/null || true)
    if [[ "$lib_id" == "ios-arm64_x86_64-simulator" ]]; then
      /usr/libexec/PlistBuddy -c "Set :AvailableLibraries:$idx:LibraryIdentifier ios-arm64-simulator" "$plist"
      # Walk the SupportedArchitectures array and drop x86_64.
      local arch_idx=0
      while :; do
        local arch
        arch=$(/usr/libexec/PlistBuddy -c "Print :AvailableLibraries:$idx:SupportedArchitectures:$arch_idx" "$plist" 2>/dev/null || true)
        if [[ -z "$arch" ]]; then break; fi
        if [[ "$arch" == "x86_64" ]]; then
          /usr/libexec/PlistBuddy -c "Delete :AvailableLibraries:$idx:SupportedArchitectures:$arch_idx" "$plist"
          break
        fi
        arch_idx=$((arch_idx + 1))
      done
      break
    fi
  done

  printf "  %-22s %5d KB -> %5d KB (saved %d KB)\n" \
    "$name:" "$before_kb" "$after_kb" "$((before_kb - after_kb))"
}

echo "Thinning iOS xcframeworks (arm64-only simulator slice):"
for xcf in "${xcframeworks[@]}"; do
  if [[ -d "$xcf" ]]; then
    thin_one "$xcf"
  else
    echo "  $(basename "$xcf"): not found, skipping"
  fi
done

echo "Done. Delete both swiftpm state dirs to force a fresh SwiftPM resolve:"
echo "  example/ios/Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm"
echo "  example/ios/Runner.xcworkspace/xcshareddata/swiftpm"
