#!/bin/bash
# Lets the Piper of an app bundle (or of piper/build/dist) speak one German sentence with
# Thorsten (medium) and checks the result: exit 0, a 16-bit mono 22050 Hz WAV of more than 1 s.
#   scripts/smoke.sh                       → piper/build/dist
#   scripts/smoke.sh "<path>/Contents"     → an app bundle's Contents folder
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASE="${1:-${ROOT}/build/dist}"
PIPER="${BASE}/Helpers/piper/piper"
RES="${BASE}/Resources/piper"
WAV="$(mktemp "${TMPDIR:-/tmp}/piper-smoke.XXXXXX").wav"
trap 'rm -f "${WAV}"' EXIT

START=$(date +%s)
echo "Achtung: An der Haustür hat jemand geklingelt." | "${PIPER}" --quiet \
  --model "${RES}/voices/de_DE-thorsten-medium.onnx" --config "${RES}/voices/de_DE-thorsten-medium.onnx.json" \
  --espeak_data "${RES}/espeak-ng-data" --output_file "${WAV}" > /dev/null
INFO="$(afinfo "${WAV}")"
grep -q "1 ch,  22050 Hz, Int16" <<< "${INFO}" || { echo "piper-smoke: falsches Format" >&2; echo "${INFO}" >&2; exit 1; }
SECONDS_AUDIO="$(awk '/estimated duration/ {print $3}' <<< "${INFO}")"
awk -v d="${SECONDS_AUDIO}" 'BEGIN { exit !(d > 1.0) }' || { echo "piper-smoke: zu kurz (${SECONDS_AUDIO} s)" >&2; exit 1; }
echo "piper-smoke: ok (${SECONDS_AUDIO} s Ton in $(( $(date +%s) - START )) s)"
