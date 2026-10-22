#!/usr/bin/env python3
"""Real screen-size regression matrix: 14 Pro, small SE, 15 Plus, and large text."""
import argparse
import json
from pathlib import Path
import subprocess
import time


def run(*args, timeout=120, capture=False):
    return subprocess.run(args, check=True, text=True, capture_output=capture, timeout=timeout)


def launch_preview(device, arguments):
    for attempt in range(2):
        try:
            run('xcrun', 'simctl', 'launch', device, 'eu.rjuhas.rjlove', '--preview', *arguments, timeout=180)
            return
        except subprocess.TimeoutExpired:
            if attempt:
                raise
            # A fresh VM can finish migration before LaunchServices is ready.
            # Restart this sample app once, then require a successful real launch.
            subprocess.run(['xcrun', 'simctl', 'terminate', device, 'eu.rjuhas.rjlove'], timeout=30)
            run('xcrun', 'simctl', 'bootstatus', device, '-b', timeout=180)


parser = argparse.ArgumentParser()
parser.add_argument('--device', choices=['iPhone 14 Pro', 'iPhone SE (3rd generation)', 'iPhone 15 Plus'])
args = parser.parse_args()

runtimes = json.loads(run('xcrun', 'simctl', 'list', 'runtimes', '-j', capture=True).stdout)['runtimes']
compatible = [r for r in runtimes if r.get('isAvailable') and 'iOS' in r['name'] and tuple(map(int, r['version'].split('.'))) >= (26, 1)]
assert compatible, 'No available iOS 26.1+ simulator runtime'
runtime = max(compatible, key=lambda r: tuple(map(int, r['version'].split('.'))))
types = json.loads(run('xcrun', 'simctl', 'list', 'devicetypes', '-j', capture=True).stdout)['devicetypes']
app = Path('.sim-derived/Build/Products/Debug-iphonesimulator/RJ Love.app')
assert app.is_dir()
server_log = open('UI-backend.log', 'w')
server = subprocess.Popen(['python3', 'Scripts/ui_test_server.py'], stdout=server_log, stderr=subprocess.STDOUT)
try:
    time.sleep(2)
    for index, name in enumerate([args.device] if args.device else ['iPhone 14 Pro', 'iPhone SE (3rd generation)', 'iPhone 15 Plus']):
        model = next((d for d in types if d['name'] == name), None)
        assert model, f'Required simulator model missing: {name}'
        device = run('xcrun', 'simctl', 'create', 'RJLove-' + name, model['identifier'], runtime['identifier'], capture=True).stdout.strip()
        slug = name.replace(' ', '').replace('(', '').replace(')', '')
        try:
            run('xcrun', 'simctl', 'boot', device)
            try:
                run('xcrun', 'simctl', 'bootstatus', device, '-b', timeout=720)
            except subprocess.TimeoutExpired:
                # Preserve completed migration work; do not erase and start over.
                run('xcrun', 'simctl', 'shutdown', device, timeout=60)
                run('xcrun', 'simctl', 'boot', device)
                run('xcrun', 'simctl', 'bootstatus', device, '-b', timeout=360)
            run('xcrun', 'simctl', 'status_bar', device, 'override', '--time', '9:41', '--dataNetwork', 'wifi', '--wifiMode', 'active', '--wifiBars', '3', '--batteryState', 'charged', '--batteryLevel', '100')
            run('xcrun', 'simctl', 'install', device, str(app))
            screens = [('Wir', []), ('Schnitt', ['--preview-recorder', '--preview-draft']), ('Funk', ['--preview-radio']), ('Einrichtung', ['--preview-setup']), ('Push', ['--preview-delivery'])]
            if name == 'iPhone 14 Pro':
                screens += [('Kalender', ['--preview-fart-calendar']), ('Jahr', ['--preview-fart-year']), ('Furzkarte', ['--preview-fart-map']), ('Chat', ['--preview-hub']), ('Health', ['--preview-health']), ('Duftpost', ['--preview-farts']), ('Liebe', ['--preview-love']), ('Grossschrift', ['--preview-radio', '--preview-accessibility'])]
            for title, arguments in screens:
                launch_preview(device, arguments)
                time.sleep(3)
                run('xcrun', 'simctl', 'io', device, 'screenshot', f'Preview-{slug}-{title}.png')
                run('xcrun', 'simctl', 'terminate', device, 'eu.rjuhas.rjlove')
            action = 'test' if index == 0 else 'test-without-building'
            try:
                run('xcodebuild', '-project', 'RJLove.xcodeproj', '-scheme', 'RJLove', '-configuration', 'Debug', '-destination', f'platform=iOS Simulator,id={device}', '-derivedDataPath', '.sim-derived', '-resultBundlePath', f'Layout-{slug}.xcresult', 'CODE_SIGNING_ALLOWED=NO', '-parallel-testing-enabled', 'NO', action, timeout=600)
            finally:
                result = Path(f'Layout-{slug}.xcresult')
                if result.exists():
                    subprocess.run(['xcrun', 'xcresulttool', 'export', 'attachments', '--path', str(result), '--output-path', f'UIAttachments-{slug}'], timeout=60)

        finally:
            subprocess.run(['xcrun', 'simctl', 'shutdown', device], timeout=30)
finally:
    server.terminate()
    server.wait(timeout=10)
    server_log.close()
