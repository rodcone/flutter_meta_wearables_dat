#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
output_dir=$(mktemp -d)
trap 'rm -rf "$output_dir"' EXIT
swiftc -emit-library -emit-module -module-name MWDATCore scripts/tests/investigation_device/MWDATCore.swift -o "$output_dir/libMWDATCore.dylib" -emit-module-path "$output_dir/MWDATCore.swiftmodule"
swiftc -I "$output_dir" -L "$output_dir" -lMWDATCore -Xlinker -rpath -Xlinker "$output_dir" ios/flutter_meta_wearables_dat/Sources/flutter_meta_wearables_dat/StreamInvestigationTrace.swift ios/flutter_meta_wearables_dat/Sources/flutter_meta_wearables_dat/InvestigationDeviceObserver.swift scripts/tests/investigation_device/main.swift -o "$output_dir/test"
MWDAT_INVESTIGATION=0 "$output_dir/test" 2> "$output_dir/off.log"
MWDAT_INVESTIGATION=1 "$output_dir/test" 2> "$output_dir/on.log"
python3 - "$output_dir" <<'PY'
import json
from pathlib import Path
import sys
root = Path(sys.argv[1])
def records(name):
    return [json.loads(line.split('[MWDAT-TRACE] ', 1)[1])
            for line in (root / name).read_text().splitlines() if '[MWDAT-TRACE] ' in line]
assert records('off.log') == []
rows = records('on.log')
assert len(rows) == 8, rows
assert [r['seq'] for r in rows] == list(range(1, 9))
assert all(r['parentId'] == 'parent-fixture' for r in rows[:5])
assert rows[2]['linkState'] == 'disconnected'
assert rows[3]['donState'] == 'doffed' and rows[3]['hingeState'] == 'closed'
assert rows[4]['errorOrigin'] == 'errorStream'
assert rows[4]['unexpectedDescription'] == 'Device unavailable'
assert rows[-1]['event'] == 'deviceObservationUnavailable'
assert all(isinstance(r['uptimeUs'], int) and isinstance(r['wallTimeUs'], int) for r in rows)
print('Device investigation: opt-out, snapshots, bounded errors, cancellation and late callbacks passed')
PY
