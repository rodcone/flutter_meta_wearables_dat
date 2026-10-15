#!/usr/bin/env python3
"""Set SDK logging in the built example only; never modify the source plist."""
import base64
import binascii
import copy
import os
from pathlib import Path
import plistlib
import sys


def configure(source, built, dart_defines):
    # Flutter passes each KEY=value separately, base64 encoded. Exact matching
    # avoids enabling file logging for false, similarly named flags or junk.
    definitions = []
    for item in dart_defines.split(','):
        if not item:
            continue
        try:
            definitions.append(base64.b64decode(item, validate=True).decode('utf-8'))
        except (binascii.Error, UnicodeDecodeError) as error:
            raise ValueError('Malformed DART_DEFINES; refusing ambiguous logging config') from error
    enabled = 'MWDAT_INVESTIGATION=true' in definitions
    original = source.get('MWDAT', {})
    target = built.setdefault('MWDAT', {})
    # Always restore from source first: no investigation logging leaks into an
    # incremental normal build. Preserve other MWDAT and Logging settings.
    if 'Logging' in original:
        target['Logging'] = copy.deepcopy(original['Logging'])
    else:
        target.pop('Logging', None)
    if enabled:
        target.setdefault('Logging', {})['Level'] = 'warning'
    return built


def main():
    source_path, built_path = map(Path, sys.argv[1:3])
    if source_path.resolve() == built_path.resolve():
        raise ValueError('Built plist must differ from source')
    source = plistlib.loads(source_path.read_bytes())
    raw = built_path.read_bytes()
    built = configure(source, plistlib.loads(raw), os.environ.get('DART_DEFINES', ''))
    output_format = plistlib.FMT_BINARY if raw.startswith(b'bplist') else plistlib.FMT_XML
    built_path.write_bytes(plistlib.dumps(built, fmt=output_format, sort_keys=False))


if __name__ == '__main__':
    main()
