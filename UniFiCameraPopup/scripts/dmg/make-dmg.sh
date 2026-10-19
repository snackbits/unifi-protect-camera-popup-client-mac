#!/bin/bash
# Builds the installer disk image: a Finder window with the app, an arrow and the „Programme“
# folder to drop it on, plus the first-launch hint (the app is not notarized).
# Usage: make-dmg.sh <path/to/UniFi Camera Popup.app> <out.dmg>
#
# Needs no extra tools (hdiutil, tiffutil, swift, osascript). The window layout is set through
# Finder, so the first run asks once whether Terminal may control Finder – allow it.
set -euo pipefail

APP_PATH="${1:?usage: make-dmg.sh <app> <out.dmg>}"
OUT="${2:?usage: make-dmg.sh <app> <out.dmg>}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VOLUME="UniFi Camera Popup"
APP_NAME="$(basename "$APP_PATH")"
MOUNT="/Volumes/${VOLUME}"

if [[ ! -d "$APP_PATH" ]]; then
  echo "ERROR: app not found: ${APP_PATH}" >&2
  exit 1
fi
if [[ -e "$MOUNT" ]]; then
  echo "ERROR: ${MOUNT} is already mounted – eject it (Finder) and run again." >&2
  exit 1
fi

WORK="$(mktemp -d)"
DEVICE=""
cleanup() {
  if [[ -n "$DEVICE" ]]; then hdiutil detach "$DEVICE" -force >/dev/null 2>&1 || true; fi
  rm -rf "$WORK"
}
trap cleanup EXIT

STAGE="${WORK}/stage"
mkdir -p "${STAGE}/.background"
ditto "$APP_PATH" "${STAGE}/${APP_NAME}"
ln -s /Applications "${STAGE}/Programme"
# No FSEvents log on the image (keeps .fseventsd empty).
mkdir -p "${STAGE}/.fseventsd" && touch "${STAGE}/.fseventsd/no_log"
swift "${SCRIPT_DIR}/make-background.swift" "${WORK}/background.png" 1
swift "${SCRIPT_DIR}/make-background.swift" "${WORK}/background@2x.png" 2
tiffutil -cathidpicheck "${WORK}/background.png" "${WORK}/background@2x.png" \
  -out "${STAGE}/.background/background.tiff" >/dev/null 2>&1

# Writable image with room for Finder's .DS_Store, compressed at the end.
SIZE_MB=$(( $(du -sm "$STAGE" | awk '{print $1}') + 30 ))
hdiutil create -quiet -srcfolder "$STAGE" -volname "$VOLUME" -fs HFS+ -format UDRW \
  -size "${SIZE_MB}m" "${WORK}/rw.dmg"
DEVICE="$(hdiutil attach -readwrite -noverify -noautoopen "${WORK}/rw.dmg" \
  | awk '/Apple_HFS/ {print $1; exit}')"
if [[ -z "$DEVICE" || ! -d "$MOUNT" ]]; then
  echo "ERROR: could not mount the image at ${MOUNT}." >&2
  exit 1
fi

# Content 600 × 400 (matches make-background.swift; 28 pt title bar), icons centred at (160, 165)
# and (440, 165). Hidden folders go below the visible area for people who show hidden files.
osascript <<OSA
tell application "Finder"
  tell disk "${VOLUME}"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set pathbar visible of container window to false
    set the bounds of container window to {200, 120, 800, 548}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 112
    set text size of viewOptions to 13
    set background picture of viewOptions to file ".background:background.tiff"
    set position of item "${APP_NAME}" of container window to {160, 165}
    set position of item "Programme" of container window to {440, 165}
    try
      set position of item ".background" of container window to {160, 560}
      set position of item ".fseventsd" of container window to {440, 560}
    end try
    close
    open
    update without registering applications
    delay 2
    close
  end tell
end tell
OSA

if [[ ! -f "${MOUNT}/.DS_Store" ]]; then
  echo "ERROR: Finder did not save the window layout (.DS_Store missing) – was Finder control allowed?" >&2
  exit 1
fi
chmod -Rf go-w "$MOUNT" || true
sync
hdiutil detach "$DEVICE" -quiet || { sleep 2; hdiutil detach "$DEVICE" -force -quiet; }
DEVICE=""

rm -f "$OUT"
hdiutil convert -quiet "${WORK}/rw.dmg" -format ULFO -o "$OUT"
hdiutil verify -quiet "$OUT"
echo "DMG: ${OUT} ($(du -h "$OUT" | awk '{print $1}'))"
