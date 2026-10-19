#!/bin/bash
# Runs the pinned Go toolchain inside wgtunnel/ with a clean environment: Xcode
# build phases export SDKROOT, ARCHS, LD … which Go must not see, and the system
# Go (1.19) must never be used. No go.work, no user go.env (GOWORK/GOENV off),
# fixed module proxy and checksum database. Extra variables go before the Go arguments:
#   scripts/go.sh test ./...
#   scripts/go.sh GOARCH=amd64 CGO_ENABLED=1 build ./capi
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GOROOT_DIR="$("${ROOT}/scripts/fetch-go.sh")"

EXTRA=()
if [[ -n "${DEVELOPER_DIR:-}" ]]; then EXTRA+=("DEVELOPER_DIR=${DEVELOPER_DIR}"); fi
# A proxy of the user's network is needed for module downloads; nothing else leaks in.
for proxy in HTTPS_PROXY https_proxy NO_PROXY no_proxy; do
  if [[ -n "${!proxy:-}" ]]; then EXTRA+=("${proxy}=${!proxy}"); fi
done
while [[ $# -gt 0 && "$1" =~ ^[A-Z_][A-Z0-9_]*= ]]; do
  EXTRA+=("$1")
  shift
done

cd "${ROOT}"
exec env -i \
  PATH="${GOROOT_DIR}/bin:/usr/bin:/bin" \
  HOME="${HOME}" \
  GOROOT="${GOROOT_DIR}" \
  GOPATH="${ROOT}/.toolchain/gopath" \
  GOCACHE="${ROOT}/.toolchain/gocache" \
  GOMODCACHE="${ROOT}/.toolchain/gomodcache" \
  GOTOOLCHAIN=local \
  GOWORK=off \
  GOENV=off \
  GOFLAGS="-mod=readonly -modcacherw" \
  GOPROXY="https://proxy.golang.org,direct" \
  GOSUMDB="sum.golang.org" \
  ${EXTRA[@]+"${EXTRA[@]}"} \
  go "$@"
