#!/bin/bash
# Construit l'app puis le disque d'installation build/VidaaInstall-<version>.dmg.
set -euo pipefail
cd "$(dirname "$0")"
export VERSION="${VERSION:-2.1}"
./build.sh

STAGE=build/dmg; rm -rf "$STAGE"; mkdir -p "$STAGE"
GUIDE="$STAGE/À lire d'abord.html"

echo "→ guide…"
ICON64=$(sips -s format png -Z 192 build/icon-1024.png --out "$STAGE/icon.png" >/dev/null && base64 -i "$STAGE/icon.png" | tr -d '\n')
python3 - "$GUIDE" "$ICON64" "$VERSION" <<'PY'
import sys
out, icon, version = sys.argv[1:]
html = open('tools/dmg/guide.html', encoding='utf-8').read()
open(out, 'w', encoding='utf-8').write(html.replace('{{ICON}}', icon).replace('{{VERSION}}', version))
PY
rm "$STAGE/icon.png"

echo "→ fond…"
swiftc -O tools/dmg/make_background.swift -o build/make_dmg_bg
build/make_dmg_bg "$STAGE/bg.png" 1
build/make_dmg_bg "$STAGE/bg@2x.png" 2
tiffutil -cathidpicheck "$STAGE/bg.png" "$STAGE/bg@2x.png" -out "$STAGE/background.tiff" >/dev/null

if [ ! -x build/.venv/bin/dmgbuild ]; then
  echo "→ dmgbuild…"
  python3 -m venv build/.venv && build/.venv/bin/pip install -q dmgbuild
fi

DMG="build/VidaaInstall-$VERSION.dmg"
rm -f "$DMG"
echo "→ disque…"
build/.venv/bin/dmgbuild -s tools/dmg/settings.py \
  -D app="build/VidaaInstall.app" -D guide="$GUIDE" \
  -D background="$STAGE/background.tiff" -D volicon="build/AppIcon.icns" \
  "VidaaInstall" "$DMG"
echo "✅ $DMG ($(du -h "$DMG" | cut -f1))"
