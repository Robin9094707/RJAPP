#!/usr/bin/env python3
from pathlib import Path
import json
import plistlib
import sys


ROOT = Path(__file__).resolve().parents[1]
REQUIRED = [
    ".github/workflows/build-ios.yml",
    "project.yml",
    "App/Info.plist",
    "App/RJLove.entitlements",
    "WidgetExtension/Info.plist",
    "WidgetExtension/RJLoveWidgets.entitlements",
    "Backend/rj_love_server.py",
    "App/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json",
]


def fail(message: str) -> None:
    print(f"VALIDATION ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


for relative in REQUIRED:
    if not (ROOT / relative).is_file():
        fail(f"missing {relative}")

for relative in [
    "App/Info.plist",
    "App/RJLove.entitlements",
    "WidgetExtension/Info.plist",
    "WidgetExtension/RJLoveWidgets.entitlements",
    "App/Resources/PrivacyInfo.xcprivacy",
]:
    try:
        with (ROOT / relative).open("rb") as handle:
            plistlib.load(handle)
    except Exception as exc:
        fail(f"invalid plist {relative}: {exc}")

try:
    json.loads((ROOT / "App/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json").read_text())
except Exception as exc:
    fail(f"invalid app icon Contents.json: {exc}")

project = (ROOT / "project.yml").read_text()
workflow = (ROOT / ".github/workflows/build-ios.yml").read_text()
for expected in ["eu.rjuhas.rjlove", "eu.rjuhas.rjlove.widgets", 'iOS: "26.1"', "RJLoveWidgets"]:
    if expected not in project:
        fail(f"project.yml missing {expected}")
for expected in ["workflow_dispatch", "CODE_SIGNING_ALLOWED=NO", "RJ-Love-unsigned.ipa", "RJ-Love-build.log"]:
    if expected not in workflow:
        fail(f"workflow missing {expected}")


for path in ROOT.rglob("*"):
    if not path.is_file() or path.suffix not in {".swift", ".yml", ".md", ".plist"}:
        continue
    content = path.read_text(errors="ignore")
    if "/Users/" in content or "C:\\Users\\" in content:
        fail(f"local absolute path in {path.relative_to(ROOT)}")

import struct
icons = ROOT / "App/Resources/Assets.xcassets/AppIcon.appiconset"
for item in json.loads((icons / "Contents.json").read_text())["images"]:
    path = icons / item["filename"]
    if not path.is_file():
        fail("missing app icon " + path.name)
    data = path.read_bytes()
    expected = round(float(item["size"].split("x")[0]) * float(item["scale"].replace("x", "")))
    if data[:8] != b"\x89PNG\r\n\x1a\n" or struct.unpack(">II", data[16:24]) != (expected, expected):
        fail("incorrect app icon dimensions " + path.name)
if "buildPhase: resources" not in project:
    fail("App resources must be an explicit source with resource build phase")
with (ROOT / "App/Info.plist").open("rb") as handle:
    if not plistlib.load(handle).get("NSMicrophoneUsageDescription"):
        fail("microphone purpose missing")

print("RJ Love project validation passed.")
