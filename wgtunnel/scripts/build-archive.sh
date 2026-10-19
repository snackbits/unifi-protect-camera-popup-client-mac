#!/bin/bash
# Builds wgtunnel/build/libwgtunnel.a as a universal (arm64 + x86_64) static
# library from the Go c-archive in wgtunnel/capi. Called by the Xcode build phase
# "Build WireGuard tunnel" (and so by build-release.sh). Skips the build when the
# archive is newer than every Go source, go.mod, go.sum and the build scripts.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${ROOT}/build"
LIB="${OUT}/libwgtunnel.a"

if [[ -f "${LIB}" ]]; then
  NEWER="$(find "${ROOT}" \( -path "${ROOT}/.toolchain" -o -path "${ROOT}/build" \) -prune -o \
    \( -name '*.go' -o -name 'go.mod' -o -name 'go.sum' -o -name '*.sh' \) -newer "${LIB}" -print -quit)"
  if [[ -z "${NEWER}" ]]; then
    echo "build-archive: ${LIB} ist aktuell"
    exit 0
  fi
fi

SDK="$(xcrun --sdk macosx --show-sdk-path)"
CLANG="$(xcrun --sdk macosx -f clang)"
MIN="13.0"

mkdir -p "${OUT}"
for GOARCH in arm64 amd64; do
  if [[ "${GOARCH}" == "amd64" ]]; then CARCH="x86_64"; else CARCH="arm64"; fi
  echo "build-archive: baue ${GOARCH}"
  "${ROOT}/scripts/go.sh" \
    GOOS=darwin GOARCH="${GOARCH}" CGO_ENABLED=1 \
    CC="${CLANG} -arch ${CARCH}" \
    CGO_CFLAGS="-isysroot ${SDK} -mmacosx-version-min=${MIN} -O2" \
    CGO_LDFLAGS="-isysroot ${SDK} -mmacosx-version-min=${MIN}" \
    MACOSX_DEPLOYMENT_TARGET="${MIN}" \
    build -trimpath -buildmode=c-archive -o "${OUT}/${GOARCH}/libwgtunnel.a" ./capi
done

lipo -create -output "${LIB}.tmp" "${OUT}/arm64/libwgtunnel.a" "${OUT}/amd64/libwgtunnel.a"
mv "${LIB}.tmp" "${LIB}"
lipo -info "${LIB}"
