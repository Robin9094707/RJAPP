#!/usr/bin/env python3
"""Generate all Xcode icon sizes from the approved generated RJ master (Pillow)."""
from pathlib import Path
import json
from PIL import Image
root = Path(__file__).resolve().parents[1]
source = Image.open(root / 'Design/RJ-AppIcon-2.1.png').convert('RGB')
icons = root / 'App/Resources/Assets.xcassets/AppIcon.appiconset'
for entry in json.loads((icons / 'Contents.json').read_text())['images']:
    pixels = round(float(entry['size'].split('x')[0]) * float(entry['scale'].replace('x', '')))
    source.resize((pixels, pixels), Image.Resampling.LANCZOS).save(icons / entry['filename'])
brand = icons.parent / 'BrandMark.imageset'
brand.mkdir(exist_ok=True)
source.resize((256,256), Image.Resampling.LANCZOS).save(brand / 'BrandMark.png')
(brand / 'Contents.json').write_text(json.dumps({'images':[{'filename':'BrandMark.png','idiom':'universal'}], 'info':{'author':'xcode','version':1}},indent=2))
print('All app icon sizes and in-app brand mark generated.')
