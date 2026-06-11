#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

# Generate a fresh build version id and bake it into both the app and the
# server. The server rejects apps whose id does not match, so old app builds
# can no longer connect after a new release.
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

SERVER_VERSION_FILE="../../server/version.json"
printf '{\n  "versionId": "%s"\n}\n' "${NEW_VERSION_ID}" > "${SERVER_VERSION_FILE}"
echo "Wrote ${SERVER_VERSION_FILE}"

xcodebuild \
  -project UniFiCameraPopup.xcodeproj \
  -scheme UniFiCameraPopup \
  -configuration Release \
  -derivedDataPath .build \
  build

APP_PATH=".build/Build/Products/Release/UniFiCameraPopup.app"
"$(dirname "$0")/resign-app.sh" "$APP_PATH"

echo ""
echo "Release build ready:"
echo "  $(pwd)/$APP_PATH"
