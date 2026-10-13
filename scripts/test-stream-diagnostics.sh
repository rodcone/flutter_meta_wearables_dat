#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
output_dir=$(mktemp -d)
trap 'rm -rf "$output_dir"' EXIT
swiftc ios/flutter_meta_wearables_dat/Sources/flutter_meta_wearables_dat/StreamDiagnosticsTracker.swift scripts/tests/stream_diagnostics/main.swift -o "$output_dir/test"
"$output_dir/test"
