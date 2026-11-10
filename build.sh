#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP="build/VidaaInstall.app"
INSTALLED="$HOME/Applications/VidaaInstall.app"
mkdir -p build

echo "→ compilation (Apple Silicon + Intel)…"
SRC=(Sources/Vidaa/ClientIdentity.swift Sources/Vidaa/Credentials.swift Sources/Vidaa/MQTTProtocol.swift
  Sources/Core.swift Sources/TV.swift Sources/Model.swift Sources/ModelTV.swift Sources/TVViews.swift Sources/AppsViews.swift Sources/Theme.swift Sources/Views.swift Sources/App.swift Sources/Demo.swift)
for ARCH in arm64 x86_64; do
  swiftc -O -parse-as-library -target $ARCH-apple-macos14.0 \
    -framework AppKit -framework SwiftUI -framework Network -framework Security \
    ${DEFINES:-} "${SRC[@]}" -o build/VidaaInstall-$ARCH &
done
wait
lipo -create build/VidaaInstall-arm64 build/VidaaInstall-x86_64 -output build/VidaaInstall

if [ ! -f build/AppIcon.icns ] || [ tools/make_icon.swift -nt build/AppIcon.icns ]; then
  echo "→ icône…"
  swiftc -O tools/make_icon.swift -o build/make_icon
  build/make_icon build/icon-1024.png
  ICONSET=build/AppIcon.iconset; rm -rf "$ICONSET"; mkdir -p "$ICONSET"
  for s in 16 32 128 256 512; do
    sips -z $s $s build/icon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) build/icon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o build/AppIcon.icns
fi

pkill -x VidaaInstall 2>/dev/null || true
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp build/VidaaInstall "$APP/Contents/MacOS/"
cp web/agent.html "$APP/Contents/Resources/"
cp build/AppIcon.icns "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>io.github.ampiso4.vidaainstall</string>
<key>CFBundleName</key><string>VidaaInstall</string>
<key>CFBundleDisplayName</key><string>VidaaInstall</string>
<key>CFBundleExecutable</key><string>VidaaInstall</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>${VERSION:-2.1}</string>
<key>CFBundleVersion</key><string>${VERSION:-2.1}</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSLocalNetworkUsageDescription</key>
<string>VidaaInstall communique avec le téléviseur Hisense sur le réseau local.</string>
<key>NSAppTransportSecurity</key><dict><key>NSAllowsArbitraryLoads</key><true/></dict>
</dict></plist>
PL
codesign --force --deep --sign - "$APP" 2>/dev/null || true
rm -rf "$INSTALLED"; mkdir -p "$HOME/Applications"; ditto "$APP" "$INSTALLED"
echo "✅ $INSTALLED"
