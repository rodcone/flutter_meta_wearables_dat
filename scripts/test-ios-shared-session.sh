#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
sources=ios/flutter_meta_wearables_dat/Sources/flutter_meta_wearables_dat
swiftc -swift-version 5 -warnings-as-errors -parse-as-library \
  -module-cache-path "$test_dir/module-cache" \
  "$sources/SharedSessionPolicy.swift" \
  scripts/tests/ios_motion/SharedSessionPolicyTests.swift \
  -o "$test_dir/shared-session-tests"
"$test_dir/shared-session-tests"
