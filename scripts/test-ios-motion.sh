#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
sources=ios/flutter_meta_wearables_dat/Sources/flutter_meta_wearables_dat
swiftc -swift-version 5 -warnings-as-errors -emit-module -emit-library \
  -module-name Flutter scripts/tests/ios_stream_lifecycle/Flutter.swift \
  -emit-module-path "$test_dir/Flutter.swiftmodule" -o "$test_dir/libFlutter.dylib"
swiftc -swift-version 5 -warnings-as-errors -emit-module -emit-library \
  -module-name MWDATCore scripts/tests/ios_motion/MWDATCore.swift \
  -emit-module-path "$test_dir/MWDATCore.swiftmodule" -o "$test_dir/libMWDATCore.dylib"
swiftc -swift-version 5 -warnings-as-errors -emit-module -emit-library \
  -I "$test_dir" -L "$test_dir" -lMWDATCore \
  -module-name MWDATMotion scripts/tests/ios_motion/MWDATMotion.swift \
  -emit-module-path "$test_dir/MWDATMotion.swiftmodule" -o "$test_dir/libMWDATMotion.dylib"
swiftc -swift-version 5 -warnings-as-errors -parse-as-library \
  -I "$test_dir" -L "$test_dir" -lFlutter -lMWDATCore -lMWDATMotion \
  -Xlinker -rpath -Xlinker "$test_dir" \
  "$sources/MotionStreamHandler.swift" "$sources/MotionController.swift" \
  scripts/tests/ios_motion/MotionTests.swift -o "$test_dir/motion-tests"
"$test_dir/motion-tests"
