#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/.."

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
# Ensure the stable self-signed identity exists so privacy grants (Full Disk
# Access for DND detection) survive this update. Idempotent.
# ---------------------------------------------------------------------------
"${SCRIPT_DIR}/create-signing-identity.sh"

# ---------------------------------------------------------------------------
# Build + re-sign the app with the stable identity.
# ---------------------------------------------------------------------------
# generic/platform=macOS builds every architecture in ARCHS (arm64 + x86_64);
# without it xcodebuild only builds for this Mac. The build phase
# "Build WireGuard tunnel" produces the universal libwgtunnel.a first.
xcodebuild \
  -project UniFiCameraPopup.xcodeproj \
  -scheme UniFiCameraPopup \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath .build \
  build

APP_PATH=".build/Build/Products/Release/UniFi Camera Popup.app"

# The release must run on Apple silicon and Intel Macs.
BINARY_ARCHS="$(lipo -archs "${APP_PATH}/Contents/MacOS/UniFi Camera Popup")"
for arch in arm64 x86_64; do
  if [[ " ${BINARY_ARCHS} " != *" ${arch} "* ]]; then
    echo "ERROR: App binary lacks ${arch} (has: ${BINARY_ARCHS})." >&2
    exit 1
  fi
done
if [[ ! -s "${APP_PATH}/Contents/Resources/ThirdPartyNotices.txt" ]]; then
  echo "ERROR: ThirdPartyNotices.txt missing from the app bundle." >&2
  exit 1
fi
# Piper (Phase 6, build phase "Build and embed Piper"): universal program and libraries,
# espeak-ng data, the bundled voice, license marks, valid signature.
"${SCRIPT_DIR}/../../piper/scripts/check-app.sh" "$APP_PATH"

"${SCRIPT_DIR}/resign-app.sh" "$APP_PATH"
# The re-signed bundle (nested Piper included) must still verify – and Piper must still speak.
codesign --verify --deep --strict "$APP_PATH"
"${SCRIPT_DIR}/../../piper/scripts/smoke.sh" "${APP_PATH}/Contents"

SHORT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP_PATH}/Contents/Info.plist" 2>/dev/null || echo "1.0.0")"
echo "App version: ${SHORT_VERSION}"

# The "Was ist neu" popup only appears when the changelog has an entry for
# this version (raise MARKETING_VERSION in the Xcode project per release).
if ! grep -q "version: \"${SHORT_VERSION}\"" Services/WhatsNewService.swift; then
  echo ""
  echo "WARNING: No changelog entry for version ${SHORT_VERSION} in Services/WhatsNewService.swift."
  echo "         Users will not see a \"Was ist neu\" popup after this update."
  echo "         Raise MARKETING_VERSION and add a ChangelogEntry for new features."
  echo ""
fi

# ---------------------------------------------------------------------------
# Package: zip the .app → server/public/app.zip (fixed name for nginx + git pull).
# ---------------------------------------------------------------------------
mkdir -p "$SERVER_PUBLIC_DIR"
ZIP_PATH="${SERVER_PUBLIC_DIR}/app.zip"
rm -f "$ZIP_PATH"
# --keepParent keeps the .app wrapper as the top-level entry in the archive.
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
echo "Packaged: ${ZIP_PATH}"

# GPL source offer: mirror the pinned Piper/espeak-ng/onnxruntime source archives and the build
# scripts next to app.zip (served from the update server).
PIPER_SRC_DIR="${SERVER_PUBLIC_DIR}/piper-source/2023.11.14-2"
PIPER_ROOT="${SCRIPT_DIR}/../../piper"
rm -rf "$PIPER_SRC_DIR"
mkdir -p "$PIPER_SRC_DIR"
for archive in "${PIPER_ROOT}/.cache/"piper-* "${PIPER_ROOT}/.cache/"espeak-ng-* "${PIPER_ROOT}/.cache/"fmt-* \
               "${PIPER_ROOT}/.cache/"spdlog-* "${PIPER_ROOT}/.cache/"onnxruntime-*; do
  if [[ ! -f "$archive" ]]; then
    echo "ERROR: Piper source archive ${archive} missing – run piper/scripts/build-piper.sh first." >&2
    exit 1
  fi
  cp "$archive" "$PIPER_SRC_DIR/"
done
rsync -a "${PIPER_ROOT}/scripts/" "${PIPER_SRC_DIR}/scripts/"
echo "Mirrored Piper sources: ${PIPER_SRC_DIR}"

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
