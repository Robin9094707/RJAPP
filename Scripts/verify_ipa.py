#!/usr/bin/env python3
"""Verify the shipped IPA, including compiled app icon and the embedded widgets."""
from pathlib import Path
import plistlib
import zipfile

root=Path(__file__).resolve().parents[1]
with zipfile.ZipFile(root/'RJ-Love-unsigned.ipa') as archive:
    names=archive.namelist()
    app='Payload/RJ Love.app/'
    info=plistlib.loads(archive.read(app+'Info.plist'))
    assert info['CFBundleShortVersionString']=='2.4.0'
    assert info['CFBundleVersion']=='240'
    import json
    quips=json.loads(archive.read(app+'Duftsprueche.json'))
    assert len(quips)==400 and len({q['id'] for q in quips})==400, 'Offline quips missing'
    assert app+'Assets.car' in names, 'Compiled image resources missing'
    assert info['CFBundleIcons']['CFBundlePrimaryIcon']['CFBundleIconName']=='AppIcon', 'Primary app icon missing'
    assert any(n.startswith(app+'AppIcon') and n.endswith('.png') for n in names), 'Device icon files missing'
    assert app+'PrivacyInfo.xcprivacy' in names, 'Privacy manifest missing'
    extension=plistlib.loads(archive.read(app+'PlugIns/RJLoveWidgets.appex/Info.plist'))
    assert extension['CFBundleIdentifier']=='eu.rjuhas.rjlove.widgets'
    assert 'push-to-talk' in info.get('UIBackgroundModes', []), 'PTT background mode missing'
    assert info.get('NSMicrophoneUsageDescription'), 'Microphone purpose missing'
print('IPA verified: version 2.4.0 (240), compiled app icon, resources, microphone purpose and widget extension.')
