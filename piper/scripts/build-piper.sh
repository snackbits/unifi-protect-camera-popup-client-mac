#!/bin/bash
# Builds Piper 2023.11.14-2 as a universal (arm64 + x86_64) program for macOS 13.0 from the
# pinned sources (scripts/fetch.sh) and assembles piper/build/dist:
#   Helpers/piper/piper, Helpers/piper/lib/*.dylib           (program, found via @executable_path/lib)
#   Resources/piper/espeak-ng-data/…                          (German + English only)
#   Resources/piper/ThirdPartyNotices-onnxruntime.txt, Resources/piper/build-scripts/…
# No voice is bundled: every voice (Thorsten medium, the default, included) is downloaded by the
# app on first use. The build needs no network once piper/.cache is filled (no sub-build fetches).
# The official macOS release tarballs of 2023.11.14-2 cannot be used: both are x86_64 only and
# lack the three dylibs. Skips the build when dist/STAMP matches the build scripts.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CACHE="$("${ROOT}/scripts/fetch.sh")"
OUT="${ROOT}/build"
DIST="${OUT}/dist"
STAMP_VALUE="$(cat "${ROOT}/scripts/fetch.sh" "${ROOT}/scripts/build-piper.sh" | shasum -a 256 | awk '{print $1}')"

if [[ -f "${DIST}/STAMP" && "$(cat "${DIST}/STAMP")" == "${STAMP_VALUE}" \
      && -x "${DIST}/Helpers/piper/piper" ]]; then
  echo "build-piper: ${DIST} ist aktuell"
  exit 0
fi

WORK="${OUT}/work"
rm -rf "${WORK}" "${DIST}"
mkdir -p "${WORK}/src"
for archive in cmake-3.31.8-macos-universal.tar.gz piper-2023.11.14-2.tar.gz piper-phonemize-bfc2e75.tar.gz \
               espeak-ng-0f65aa3.tar.gz fmt-10.0.0.tar.gz spdlog-1.12.0.tar.gz onnxruntime-osx-universal2-1.14.1.tgz; do
  tar -xzf "${CACHE}/${archive}" -C "${WORK}/src"
done
SRC="${WORK}/src"
CMAKE="${SRC}/cmake-3.31.8-macos-universal/CMake.app/Contents/bin/cmake"
ORT="${SRC}/onnxruntime-osx-universal2-1.14.1"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
JOBS="$(sysctl -n hw.ncpu)"

# Xcode build phases export SDKROOT, ARCHS, CC … – CMake must see none of it.
CLEAN_ENV=(PATH="/usr/bin:/bin:/usr/sbin:/sbin" HOME="${HOME}")
if [[ -n "${DEVELOPER_DIR:-}" ]]; then CLEAN_ENV+=(DEVELOPER_DIR="${DEVELOPER_DIR}"); fi
run() {
  env -i "${CLEAN_ENV[@]}" "$@"
}
# FETCHCONTENT_FULLY_DISCONNECTED: a FetchContent left in any sub-build fails instead of downloading.
configure() {
  local source="$1" build="$2"; shift 2
  run "${CMAKE}" -S "${source}" -B "${build}" -DCMAKE_BUILD_TYPE=Release \
    "-DCMAKE_OSX_ARCHITECTURES=arm64;x86_64" -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 \
    -DCMAKE_OSX_SYSROOT="${SDK}" -DFETCHCONTENT_FULLY_DISCONNECTED=ON "$@" > "${build}.log" 2>&1
}
build() {
  local build="$1"; shift
  run "${CMAKE}" --build "${build}" -j "${JOBS}" "$@" >> "${build}.log" 2>&1
  run "${CMAKE}" --install "${build}" >> "${build}.log" 2>&1
}

echo "build-piper: fmt, spdlog"
configure "${SRC}/fmt-10.0.0" "${WORK}/b-fmt" -DFMT_TEST=OFF -DCMAKE_INSTALL_PREFIX="${WORK}/fi"
build "${WORK}/b-fmt"
configure "${SRC}/spdlog-1.12.0" "${WORK}/b-spdlog" -DSPDLOG_BUILD_EXAMPLE=OFF -DCMAKE_INSTALL_PREFIX="${WORK}/si"
build "${WORK}/b-spdlog"

echo "build-piper: espeak-ng"
ESPEAK_SRC="${SRC}/espeak-ng-0f65aa301e0d6bae5e172cc74197d32a6182200f"
# cmake/deps.cmake git-clones sonic from GitHub whenever no system libsonic is found – even with
# USE_LIBSONIC=OFF, and sonic is never linked then. Drop that FetchContent block (the else branch
# stays empty) so the build only uses the pinned, checksummed archives.
sed -i '' '/FetchContent_Declare(sonic-git/,/set(SONIC_INC/d' "${ESPEAK_SRC}/cmake/deps.cmake"
if grep -q "FetchContent_Declare\|FetchContent_MakeAvailable" "${ESPEAK_SRC}/cmake/deps.cmake"; then
  echo "build-piper: espeak-ng cmake/deps.cmake lädt noch etwas aus dem Netz" >&2
  exit 1
fi
configure "${ESPEAK_SRC}" "${WORK}/b-espeak" \
  -DCMAKE_INSTALL_PREFIX="${WORK}/ei" -DUSE_ASYNC=OFF -DBUILD_SHARED_LIBS=ON -DUSE_MBROLA=OFF \
  -DUSE_LIBSONIC=OFF -DUSE_LIBPCAUDIO=OFF -DUSE_KLATT=OFF -DUSE_SPEECHPLAYER=OFF \
  -DEXTRA_cmn=ON -DEXTRA_ru=ON -DCMAKE_C_FLAGS=-D_FILE_OFFSET_BITS=64
build "${WORK}/b-espeak"

echo "build-piper: piper-phonemize"
configure "${SRC}/piper-phonemize-bfc2e7549957829b0227c66a305d11cc88167bda" "${WORK}/b-phonemize" \
  -DCMAKE_INSTALL_PREFIX="${WORK}/pi" -DONNXRUNTIME_DIR="${ORT}" -DESPEAK_NG_DIR="${WORK}/ei"
build "${WORK}/b-phonemize"

echo "build-piper: piper"
configure "${SRC}/piper-2023.11.14-2" "${WORK}/b-piper" -DCMAKE_INSTALL_PREFIX="${WORK}/out" \
  -DFMT_DIR="${WORK}/fi" -DSPDLOG_DIR="${WORK}/si" -DPIPER_PHONEMIZE_DIR="${WORK}/pi"
run "${CMAKE}" --build "${WORK}/b-piper" --target piper -j "${JOBS}" >> "${WORK}/b-piper.log" 2>&1

HELPERS="${DIST}/Helpers/piper"
RESOURCES="${DIST}/Resources/piper"
mkdir -p "${HELPERS}/lib" "${RESOURCES}/espeak-ng-data/lang/gmw" "${RESOURCES}/build-scripts"
cp "${WORK}/b-piper/piper" "${HELPERS}/piper"
cp -L "${WORK}/ei/lib/libespeak-ng.1.dylib" "${WORK}/pi/lib/libpiper_phonemize.1.dylib" \
      "${ORT}/lib/libonnxruntime.1.14.1.dylib" "${HELPERS}/lib/"
chmod 755 "${HELPERS}/piper"
chmod 644 "${HELPERS}/lib/"*.dylib

# Build-machine rpaths out, the bundle's own in.
strip_rpaths() {
  local file="$1" path
  for path in $(otool -l "${file}" | awk '/cmd LC_RPATH/ {getline; getline; print $2}' | sort -u); do
    install_name_tool -delete_rpath "${path}" "${file}" 2>/dev/null
  done
}
strip_rpaths "${HELPERS}/piper"
install_name_tool -add_rpath @executable_path/lib "${HELPERS}/piper" 2>/dev/null
for lib in "${HELPERS}/lib/"*.dylib; do
  strip_rpaths "${lib}"
done

# German voices only; English for words eSpeak marks as English ("Computer", "okay").
DATA="${WORK}/ei/share/espeak-ng-data"
cp "${DATA}/phontab" "${DATA}/phonindex" "${DATA}/phondata" "${DATA}/intonations" \
   "${DATA}/de_dict" "${DATA}/en_dict" "${RESOURCES}/espeak-ng-data/"
cp "${DATA}/lang/gmw/de" "${DATA}/lang/gmw/en" "${RESOURCES}/espeak-ng-data/lang/gmw/"

cp "${ORT}/ThirdPartyNotices.txt" "${RESOURCES}/ThirdPartyNotices-onnxruntime.txt"
cp "${ROOT}/scripts/fetch.sh" "${ROOT}/scripts/build-piper.sh" "${RESOURCES}/build-scripts/"

# Ad-hoc signature so the program runs straight from dist (embed.sh signs again for the app).
codesign --force --sign - "${HELPERS}/lib/"*.dylib "${HELPERS}/piper" 2>/dev/null

for file in "${HELPERS}/piper" "${HELPERS}/lib/"*.dylib; do
  archs="$(lipo -archs "${file}")"
  if [[ " ${archs} " != *" arm64 "* || " ${archs} " != *" x86_64 "* ]]; then
    echo "build-piper: ${file} ist nicht universal (${archs})" >&2
    exit 1
  fi
done
echo "${STAMP_VALUE}" > "${DIST}/STAMP"
# PIPER_KEEP_WORK=1 keeps build/work with the CMake logs (e.g. to check that nothing was fetched).
if [[ -z "${PIPER_KEEP_WORK:-}" ]]; then rm -rf "${WORK}"; fi
echo "build-piper: ${DIST}"
