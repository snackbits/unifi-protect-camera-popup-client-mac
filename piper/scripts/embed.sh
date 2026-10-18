#!/bin/bash
# Xcode build phase "Build and embed Piper" (after Resources): builds piper/build/dist if needed
# and copies it into the app – the program to Contents/Helpers/piper, data and the bundled voice
# to Contents/Resources/piper. Every Mach-O is signed here with the build's identity (Xcode's own
# CodeSign step only seals them); resign-app.sh re-signs them with --deep for releases.
# Debug builds then let the embedded Piper speak one sentence (scripts/smoke.sh).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"${ROOT}/scripts/build-piper.sh"
DIST="${ROOT}/build/dist"
CONTENTS="${TARGET_BUILD_DIR:?}/${CONTENTS_FOLDER_PATH:?}"

mkdir -p "${CONTENTS}/Helpers" "${CONTENTS}/Resources"
rsync -a --delete "${DIST}/Helpers/piper/" "${CONTENTS}/Helpers/piper/"
rsync -a --delete "${DIST}/Resources/piper/" "${CONTENTS}/Resources/piper/"

IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:-}"
if [[ -z "${IDENTITY}" ]]; then IDENTITY="-"; fi
codesign --force --sign "${IDENTITY}" "${CONTENTS}/Helpers/piper/lib/"*.dylib
codesign --force --sign "${IDENTITY}" "${CONTENTS}/Helpers/piper/piper"

if [[ "${CONFIGURATION:-}" == "Debug" ]]; then
  "${ROOT}/scripts/smoke.sh" "${CONTENTS}"
fi
