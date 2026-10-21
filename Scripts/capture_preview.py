#!/usr/bin/env python3
"""Boot a fresh compatible simulator and capture real Debug-only sample screens."""
import json
from pathlib import Path
import subprocess
import time


def run(*args, timeout=120, capture=False):
    return subprocess.run(args, check=True, text=True, capture_output=capture, timeout=timeout)


runtimes = json.loads(run('xcrun', 'simctl', 'list', 'runtimes', '-j', capture=True).stdout)['runtimes']
compatible = [r for r in runtimes if r.get('isAvailable') and 'iOS' in r['name'] and tuple(map(int, r['version'].split('.'))) >= (26, 1)]
assert compatible, 'No available iOS 26.1+ simulator runtime'
runtime = max(compatible, key=lambda r: tuple(map(int, r['version'].split('.'))))
types = json.loads(run('xcrun', 'simctl', 'list', 'devicetypes', '-j', capture=True).stdout)['devicetypes']
phones = [d for d in types if d.get('productFamily') == 'iPhone' or d['name'].startswith('iPhone')]
preferred = next((d for d in phones if d['name'] == 'iPhone 15 Plus'), phones[-1])
device = run('xcrun', 'simctl', 'create', 'RJLovePreview', preferred['identifier'], runtime['identifier'], capture=True).stdout.strip()
try:
    run('xcrun', 'simctl', 'boot', device)
    run('xcrun', 'simctl', 'bootstatus', device, '-b', timeout=360)
    run('xcrun', 'simctl', 'status_bar', device, 'override', '--time', '9:41', '--dataNetwork', 'wifi', '--wifiMode', 'active', '--wifiBars', '3', '--batteryState', 'charged', '--batteryLevel', '100')
    app = Path('.sim-derived/Build/Products/Debug-iphonesimulator/RJ Love.app')
    assert app.is_dir()
    run('xcrun', 'simctl', 'install', device, str(app))
    for name, arguments in [('Wir', []), ('Chat', ['--preview-hub']), ('Health', ['--preview-health']), ('Duftpost', ['--preview-farts']), ('Recorder', ['--preview-recorder']), ('Liebe', ['--preview-love'])]:
        run('xcrun', 'simctl', 'launch', device, 'eu.rjuhas.rjlove', '--preview', *arguments)
        time.sleep(5)
        run('xcrun', 'simctl', 'io', device, 'screenshot', f'Preview-{name}.png')
        run('xcrun', 'simctl', 'terminate', device, 'eu.rjuhas.rjlove')
finally:
    subprocess.run(['xcrun', 'simctl', 'shutdown', device], timeout=30)
