#!/bin/bash
set -euo pipefail

APP_PATH="${1:-}"

if [[ -z "$APP_PATH" ]]; then
  echo "Usage: $0 <path/to/UniFi Camera Popup.app>" >&2
  exit 1
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found: $APP_PATH" >&2
  exit 1
fi

# Prefer a STABLE self-signed identity so macOS keeps privacy grants (Full Disk
# Access for Focus / Do Not Disturb detection) across rebuilds and auto-updates.
# Run scripts/create-signing-identity.sh once to create it. Falls back to ad-hoc
# (which loses Full Disk Access on every update) only if the identity is absent.
SIGNING_IDENTITY="${SIGNING_IDENTITY:-UniFi Camera Popup (Self-Signed)}"

if security find-identity -v 2>/dev/null | grep -qF "$SIGNING_IDENTITY" \
  || security find-certificate -c "$SIGNING_IDENTITY" >/dev/null 2>&1; then
  SIGN_ARG="$SIGNING_IDENTITY"
  echo "Signing with stable identity: ${SIGNING_IDENTITY}"
else
  SIGN_ARG="-"
  echo "WARNING: signing identity '${SIGNING_IDENTITY}' not found – falling back to ad-hoc."
  echo "         Full Disk Access (DND detection) will be revoked on each update."
  echo "         Run scripts/create-signing-identity.sh to fix this permanently."
fi

# Sign without --options runtime: Hardened Runtime breaks VLCKit loading when the
# app is copied outside the build folder (dyld Team ID mismatch).
codesign --force --deep --sign "$SIGN_ARG" "$APP_PATH"
echo "Re-signed: $APP_PATH"
