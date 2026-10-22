#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/.."

# ---------------------------------------------------------------------------
# Configuration (override via environment)
# ---------------------------------------------------------------------------
# Fixed public URL for the app update archive (snackbits.dev, uploaded by deploy-release.sh).
DOWNLOAD_URL="${DOWNLOAD_URL:-https://snackbits.dev/apps/unifi-camera-popup/app.zip}"

PRIVATE_KEY_FILE="${SCRIPT_DIR}/update_private_key.txt"
SERVER_PUBLIC_DIR="../../server/public"
SERVER_VERSION_FILE="../../server/version.json"

# GPL source offer (Piper/espeak-ng/onnxruntime): the pinned source archives are mirrored next to
# app.zip. Check they exist before anything is bumped or packaged, so a failure leaves no half release.
# Named explicitly (as in collect-notices.sh), so an aborted *.part download is never mirrored.
# The source mirror is not in the server's git (onnxruntime's source alone is 190 MB, over GitHub's
# 100 MB limit; public/piper-source/ is git-ignored there) – it is deployed with rsync (see the end).
PIPER_ROOT="${SCRIPT_DIR}/../../piper"
PIPER_ARCHIVES=()
for name in piper-2023.11.14-2.tar.gz piper-phonemize-bfc2e75.tar.gz espeak-ng-0f65aa3.tar.gz \
            fmt-10.0.0.tar.gz spdlog-1.12.0.tar.gz onnxruntime-osx-universal2-1.14.1.tgz \
            onnxruntime-1.14.1-src.tar.gz; do
  PIPER_ARCHIVES+=("${PIPER_ROOT}/.cache/${name}")
done
# smoke.sh (after re-signing) speaks with the cached Thorsten (medium) – no voice is in the app.
for archive in "${PIPER_ARCHIVES[@]}" "${PIPER_ROOT}/.cache/de_DE-thorsten-medium.onnx" \
               "${PIPER_ROOT}/.cache/de_DE-thorsten-medium.onnx.json"; do
  if [[ ! -f "$archive" ]]; then
    echo "ERROR: Piper source archive ${archive} missing – run piper/scripts/build-piper.sh first." >&2
    exit 1
  fi
done

# ---------------------------------------------------------------------------
# Bump version identifiers and bake them into the app + server manifest.
# ---------------------------------------------------------------------------
NEW_VERSION_ID="$(uuidgen | tr '[:upper:]' '[:lower:]')"
echo "Build version id: ${NEW_VERSION_ID}"

CURRENT_BUILD_NUMBER="$(sed -nE 's/.*static let buildNumber = ([0-9]+).*/\1/p' AppConfig.swift)"
CURRENT_VERSION_ID="$(sed -nE 's/.*static let buildVersionId = "([^"]*)".*/\1/p' AppConfig.swift)"
NEW_BUILD_NUMBER=$((CURRENT_BUILD_NUMBER + 1))
echo "Build number: ${NEW_BUILD_NUMBER}"

# Until version.json is written, any failure (build, checks, app.zip too large) puts the two
# AppConfig.swift values back, so no half release is left behind.
revert_bump() {
  sed -i '' -E \
    -e "s/(static let buildNumber = )[0-9]+/\1${CURRENT_BUILD_NUMBER}/" \
    -e "s/(static let buildVersionId = \")[^\"]*(\")/\1${CURRENT_VERSION_ID}\2/" \
    AppConfig.swift \
  && echo "Reverted AppConfig.swift to buildNumber ${CURRENT_BUILD_NUMBER} / buildVersionId ${CURRENT_VERSION_ID}." >&2 \
  || echo "ERROR: could not revert AppConfig.swift – set buildNumber back to ${CURRENT_BUILD_NUMBER} and buildVersionId back to \"${CURRENT_VERSION_ID}\" by hand." >&2
}
trap 'revert_bump' EXIT

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
# espeak-ng data, license marks, valid signature (voices are downloaded at first use).
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
# Package: zip the .app → server/public/app.zip (update archive) and the installer disk image
# → server/public/UniFi-Camera-Popup.dmg (first download). Both names stay the same per release,
# so a deploy simply overwrites them (scripts/deploy-release.sh).
# ---------------------------------------------------------------------------
mkdir -p "$SERVER_PUBLIC_DIR"
ZIP_PATH="${SERVER_PUBLIC_DIR}/app.zip"
DMG_PATH="${SERVER_PUBLIC_DIR}/UniFi-Camera-Popup.dmg"
# Packed next to the old files first: a failed or oversized package never replaces them.
ZIP_NEW="${ZIP_PATH}.new"
DMG_NEW="${SERVER_PUBLIC_DIR}/UniFi-Camera-Popup.new.dmg"
rm -f "$ZIP_NEW" "$DMG_NEW"
# --keepParent keeps the .app wrapper as the top-level entry in the archive.
ditto -c -k --keepParent "$APP_PATH" "$ZIP_NEW"
# Sanity limit: the app is about 55 MB; far more means something got bundled by mistake.
ZIP_LIMIT=95000000
ZIP_SIZE="$(stat -f %z "$ZIP_NEW")"
if (( ZIP_SIZE > ZIP_LIMIT )); then
  rm -f "$ZIP_NEW"
  echo "ERROR: app.zip would be ${ZIP_SIZE} bytes (> 95 MB)." >&2
  echo "       Nothing was packaged or written (no app.zip, no version.json). Is a Piper voice bundled again? (piper/scripts/check-app.sh)" >&2
  exit 1
fi
if ! "${SCRIPT_DIR}/dmg/make-dmg.sh" "$APP_PATH" "$DMG_NEW"; then
  rm -f "$ZIP_NEW" "$DMG_NEW"
  echo "ERROR: building the DMG failed – nothing was replaced (no app.zip, no DMG, no version.json)." >&2
  exit 1
fi
mv -f "$ZIP_NEW" "$ZIP_PATH"
mv -f "$DMG_NEW" "$DMG_PATH"
echo "Packaged: ${ZIP_PATH} (${ZIP_SIZE} bytes)"
echo "Packaged: ${DMG_PATH} ($(stat -f %z "$DMG_PATH") bytes)"

# GPL source offer: mirror the pinned Piper/espeak-ng/onnxruntime source archives and the build
# scripts next to app.zip (served from the update server; git-ignored there, deployed by rsync).
PIPER_SRC_DIR="${SERVER_PUBLIC_DIR}/piper-source/2023.11.14-2"
rm -rf "$PIPER_SRC_DIR"
mkdir -p "$PIPER_SRC_DIR"
cp "${PIPER_ARCHIVES[@]}" "$PIPER_SRC_DIR/"
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

# The update question in the app lists the „Was ist neu“ items of this version.
NOTES_JSON="$(python3 -I "${SCRIPT_DIR}/changelog-notes.py" Services/WhatsNewService.swift "$SHORT_VERSION")"

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
  "notes": ${NOTES_JSON}
}
EOF
echo "Wrote ${SERVER_VERSION_FILE}"
# Released: the bumped AppConfig.swift stays.
trap - EXIT

echo ""
echo "Release build ready:"
echo "  $(pwd)/$APP_PATH"
echo "  $(pwd)/$ZIP_PATH"
echo "  $(pwd)/$DMG_PATH"
echo ""
echo "Deploy (uploads version.json, app.zip, the DMG and the Piper source mirror, then checks the live files):"
echo "  scripts/deploy-release.sh            # --dry-run shows the steps only"
