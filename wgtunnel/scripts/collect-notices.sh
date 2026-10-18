#!/bin/bash
# Writes UniFiCameraPopup/ThirdPartyNotices.txt: license texts of the Go runtime and
# of every module linked into libwgtunnel.a (shown in Hilfe › „Über“).
# Re-run after every change to go.mod and commit the result.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${ROOT}/../UniFiCameraPopup/ThirdPartyNotices.txt"
GOROOT_DIR="$("${ROOT}/scripts/fetch-go.sh")"
GO="${ROOT}/scripts/go.sh"

"${GO}" mod download
{
  echo "Camera Popup – Software von Dritten im WireGuard-Tunnel"
  echo "========================================================"
  echo
  echo "--- Go $("${GO}" env GOVERSION) (Laufzeit und Standardbibliothek) ---"
  echo
  cat "${GOROOT_DIR}/LICENSE"
  "${GO}" GOOS=darwin CGO_ENABLED=1 list -deps \
    -f '{{if and .Module (not .Module.Main)}}{{.Module.Path}}	{{.Module.Version}}	{{.Module.Dir}}{{end}}' ./capi \
    | sort -u | while IFS=$'\t' read -r path version dir; do
      echo
      echo "--- ${path} ${version} ---"
      echo
      cat "${dir}/LICENSE"
      for extra in NOTICE AUTHORS; do
        if [[ -f "${dir}/${extra}" ]]; then
          echo
          cat "${dir}/${extra}"
        fi
      done
    done
} > "${OUT}"
echo "collect-notices: ${OUT}"
