#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

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
