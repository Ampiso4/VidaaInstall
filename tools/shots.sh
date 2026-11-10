#!/bin/bash
# Captures d'écran du README, avec des données fictives (build DEMO, jamais publié).
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=docs/images; mkdir -p "$OUT"
WORK=build/shots; rm -rf "$WORK"; mkdir -p "$WORK"
SRC=($(sed -n '/^SRC=(/,/)$/p' build.sh | tr -d '()' | sed 's/SRC=//'))
swiftc -O -D DEMO -parse-as-library -target arm64-apple-macos14.0 \
  -framework AppKit -framework SwiftUI -framework Network -framework Security "${SRC[@]}" -o "$WORK/bin"
cp -R build/VidaaInstall.app "$WORK/Shots.app"
cp "$WORK/bin" "$WORK/Shots.app/Contents/MacOS/VidaaInstall"
codesign --force --sign - "$WORK/Shots.app" 2>/dev/null
BIN="$WORK/Shots.app/Contents/MacOS/VidaaInstall"
cat > "$WORK/winid.swift" <<'SW'
import CoreGraphics
let l = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
for w in l where (w[kCGWindowOwnerName as String] as? String) == "VidaaInstall" && (w[kCGWindowLayer as String] as? Int) == 0 { print(w[kCGWindowNumber as String]!); break }
SW
swiftc "$WORK/winid.swift" -o "$WORK/winid"
shot() { # écran état attente fichier
  pkill -x VidaaInstall 2>/dev/null || true
  while pgrep -x VidaaInstall >/dev/null; do sleep 0.2; done
  env VIDAA_SHOTS=1 VIDAA_PANE="$1" VIDAA_SHOTS_STATE="$2" "$BIN" >/dev/null 2>&1 &
  sleep "$3"
  local id=""; for _ in 1 2 3 4 5; do id=$("$WORK/winid"); [ -n "$id" ] && break; sleep 0.5; done
  screencapture -x -l "$id" "$OUT/$4.png"
  echo "  $4"
}
if [ "${1:-}" != "--gif" ]; then
shot tvs none 2 _warmup; rm -f "$OUT/_warmup.png"
shot tvs none 3.5 televiseurs
shot tvs scan 2.6 scan
shot install success 3.4 installer
shot apps none 9 applications
shot backups none 3 sauvegardes
shot tvs pair 3 appairage
fi
pkill -x VidaaInstall 2>/dev/null || true
[ "${1:-}" = "--gif" ] && GIF=1

# GIF de démonstration : visite automatique des écrans, enregistrée puis convertie.
if [ "${1:-}" = "--gif" ] || [ "${GIF:-}" = "1" ]; then
  cat > "$WORK/bounds.swift" <<'SW'
import CoreGraphics
let l = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
if let w = l.first(where: { ($0[kCGWindowOwnerName as String] as? String) == "VidaaInstall" && ($0[kCGWindowLayer as String] as? Int) == 0 }),
   let b = w[kCGWindowBounds as String] as? [String: Double] { print("\(Int(b["X"]!)),\(Int(b["Y"]!)),\(Int(b["Width"]!)),\(Int(b["Height"]!))") }
SW
  swiftc "$WORK/bounds.swift" -o "$WORK/bounds"
  while pgrep -x VidaaInstall >/dev/null; do sleep 0.2; done
  env VIDAA_SHOTS=1 VIDAA_PANE=tvs VIDAA_SHOTS_TOUR=1 "$BIN" >/dev/null 2>&1 &
  sleep 0.6
  R=$("$WORK/bounds")
  screencapture -x -v -V 17 -R "$R" "$WORK/tour.mov"
  pkill -x VidaaInstall 2>/dev/null || true
  ffmpeg -y -loglevel error -i "$WORK/tour.mov" -vf "fps=10,scale=720:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128:stats_mode=full[p];[b][p]paletteuse=dither=bayer:bayer_scale=4" "$OUT/demo.gif"
  echo "  demo.gif ($(du -h "$OUT/demo.gif" | cut -f1))"
fi
