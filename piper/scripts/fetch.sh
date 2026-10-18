#!/bin/bash
# Downloads every pinned input of the Piper build into piper/.cache (gitignored) and checks
# its SHA-256: CMake (build tool), the sources of piper, piper-phonemize, espeak-ng, fmt and
# spdlog, the onnxruntime release and the bundled voice Thorsten (medium). Idempotent: a file
# with the right checksum is not downloaded again. Prints the cache directory.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CACHE="${ROOT}/.cache"
mkdir -p "${CACHE}"

VOICES_REV="c10ece1aade47bb51c153c893d14e5bf8e5b7117"
HF="https://huggingface.co/rhasspy/piper-voices/resolve/${VOICES_REV}"

# name | sha256 | url
PINNED="
cmake-3.31.8-macos-universal.tar.gz|d1449f969c54d5c00886d5b643340d493dfb3c81cb39ee29b35453395c11ebf7|https://github.com/Kitware/CMake/releases/download/v3.31.8/cmake-3.31.8-macos-universal.tar.gz
piper-2023.11.14-2.tar.gz|8b684e102cfe23af097830db9555a8641f17735725853c531a1daeb34b6ed1a8|https://github.com/rhasspy/piper/archive/refs/tags/2023.11.14-2.tar.gz
piper-phonemize-bfc2e75.tar.gz|cb72dd5564b292e043129d1c34b74f064dcc9ff0f713aebb3c6e44c5607de724|https://github.com/rhasspy/piper-phonemize/archive/bfc2e7549957829b0227c66a305d11cc88167bda.tar.gz
espeak-ng-0f65aa3.tar.gz|37ebbabb010200be8ec26c61b770e93f964f4503a329d7d74c239a1a40051e43|https://github.com/rhasspy/espeak-ng/archive/0f65aa301e0d6bae5e172cc74197d32a6182200f.tar.gz
fmt-10.0.0.tar.gz|ede1b6b42188163a3f2e0f25ad5c0637eca564bd8df74d02e31a311dd6b37ad8|https://github.com/fmtlib/fmt/archive/refs/tags/10.0.0.tar.gz
spdlog-1.12.0.tar.gz|4dccf2d10f410c1e2feaff89966bfc49a1abb29ef6f08246335b110e001e09a9|https://github.com/gabime/spdlog/archive/refs/tags/v1.12.0.tar.gz
onnxruntime-osx-universal2-1.14.1.tgz|bcbaa573172caa74f8273598d70733572a1b15279e63c7a18031cc8cc97cf134|https://github.com/microsoft/onnxruntime/releases/download/v1.14.1/onnxruntime-osx-universal2-1.14.1.tgz
de_DE-thorsten-medium.onnx|7e64762d8e5118bb578f2eea6207e1a35a8e0c30595010b666f983fc87bb7819|${HF}/de/de_DE/thorsten/medium/de_DE-thorsten-medium.onnx
de_DE-thorsten-medium.onnx.json|974adee790533adb273a1ac88f49027d2a1b8f0f2cf4905954a4791e79264e85|${HF}/de/de_DE/thorsten/medium/de_DE-thorsten-medium.onnx.json
"

while IFS='|' read -r name sha url; do
  [[ -z "${name}" ]] && continue
  target="${CACHE}/${name}"
  if [[ -f "${target}" ]] && echo "${sha}  ${target}" | shasum -a 256 -c - >/dev/null 2>&1; then
    continue
  fi
  echo "fetch: lade ${url}" >&2
  curl -fsSL --retry 3 -o "${target}.part" "${url}"
  if ! echo "${sha}  ${target}.part" | shasum -a 256 -c - >/dev/null 2>&1; then
    rm -f "${target}.part"
    echo "fetch: Prüfsumme falsch: ${name}" >&2
    exit 1
  fi
  mv "${target}.part" "${target}"
done <<< "${PINNED}"

echo "${CACHE}"
