#!/usr/bin/env python3
"""New gallery/map/relationship previews and three focused UI checks."""
import json
from pathlib import Path
import subprocess
import time


def run(*args, capture=False, timeout=180):
    return subprocess.run(args, check=True, text=True, capture_output=capture, timeout=timeout)


runtimes=json.loads(run('xcrun','simctl','list','runtimes','-j',capture=True).stdout)['runtimes']
runtime=max((r for r in runtimes if r.get('isAvailable') and 'iOS' in r['name'] and tuple(map(int,r['version'].split('.'))) >= (26,1)),key=lambda r:tuple(map(int,r['version'].split('.'))))
types=json.loads(run('xcrun','simctl','list','devicetypes','-j',capture=True).stdout)['devicetypes']
model=next(d for d in types if d['name']=='iPhone 15 Plus')
devices=json.loads(run('xcrun','simctl','list','devices','available','-j',capture=True).stdout)['devices'].get(runtime['identifier'],[])
existing=next((d for d in devices if d['name']=='iPhone 15 Plus'),None)
device=existing['udid'] if existing else run('xcrun','simctl','create','RJLove-Design',model['identifier'],runtime['identifier'],capture=True).stdout.strip()
try:
    if not existing or existing.get('state')!='Booted':run('xcrun','simctl','boot',device)
    run('xcrun','simctl','bootstatus',device,'-b',timeout=720)
    run('xcrun','simctl','install',device,'.sim-derived/Build/Products/Debug-iphonesimulator/RJ Love.app')
    run('xcrun','simctl','ui',device,'appearance','dark')
    run('xcrun','simctl','launch',device,'eu.rjuhas.rjlove','--preview','--preview-gallery')
    time.sleep(8)
    run('xcrun','simctl','io',device,'screenshot','Gallery-Preview.png')
    run('xcrun','simctl','terminate',device,'eu.rjuhas.rjlove')
    run('xcodebuild','-project','RJLove.xcodeproj','-scheme','RJLove','-configuration','Debug','-destination',f'id={device}','-derivedDataPath','.sim-derived','-resultBundlePath','Gallery-Layout.xcresult','CODE_SIGNING_ALLOWED=NO','-parallel-testing-enabled','NO','-only-testing:RJLoveUITests/GalleryLayoutTests','-only-testing:RJLoveUITests/VideoAudioSessionTests','test',timeout=900)
finally:
    if Path('Gallery-Layout.xcresult').exists():subprocess.run(['xcrun','xcresulttool','export','attachments','--path','Gallery-Layout.xcresult','--output-path','Gallery-Attachments'],timeout=60)
    subprocess.run(['xcrun','simctl','shutdown',device],timeout=60)
