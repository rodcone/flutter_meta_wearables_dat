#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
output_dir=$(mktemp -d)
trap 'rm -rf "$output_dir"' EXIT
swiftc ios/flutter_meta_wearables_dat/Sources/flutter_meta_wearables_dat/StreamInvestigationTrace.swift scripts/tests/stream_investigation/main.swift -o "$output_dir/test"
swiftc example/ios/Runner/InvestigationTraceSink.swift scripts/tests/investigation_sink/main.swift -o "$output_dir/sink-test"
"$output_dir/sink-test"
MWDAT_INVESTIGATION=0 "$output_dir/test" 2> "$output_dir/disabled.log"
MWDAT_INVESTIGATION=1 "$output_dir/test" 2> "$output_dir/enabled.log"
MWDAT_INVESTIGATION=0 "$output_dir/test" --mwdat-investigation 2> "$output_dir/argument.log"
MWDAT_INVESTIGATION=1 "$output_dir/test" --limit 2> "$output_dir/limit.log"
python3 - "$output_dir" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])

def records(name):
    return [json.loads(line.split('[MWDAT-TRACE] ', 1)[1])
            for line in (root / name).read_text().splitlines()
            if '[MWDAT-TRACE] ' in line]

assert not records('disabled.log'), 'Opt-out must produce no trace records'
for name in ['enabled.log', 'argument.log']:
    events = records(name)
    assert len(events) == 19
    assert [e['seq'] for e in events] == list(range(1, 20))
    assert len({e['runId'] for e in events}) == 1
    begins = {e['spanId']: e for e in events if e['event'] == 'cleanupPhaseBegin'}
    ends = {e['spanId']: e for e in events if e['event'] == 'cleanupPhaseEnd'}
    assert len(begins) == 9 and begins.keys() == ends.keys()
    parent = next(e for e in begins.values() if e['phase'] == 'parent')
    for identity, begin in begins.items():
        end = ends[identity]
        assert end['phase'] == begin['phase']
        assert end['parentSpanId'] == begin['parentSpanId']
        assert end['operationStartUptimeUs'] >= begin['uptimeUs']
        assert end['operationEndUptimeUs'] >= end['operationStartUptimeUs']
        assert end['durationUs'] == end['operationEndUptimeUs'] - end['operationStartUptimeUs']
        assert end['traceCallUptimeUs'] >= end['operationEndUptimeUs']
        if begin['phase'] == 'child':
            assert begin['parentSpanId'] == parent['spanId']
        else:
            assert begin['parentSpanId'] is None
    for event in events:
        assert event['traceFieldsUs'] >= 0 and event['traceLockWaitUs'] >= 0
        assert event['uptimeUs'] >= event['traceCallUptimeUs']
    slow = next(e for e in events if e['event'] == 'slowFields')
    assert slow['traceFieldsUs'] >= 5_000, 'Measure expensive field capture separately'

limited = records('limit.log')
assert len(limited) == 2_001
assert [e['seq'] for e in limited] == list(range(1, 2_002))
assert limited[-1]['event'] == 'traceLimitReached'
assert sum(e['event'] == 'traceLimitReached' for e in limited) == 1
print('Stream investigation: opt-out, launch flag, concurrent spans, timing and cap passed')
PY
