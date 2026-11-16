#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOCALE="$ROOT/fastlane/metadata/android/en-US"
RECIPE="$ROOT/publishing/fdroid/io.github.daksh_mor.valu.yml"

ruby -e 'require "yaml"; YAML.parse_file(ARGV.fetch(0)); puts "YAML syntax: OK"' "$RECIPE"

python3 - "$ROOT" <<'PY'
from pathlib import Path
import re
import struct
import sys

root = Path(sys.argv[1])
locale = root / "fastlane/metadata/android/en-US"
recipe = root / "publishing/fdroid/io.github.daksh_mor.valu.yml"

limits = {
    "title.txt": 50,
    "short_description.txt": 80,
    "full_description.txt": 4000,
    "changelogs/1.txt": 500,
}

texts = {}
for relative, limit in limits.items():
    path = locale / relative
    value = path.read_text(encoding="utf-8").rstrip("\n")
    texts[relative] = value
    if not value:
        raise SystemExit(f"{relative}: empty")
    if len(value) > limit:
        raise SystemExit(f"{relative}: {len(value)} characters exceeds {limit}")
    print(f"{relative}: {len(value)}/{limit} characters")

if texts["short_description.txt"].endswith("."):
    raise SystemExit("short_description.txt: must not end with a period")

banned = re.compile(r"\b(?:valorant|valo|riot)\b", re.IGNORECASE)
for relative, value in texts.items():
    if banned.search(value):
        raise SystemExit(f"{relative}: contains prohibited public wording")

def png_size(path: Path) -> tuple[int, int]:
    data = path.read_bytes()[:24]
    if len(data) != 24 or data[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit(f"{path}: not a valid PNG")
    return struct.unpack(">II", data[16:24])

icon = locale / "images/icon.png"
if png_size(icon) != (512, 512):
    raise SystemExit("images/icon.png: expected 512x512")
print("images/icon.png: 512x512 PNG")

screenshots = sorted((locale / "images/phoneScreenshots").glob("*.png"))
if not 3 <= len(screenshots) <= 5:
    raise SystemExit(f"phoneScreenshots: expected 3-5 PNGs, found {len(screenshots)}")
for screenshot in screenshots:
    width, height = png_size(screenshot)
    if width < 320 or height < 320 or width <= height:
        raise SystemExit(f"{screenshot.name}: unexpected phone screenshot size {width}x{height}")
    print(f"{screenshot.name}: {width}x{height}, {screenshot.stat().st_size} bytes")

recipe_text = recipe.read_text(encoding="utf-8")
required_recipe_fragments = (
    "Godot@4.7.1-stable",
    "java-21-openjdk-amd64",
    "target=editor",
    "target=template_release arch=arm64",
    "gradle generateGodotTemplates",
    "package/signed",
    "custom_template/release",
    "--export-release",
    "ndk: 29.0.14206865",
)
for fragment in required_recipe_fragments:
    if fragment not in recipe_text:
        raise SystemExit(f"recipe: missing {fragment!r}")

preset = (root / "export_presets.cfg").read_text(encoding="utf-8")
required_preset_fragments = (
    'version/code=1',
    'version/name="1.0.0"',
    'package/unique_name="io.github.daksh_mor.valu"',
    'architectures/arm64-v8a=true',
)
for fragment in required_preset_fragments:
    if fragment not in preset:
        raise SystemExit(f"export_presets.cfg: missing {fragment!r}")

for key in ("keystore/release", "keystore/release_user", "keystore/release_password"):
    match = re.search(rf"(?m)^{re.escape(key)}=(.*)$", preset)
    if match is None or match.group(1).strip() != '""':
        raise SystemExit(f"export_presets.cfg: {key} must remain empty")

print("Recipe source-build markers: OK")
print("Package, version, and arm64 preset: OK")
print("Release keystore fields: empty")
PY
