#!/bin/bash
# Runs the pinned Go toolchain inside wgtunnel/ with a clean environment: Xcode
# build phases export SDKROOT, ARCHS, LD … which Go must not see, and the system
# Go (1.19) must never be used. Extra variables go before the Go arguments:
#   scripts/go.sh test ./...
#   scripts/go.sh GOARCH=amd64 CGO_ENABLED=1 build ./capi
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GOROOT_DIR="$("${ROOT}/scripts/fetch-go.sh")"

EXTRA=()
if [[ -n "${DEVELOPER_DIR:-}" ]]; then EXTRA+=("DEVELOPER_DIR=${DEVELOPER_DIR}"); fi
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
  GOFLAGS="-mod=readonly -modcacherw" \
  ${EXTRA[@]+"${EXTRA[@]}"} \
  go "$@"
