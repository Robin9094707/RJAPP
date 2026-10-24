#!/usr/bin/env python3
"""Cinema navigation smoke test and light/dark interface captures."""
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
    run('xcrun','simctl','status_bar',device,'override','--time','9:41','--dataNetwork','wifi','--wifiMode','active','--wifiBars','3','--batteryState','charged','--batteryLevel','100')
    run('xcrun','simctl','install',device,'.sim-derived/Build/Products/Debug-iphonesimulator/RJ Love.app')
    for title,arguments in [('Kino',['--preview-cinema'])]:
        run('xcrun','simctl','launch',device,'eu.rjuhas.rjlove','--preview',*arguments)
        time.sleep(10)
        run('xcrun','simctl','io',device,'screenshot','Preview-Design-'+title+'.png')
        run('xcrun','simctl','terminate',device,'eu.rjuhas.rjlove')
    run('xcrun','simctl','ui',device,'appearance','dark')
    run('xcrun','simctl','launch',device,'eu.rjuhas.rjlove','--preview','--preview-cinema')
    # Appearance changes and cold launches can outlast the launch command on CI.
    time.sleep(15)
    run('xcrun','simctl','io',device,'screenshot','Preview-Design-Kino-Dark.png')
    run('xcrun','simctl','terminate',device,'eu.rjuhas.rjlove')
    run('xcrun','simctl','ui',device,'appearance','light')
    backend_log=open('UI-backend.log','w')
    backend=subprocess.Popen(['python3','Scripts/ui_test_server.py'],stdout=backend_log,stderr=subprocess.STDOUT)
    time.sleep(1)
    try:
        run('xcodebuild','-project','RJLove.xcodeproj','-scheme','RJLove','-configuration','Debug','-destination','platform=iOS Simulator,id='+device,'-derivedDataPath','.sim-derived','-resultBundlePath','Layout-Cinema.xcresult','CODE_SIGNING_ALLOWED=NO','-parallel-testing-enabled','NO','-only-testing:RJLoveUITests/CinemaFlowTests','test',timeout=900)
    finally:
        backend.terminate();backend.wait(timeout=20);backend_log.close()
        if Path('Layout-Cinema.xcresult').exists():
            subprocess.run(['xcrun','xcresulttool','export','attachments','--path','Layout-Cinema.xcresult','--output-path','UIAttachments-Cinema'],timeout=60)
finally:
    subprocess.run(['xcrun','simctl','shutdown',device],timeout=60)
