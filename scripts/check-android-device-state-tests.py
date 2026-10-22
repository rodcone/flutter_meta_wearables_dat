"""Require the real device-state handler suite to execute successfully in CI."""
from pathlib import Path
import xml.etree.ElementTree as ET

report = Path('example/build/flutter_meta_wearables_dat/test-results/testDebugUnitTest/'
              'TEST-io.rodcone.flutter_meta_wearables_dat.DeviceStateStreamHandlerTest.xml')
if not report.is_file():
    raise SystemExit(f'Missing JUnit report: {report}')
cases = ET.parse(report).getroot().findall('testcase')
if not cases or any(case.find(tag) is not None for case in cases
                    for tag in ('failure', 'error', 'skipped')):
    raise SystemExit('Device State tests must execute without skips or failures')
print(f'Android Device State: {len(cases)} tests passed')
