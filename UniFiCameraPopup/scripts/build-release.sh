#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ---------------------------------------------------------------------------
# Configuration (override via environment)
# ---------------------------------------------------------------------------
# Fixed public URL for the app update archive (served by nginx from server/public/).
DOWNLOAD_URL="${DOWNLOAD_URL:-https://unifi-protect-camera-popup-server.snackbits.dev/app.zip}"

PRIVATE_KEY_FILE="${SCRIPT_DIR}/update_private_key.txt"
SERVER_PUBLIC_DIR="../../server/public"
SERVER_VERSION_FILE="../../server/version.json"

# ---------------------------------------------------------------------------
# Bump version identifiers and bake them into the app + server manifest.
# ---------------------------------------------------------------------------
NEW_VERSION_ID="$(uuidgen | tr '[:upper:]' '[:lower:]')"
echo "Build version id: ${NEW_VERSION_ID}"

CURRENT_BUILD_NUMBER="$(sed -nE 's/.*static let buildNumber = ([0-9]+).*/\1/p' AppConfig.swift)"
NEW_BUILD_NUMBER=$((CURRENT_BUILD_NUMBER + 1))
echo "Build number: ${NEW_BUILD_NUMBER}"

sed -i '' -E \
  "s/(static let buildNumber = )[0-9]+/\1${NEW_BUILD_NUMBER}/" \
  AppConfig.swift

sed -i '' -E \
  "s/(static let buildVersionId = \")[^\"]*(\")/\1${NEW_VERSION_ID}\2/" \
  AppConfig.swift

# ---------------------------------------------------------------------------
# Build + re-sign (ad-hoc) the app.
# ---------------------------------------------------------------------------
xcodebuild \
  -project UniFiCameraPopup.xcodeproj \
  -scheme UniFiCameraPopup \
  -configuration Release \
  -derivedDataPath .build \
  build

APP_PATH=".build/Build/Products/Release/UniFi Camera Popup.app"
"${SCRIPT_DIR}/resign-app.sh" "$APP_PATH"

SHORT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP_PATH}/Contents/Info.plist" 2>/dev/null || echo "1.0.0")"

# ---------------------------------------------------------------------------
# Package: zip the .app → server/public/app.zip (fixed name for nginx + git pull).
# ---------------------------------------------------------------------------
mkdir -p "$SERVER_PUBLIC_DIR"
ZIP_PATH="${SERVER_PUBLIC_DIR}/app.zip"
rm -f "$ZIP_PATH"
# --keepParent keeps the .app wrapper as the top-level entry in the archive.
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
echo "Packaged: ${ZIP_PATH}"

SHA256="$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')"

# ---------------------------------------------------------------------------
# Sign the archive with the Ed25519 update key (authenticity).
# ---------------------------------------------------------------------------
SIGNATURE=""
if [[ -f "$PRIVATE_KEY_FILE" ]]; then
  SIGNATURE="$(swift "${SCRIPT_DIR}/sign-update.swift" "$ZIP_PATH" "$PRIVATE_KEY_FILE")"
  echo "Signed archive (Ed25519)."
else
  echo "WARNING: ${PRIVATE_KEY_FILE} not found – release will NOT be signed."
  echo "         Auto-update will refuse it. Run scripts/update-keygen.swift first."
fi

# ---------------------------------------------------------------------------
# Write the version manifest (consumed by the server at GET /version).
# ---------------------------------------------------------------------------
cat > "$SERVER_VERSION_FILE" <<EOF
{
  "versionId": "${NEW_VERSION_ID}",
  "buildNumber": ${NEW_BUILD_NUMBER},
  "shortVersion": "${SHORT_VERSION}",
  "url": "${DOWNLOAD_URL}",
  "sha256": "${SHA256}",
  "signature": "${SIGNATURE}",
  "notes": ""
}
EOF
echo "Wrote ${SERVER_VERSION_FILE}"

echo ""
echo "Release build ready:"
echo "  $(pwd)/$APP_PATH"
echo "  $(pwd)/$ZIP_PATH"
echo ""
echo "Deploy (git workflow):"
echo "  git add app/UniFiCameraPopup/AppConfig.swift server/version.json server/public/app.zip"
echo "  git commit -m \"Release build ${NEW_BUILD_NUMBER}\""
echo "  git push"
echo "  # on server: git pull   (nginx serves app.zip immediately, Node reads version.json)"
