#!/usr/bin/env python3
"""Render the project's editable SVG into opaque iOS app icon assets.
Development dependencies: cairosvg and Pillow. Already-rendered PNGs are committed.
"""
import io
import json
from pathlib import Path
import cairosvg
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / "assets/app-icon.svg").read_text()
target = ROOT / "ios/GDirect/Assets.xcassets/AppIcon.appiconset"
target.mkdir(parents=True, exist_ok=True)
variants = {
    "AppIcon.png": source,
    "AppIcon-dark.png": source.replace('fill="url(#bg)"', 'fill="#0C1938"'),
    "AppIcon-tinted.png": source.replace('fill="url(#bg)"', 'fill="#181818"').replace('#A8FFE7', '#FFFFFF'),
}
images = []
for index, (name, svg) in enumerate(variants.items()):
    data = cairosvg.svg2png(bytestring=svg.encode(), output_width=1024, output_height=1024)
    image = Image.open(io.BytesIO(data)).convert("RGB")
    image.save(target / name, optimize=True)
    entry = {"filename": name, "idiom": "universal", "platform": "ios", "size": "1024x1024"}
    if index:
        entry["appearances"] = [{"appearance": "luminosity", "value": "dark" if index == 1 else "tinted"}]
    images.append(entry)
(target / "Contents.json").write_text(json.dumps({"images": images, "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
(target.parent / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
print("Created 3 opaque 1024x1024 app icons")
