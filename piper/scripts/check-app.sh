#!/bin/bash
# Checks the Piper inside a built app (called by build-release.sh, runnable on any build):
# program and libraries universal (arm64 + x86_64), data and bundled voice present, signature valid.
#   piper/scripts/check-app.sh "<path>/UniFi Camera Popup.app"
set -euo pipefail

APP_PATH="${1:?usage: check-app.sh <App.app>}"
PIPER_DIR="${APP_PATH}/Contents/Helpers/piper"
RES="${APP_PATH}/Contents/Resources/piper"

for file in "${PIPER_DIR}/piper" "${PIPER_DIR}/lib/libespeak-ng.1.dylib" \
            "${PIPER_DIR}/lib/libpiper_phonemize.1.dylib" "${PIPER_DIR}/lib/libonnxruntime.1.14.1.dylib"; do
  if [[ ! -f "${file}" ]]; then
    echo "ERROR: ${file} missing from the app bundle." >&2
    exit 1
  fi
  archs="$(lipo -archs "${file}")"
  for arch in arm64 x86_64; do
    if [[ " ${archs} " != *" ${arch} "* ]]; then
      echo "ERROR: ${file} lacks ${arch} (has: ${archs})." >&2
      exit 1
    fi
  done
done
for file in voices/de_DE-thorsten-medium.onnx voices/de_DE-thorsten-medium.onnx.json espeak-ng-data/phondata \
            espeak-ng-data/de_dict espeak-ng-data/en_dict ThirdPartyNotices-onnxruntime.txt \
            build-scripts/fetch.sh build-scripts/build-piper.sh; do
  if [[ ! -s "${RES}/${file}" ]]; then
    echo "ERROR: Contents/Resources/piper/${file} missing from the app bundle." >&2
    exit 1
  fi
done
codesign --verify --deep --strict "${APP_PATH}"
echo "check-app: Piper ok in ${APP_PATH}"
