"""Fail CI if required audio/lifecycle suites are absent, empty, skipped or failing."""
from pathlib import Path
import xml.etree.ElementTree as ET

root = Path('example/build/flutter_meta_wearables_dat/test-results/testDebugUnitTest')
for name in ('AudioFrameStreamHandlerTest', 'CameraStreamConfigurationTest',
             'PermissionRequestCoordinatorTest', 'AndroidAudioLifecycleTest',
             'DeviceSessionLifecycleTest'):
    report = root / f'TEST-io.rodcone.flutter_meta_wearables_dat.{name}.xml'
    if not report.is_file():
        raise SystemExit(f'Missing JUnit report: {report}')
    cases = ET.parse(report).getroot().findall('testcase')
    if not cases or any(case.find(tag) is not None for case in cases
                        for tag in ('failure', 'error', 'skipped')):
        raise SystemExit(f'{name} must execute with no skipped or failed tests')
    print(f'{name}: {len(cases)} tests passed')
