#!/bin/bash
# Loopback end-to-end check of libwgtunnel.a from Swift – no app, no real network:
# builds the archive, starts the fake home (cmd/home), runs smoke/main.swift against it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"${ROOT}/scripts/build-archive.sh" >/dev/null
WORK="$(mktemp -d "${TMPDIR:-/tmp}/wgsmoke.XXXXXX")"
HOME_PID=""
cleanup() {
  if [[ -n "${HOME_PID}" ]]; then
    kill "${HOME_PID}" 2>/dev/null || true
    wait "${HOME_PID}" 2>/dev/null || true
  fi
  rm -rf "${WORK}"
}
trap cleanup EXIT

"${ROOT}/scripts/go.sh" build -o "${WORK}/home" ./cmd/home
PORT=$((40000 + RANDOM % 20000))
"${WORK}/home" -port "${PORT}" -out "${WORK}/app.conf" > "${WORK}/home.log" 2>&1 &
HOME_PID=$!
for _ in $(seq 1 50); do
  [[ -s "${WORK}/app.conf" ]] && break
  sleep 0.1
done

xcrun swiftc -O -I "${ROOT}/include" "${ROOT}/smoke/main.swift" "${ROOT}/build/libwgtunnel.a" \
  -lresolv -framework Security -framework CoreFoundation -o "${WORK}/smoke"
"${WORK}/smoke" "${WORK}/app.conf"
