#!/bin/bash
set -euo pipefail

APP_PATH="${1:-}"

if [[ -z "$APP_PATH" ]]; then
  echo "Usage: $0 <path/to/UniFiCameraPopup.app>" >&2
  exit 1
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found: $APP_PATH" >&2
  exit 1
fi

# Sign without --options runtime: Hardened Runtime + ad-hoc signing breaks VLCKit loading
# when the app is copied outside the build folder (dyld Team ID mismatch).
codesign --force --deep --sign - "$APP_PATH"
echo "Re-signed: $APP_PATH"
