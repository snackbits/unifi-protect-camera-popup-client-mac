#!/bin/bash
# Checks the Piper inside a built app (called by build-release.sh, runnable on any build):
# program executable and universal (arm64 + x86_64), libraries universal, data present, no voice
# bundled (every voice is downloaded on first use – keeps app.zip under GitHub's 100 MB), signature valid.
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
  if [[ "${file}" == "${PIPER_DIR}/piper" && ! -x "${file}" ]]; then
    echo "ERROR: ${file} is not executable." >&2
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
for file in espeak-ng-data/phondata \
            espeak-ng-data/de_dict espeak-ng-data/en_dict ThirdPartyNotices-onnxruntime.txt \
            build-scripts/fetch.sh build-scripts/build-piper.sh; do
  if [[ ! -s "${RES}/${file}" ]]; then
    echo "ERROR: Contents/Resources/piper/${file} missing from the app bundle." >&2
    exit 1
  fi
done
if [[ -e "${RES}/voices" ]] || find "${APP_PATH}/Contents" -name '*.onnx' | grep -q .; then
  echo "ERROR: a Piper voice is bundled (Contents/Resources/piper/voices or *.onnx) – voices are downloaded on first use." >&2
  exit 1
fi
NOTICES="${APP_PATH}/Contents/Resources/ThirdPartyNotices.txt"
for marker in "Sprachausgabe (Piper)" "--- espeak-ng" "GPL-3.0-or-later" "--- onnxruntime" "Thorsten-Voice" "M-AILABS" "dataset-voice-kerstin"; do
  if ! grep -qF -- "${marker}" "${NOTICES}"; then
    echo "ERROR: ThirdPartyNotices.txt lacks \"${marker}\" – run piper/scripts/collect-notices.sh, then wgtunnel/scripts/collect-notices.sh." >&2
    exit 1
  fi
done
codesign --verify --deep --strict "${APP_PATH}"
echo "check-app: Piper ok in ${APP_PATH}"
