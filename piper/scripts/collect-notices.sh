#!/bin/bash
# Writes piper/NOTICES.txt: what the bundled Piper consists of, the GPL source offer and the
# license texts of piper, piper-phonemize (+ uni-algo), espeak-ng, onnxruntime, fmt, spdlog and
# of every offered voice. wgtunnel/scripts/collect-notices.sh appends it to ThirdPartyNotices.txt.
# Re-run after every change to scripts/fetch.sh or the voice catalog and commit the result.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CACHE="$("${ROOT}/scripts/fetch.sh")"
OUT="${ROOT}/NOTICES.txt"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/piper-notices.XXXXXX")"
trap 'rm -rf "${TMP}" "${OUT}.tmp"' EXIT

for archive in piper-2023.11.14-2.tar.gz piper-phonemize-bfc2e75.tar.gz espeak-ng-0f65aa3.tar.gz \
               fmt-10.0.0.tar.gz spdlog-1.12.0.tar.gz onnxruntime-osx-universal2-1.14.1.tgz; do
  tar -xzf "${CACHE}/${archive}" -C "${TMP}"
done
PIPER="${TMP}/piper-2023.11.14-2"
PHONEMIZE="${TMP}/piper-phonemize-bfc2e7549957829b0227c66a305d11cc88167bda"
ESPEAK="${TMP}/espeak-ng-0f65aa301e0d6bae5e172cc74197d32a6182200f"
ORT="${TMP}/onnxruntime-osx-universal2-1.14.1"

section() {
  echo
  echo "--- $1 ---"
  echo
  shift
  for file in "$@"; do cat "${file}"; echo; done
}

{
  echo
  echo "Camera Popup – Sprachausgabe (Piper)"
  echo "===================================="
  echo
  echo "Die Ansagen aus Text erzeugt Piper, ein eigenständiges Programm im App-Paket"
  echo "(Contents/Helpers/piper). Die App startet es als eigenen Prozess und linkt es nicht;"
  echo "die App selbst steht nicht unter der GPL. Piper ist mit espeak-ng (GPL-3.0-or-later)"
  echo "gelinkt; das Programm Piper samt Bibliotheken wird daher unter GPL-3.0-or-later"
  echo "weitergegeben (der Piper-Quellcode selbst ist MIT-lizenziert)."
  echo
  echo "Quellcode (genau die verwendeten Stände):"
  echo "  Piper 2023.11.14-2           https://github.com/rhasspy/piper/archive/refs/tags/2023.11.14-2.tar.gz"
  echo "  piper-phonemize bfc2e75      https://github.com/rhasspy/piper-phonemize/archive/bfc2e7549957829b0227c66a305d11cc88167bda.tar.gz"
  echo "  espeak-ng (rhasspy) 0f65aa3  https://github.com/rhasspy/espeak-ng/archive/0f65aa301e0d6bae5e172cc74197d32a6182200f.tar.gz"
  echo "  onnxruntime 1.14.1 (Binärpaket, so im App-Paket ausgeliefert)"
  echo "                               https://github.com/microsoft/onnxruntime/releases/download/v1.14.1/onnxruntime-osx-universal2-1.14.1.tgz"
  echo "  onnxruntime 1.14.1 (zugehöriger Quellcode, Tag v1.14.1)"
  echo "                               https://github.com/microsoft/onnxruntime/archive/refs/tags/v1.14.1.tar.gz"
  echo "  fmt 10.0.0                   https://github.com/fmtlib/fmt/archive/refs/tags/10.0.0.tar.gz"
  echo "  spdlog 1.12.0                https://github.com/gabime/spdlog/archive/refs/tags/v1.12.0.tar.gz"
  echo "Prüfsummen und Build-Befehle: Contents/Resources/piper/build-scripts/fetch.sh und build-piper.sh."
  echo "Spiegel dieser Quell-Archive und Build-Skripte (GPL-Quellcode-Angebot), abgelegt neben der App-Datei app.zip auf dem Update-Server:"
  echo "  https://snackbits.dev/apps/unifi-camera-popup/piper-source/2023.11.14-2/"
  echo
  echo "Stimmen (rhasspy/piper-voices, Stand c10ece1aade47bb51c153c893d14e5bf8e5b7117, Modelle MIT):"
  echo "  Thorsten (niedrig, mittel, hoch), Thorsten emotional – Datensatz Thorsten-Voice, CC0 1.0"
  echo "    https://github.com/thorstenMueller/Thorsten-Voice  (alle Stimmen lädt die App beim ersten Gebrauch)"
  echo "  Kerstin – dataset-voice-kerstin, CC0 1.0  https://github.com/rhasspy/dataset-voice-kerstin"
  echo "  Eva K., Karlsson, Ramona – M-AILABS Speech Dataset (Sprachmodell von rhasspy/piper-voices aus diesem"
  echo "  Datensatz trainiert; Lizenztext des Datensatzes, wörtlich nach https://www.caito.de/2019/01/03/the-m-ailabs-speech-dataset/):"
  echo "    Copyright (c) 2017-2019 by the original creators @ M-AILABS with the following license:"
  echo "    Redistribution and use in any form, including any commercial use, with or without"
  echo "    modification are permitted provided that the following conditions are met: Redistributions"
  echo "    of source data must retain the above copyright notice, this list of conditions and the"
  echo "    following disclaimer. Neither the name of the copyright holder nor the names of its"
  echo "    contributors may be used to endorse or promote products derived from this downloaded data,"
  echo "    source-code or binary-code without specific prior written permission. THIS DATA IS PROVIDED"
  echo "    BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS \"AS IS\" AND ANY EXPRESS OR IMPLIED WARRANTIES,"
  echo "    INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A"
  echo "    PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE"
  echo "    LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES"
  echo "    (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,"
  echo "    DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,"
  echo "    WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING"
  echo "    IN ANY WAY OUT OF THE USE OF THIS SOFTWARE and/or DATA, EVEN IF ADVISED OF THE POSSIBILITY"
  echo "    OF SUCH DAMAGE."
  echo "  Nicht angeboten: Pavoque (CC BY-NC-SA 4.0 – keine kommerzielle Nutzung)."
  section "rhasspy/piper 2023.11.14-2 (MIT)" "${PIPER}/LICENSE.md"
  section "rhasspy/piper-phonemize bfc2e75 (MIT)" "${PHONEMIZE}/LICENSE.md"
  section "uni-algo (in piper-phonemize)" "${PHONEMIZE}/licenses/uni-algo/LICENSE.md"
  section "espeak-ng 1.52 (rhasspy-Fork 0f65aa3, GPL-3.0-or-later)" "${ESPEAK}/COPYING"
  section "espeak-ng: Unicode Character Database (ucd-tools)" "${ESPEAK}/COPYING.UCD"
  section "onnxruntime 1.14.1 (MIT; Hinweise Dritter: Contents/Resources/piper/ThirdPartyNotices-onnxruntime.txt)" "${ORT}/LICENSE"
  section "fmt 10.0.0 (MIT)" "${TMP}/fmt-10.0.0/LICENSE.rst"
  section "spdlog 1.12.0 (MIT)" "${TMP}/spdlog-1.12.0/LICENSE"
} > "${OUT}.tmp"
mv "${OUT}.tmp" "${OUT}"
echo "collect-notices: ${OUT}"
