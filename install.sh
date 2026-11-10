#!/bin/bash
# Installe (ou met à jour) VidaaInstall depuis la dernière release GitHub.
#
#   curl -fsSL https://raw.githubusercontent.com/Ampiso4/VidaaInstall/main/install.sh | bash
#
# Un fichier téléchargé par curl n'est pas marqué « quarantaine » par macOS :
# l'app s'ouvre directement, sans passer par Réglages → Confidentialité et sécurité.
set -euo pipefail

REPO="Ampiso4/VidaaInstall"
URL="https://github.com/$REPO/releases/latest/download/VidaaInstall.dmg"
APP="VidaaInstall.app"

say() { printf '\033[1;34m›\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || die "VidaaInstall ne fonctionne que sur macOS."
MAJOR=$(sw_vers -productVersion | cut -d. -f1)
[ "$MAJOR" -ge 14 ] || die "macOS 14 (Sonoma) ou plus récent est requis (version actuelle : $(sw_vers -productVersion))."

DEST="/Applications"
[ -w "$DEST" ] || DEST="$HOME/Applications"
mkdir -p "$DEST"

TMP=$(mktemp -d)
MNT="$TMP/mnt"
cleanup() { hdiutil detach "$MNT" -quiet 2>/dev/null || true; rm -rf "$TMP"; }
trap cleanup EXIT

say "Téléchargement de la dernière version…"
curl -fL --progress-bar "$URL" -o "$TMP/VidaaInstall.dmg" || die "Téléchargement impossible : $URL"

say "Ouverture du disque…"
mkdir -p "$MNT"
hdiutil attach -nobrowse -readonly -quiet -mountpoint "$MNT" "$TMP/VidaaInstall.dmg" || die "Le disque n'a pas pu être monté."
[ -d "$MNT/$APP" ] || die "$APP introuvable dans le disque."

if pgrep -x VidaaInstall >/dev/null; then
  say "Fermeture de la version en cours…"
  pkill -x VidaaInstall || true
  sleep 1
fi

say "Copie dans ${DEST}…"
rm -rf "${DEST:?}/$APP"
ditto "$MNT/$APP" "$DEST/$APP"
xattr -dr com.apple.quarantine "$DEST/$APP" 2>/dev/null || true

say "Lancement 🚀"
open "$DEST/$APP"
printf '\n\033[1;32m✓ VidaaInstall est installé dans %s\033[0m\n' "$DEST"
printf '  Au premier lancement, autorise l'"'"'accès au réseau local, puis Téléviseurs → Rechercher → Appairer.\n'
