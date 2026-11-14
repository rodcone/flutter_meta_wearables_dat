#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
swiftc -swift-version 5 -warnings-as-errors -emit-module -emit-library \
  -module-name Flutter scripts/tests/ios_stream_lifecycle/Flutter.swift \
  -emit-module-path "$test_dir/Flutter.swiftmodule" -o "$test_dir/libFlutter.dylib"
swiftc -swift-version 5 -warnings-as-errors -emit-module -emit-library \
  -module-name MWDATCore scripts/tests/ios_device_state/MWDATCore.swift \
  -emit-module-path "$test_dir/MWDATCore.swiftmodule" -o "$test_dir/libMWDATCore.dylib"
swiftc -swift-version 5 -warnings-as-errors -parse-as-library \
  -I "$test_dir" -L "$test_dir" -lFlutter -lMWDATCore \
  -Xlinker -rpath -Xlinker "$test_dir" \
  ios/flutter_meta_wearables_dat/Sources/flutter_meta_wearables_dat/DeviceStateStreamHandler.swift \
  scripts/tests/ios_device_state/DeviceStateTests.swift \
  -o "$test_dir/device-state-tests"
"$test_dir/device-state-tests"
python3 scripts/tests/ios_device_state/check_wiring.py
