#!/bin/bash
# Downloads the pinned Go toolchain into wgtunnel/.toolchain (gitignored) and
# prints its GOROOT. The system Go (1.19 amd64) is too old for wireguard-go.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GO_VERSION="1.27.2"

case "$(uname -m)" in
  arm64)  GO_ARCH="arm64"; GO_SHA256="76812b213b1b2302c978d28fa52fa92d541704b9e7d9d5db8002c50e4018c4c5" ;;
  x86_64) GO_ARCH="amd64"; GO_SHA256="587b59182488b23aa6e5fc25110405a3e0e5b38ed2f5b2f46ed13c32aee356fe" ;;
  *) echo "fetch-go: unbekannte Architektur $(uname -m)" >&2; exit 1 ;;
esac

DEST="${ROOT}/.toolchain/go${GO_VERSION}-${GO_ARCH}"
if [[ -x "${DEST}/go/bin/go" ]] && [[ "$("${DEST}/go/bin/go" env GOVERSION 2>/dev/null)" == "go${GO_VERSION}" ]]; then
  echo "${DEST}/go"
  exit 0
fi

mkdir -p "${ROOT}/.toolchain"
TMP="$(mktemp -d "${ROOT}/.toolchain/download.XXXXXX")"
trap 'rm -rf "${TMP}"' EXIT

URL="https://go.dev/dl/go${GO_VERSION}.darwin-${GO_ARCH}.tar.gz"
echo "fetch-go: lade ${URL}" >&2
curl -fsSL --retry 3 -o "${TMP}/go.tar.gz" "${URL}"
echo "${GO_SHA256}  ${TMP}/go.tar.gz" | shasum -a 256 -c - >&2
tar -xzf "${TMP}/go.tar.gz" -C "${TMP}"
rm -rf "${DEST}"
mkdir -p "${DEST}"
mv "${TMP}/go" "${DEST}/go"
echo "${DEST}/go"
