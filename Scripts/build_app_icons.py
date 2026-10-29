#!/usr/bin/env python3
"""Generate all Xcode icon sizes from the approved generated RJ master (Pillow)."""
from pathlib import Path
import json
from PIL import Image
root = Path(__file__).resolve().parents[1]
source = Image.open(root / 'Design/RJ-AppIcon-3.4.png').convert('RGB')
icons = root / 'App/Resources/Assets.xcassets/AppIcon.appiconset'
for entry in json.loads((icons / 'Contents.json').read_text())['images']:
    pixels = round(float(entry['size'].split('x')[0]) * float(entry['scale'].replace('x', '')))
    source.resize((pixels, pixels), Image.Resampling.LANCZOS).save(icons / entry['filename'])
brand = icons.parent / 'BrandMark.imageset'
brand.mkdir(exist_ok=True)
source.resize((256,256), Image.Resampling.LANCZOS).save(brand / 'BrandMark.png')
(brand / 'Contents.json').write_text(json.dumps({'images':[{'filename':'BrandMark.png','idiom':'universal'}], 'info':{'author':'xcode','version':1}},indent=2))
print('All app icon sizes and in-app brand mark generated.')
# Launch mark: rounded brand image at 112 pt, shared by the system launch screen and the SwiftUI splash.
from PIL import ImageDraw
launch = icons.parent / 'LaunchMark.imageset'
launch.mkdir(exist_ok=True)
images = []
for scale in (2, 3):
    pixels = 112 * scale
    big = pixels * 4
    mask = Image.new('L', (big, big), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, big - 1, big - 1), radius=round(big * 0.235), fill=255)
    mark = source.resize((pixels, pixels), Image.Resampling.LANCZOS).convert('RGBA')
    mark.putalpha(mask.resize((pixels, pixels), Image.Resampling.LANCZOS))
    name = f'LaunchMark@{scale}x.png'
    mark.save(launch / name, optimize=True)
    images.append({'filename': name, 'idiom': 'universal', 'scale': f'{scale}x'})
images.insert(0, {'idiom': 'universal', 'scale': '1x'})
(launch / 'Contents.json').write_text(json.dumps({'images': images, 'info': {'author': 'xcode', 'version': 1}}, indent=2))
print('Launch mark generated.')
