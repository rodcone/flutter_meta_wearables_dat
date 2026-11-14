"""Check teardown wiring that the standalone production-handler harness cannot load."""
from pathlib import Path
import re
root = Path('ios/flutter_meta_wearables_dat/Sources/flutter_meta_wearables_dat')
plugin = (root / 'MetaWearablesDatPlugin.swift').read_text()
assert re.search(r'func detachFromEngine\(for registrar: FlutterPluginRegistrar\)\s*\{\s*deviceStateHandler\?\.dispose\(\)', plugin)
handler = (root / 'DeviceStateStreamHandler.swift').read_text()
for forbidden in ('createSession(', 'addCamera(', 'addMotion(', 'startStreamSession('):
    assert forbidden not in handler, f'Device-state observation must not own sessions: {forbidden}'
print('iOS Device State teardown wiring passed')
