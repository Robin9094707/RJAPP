#!/usr/bin/env python3
"""Create a reproducible complete handoff without credentials or user data."""
from pathlib import Path
import hashlib
import json
import os
import zipfile

root = Path(__file__).resolve().parents[1]
ipa = root / 'RJ-Love-unsigned.ipa'
assert ipa.is_file(), 'Build the IPA first'
import runpy
runpy.run_path(str(root / 'Scripts/verify_ipa.py'))
files = [root / 'RELEASE-4.2.1.md', ipa, root / 'README.md', root / 'INSTALLATION.md', root / 'FEATURES.md', root / 'PRIVACY.md', root / 'Backend/rj_love_server.py', root / 'Design/RJ-AppIcon-3.4.png']
manifest = {'version': '4.2.1', 'build': 421, 'minimum_server': '4.2.0', 'bundled_server': '4.2.0', 'commit': os.environ.get('GITHUB_SHA', 'local'), 'signing': 'unsigned; sign main app and embedded widget extension', 'sha256': {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest() for p in files}}
with zipfile.ZipFile(root / 'RJ-Love-4.2.1-Komplettpaket.zip', 'w', zipfile.ZIP_DEFLATED) as archive:
    for path in files:
        archive.write(path, 'RJ-Love-4.2.1/' + str(path.relative_to(root)))
    archive.writestr('RJ-Love-4.2.1/manifest.json', json.dumps(manifest, indent=2))
print('Complete app/backend package created.')


