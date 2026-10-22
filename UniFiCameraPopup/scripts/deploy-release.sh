#!/bin/bash
# Puts a finished release (from build-release.sh) online and checks it live:
#   snackbits.dev/apps/unifi-camera-popup/: version.json, app.zip, UniFi-Camera-Popup.dmg,
#     piper-source/ (static files, nginx of snackbits.dev serves them from RELEASE_DIR)
#   relay server (unifi-protect-camera-popup-server.snackbits.dev): version.json – its versionId
#     decides which app builds the relay accepts.
# Until the old download routes on the relay subdomain are switched off (LEGACY=0, from
# 2026-11-05), app.zip, the DMG and piper-source/ go there too: installed apps up to 3.1.0 poll
# its /version.
# The files are not in the server's git (too big, they change every release) – they are uploaded
# with rsync. Server code (src/, nginx/, scripts/) still goes through git: commit and push it in
# server/ first, this script then runs the server's pull-and-chown.sh.
#
# Usage: scripts/deploy-release.sh [--dry-run] [--nginx [--yes]]
#   --dry-run  checks everything locally and prints the steps, changes nothing
#   --nginx    also installs server/nginx/server.config (shows the diff and asks first)
#   --yes      installs the nginx config without asking (after reviewing it with --dry-run)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/.."

SSH_HOST="${SSH_HOST:-snackbits}"
REMOTE_DIR="${REMOTE_DIR:-/var/www/snackbits.dev/subdomains/unifi-protect-camera-popup-server}"
REMOTE_OWNER="${REMOTE_OWNER:-snackbitsdev:snackbitsdev}"
BASE_URL="${BASE_URL:-https://unifi-protect-camera-popup-server.snackbits.dev}"
RELEASE_DIR="${RELEASE_DIR:-/var/www/snackbits.dev/releases/apps/unifi-camera-popup}"
RELEASE_URL="${RELEASE_URL:-https://snackbits.dev/apps/unifi-camera-popup}"
# 1 = also serve app.zip, DMG and piper-source/ from the relay subdomain (transition, see above).
LEGACY="${LEGACY:-1}"
NGINX_SITE="/etc/nginx/sites-available/unifi-protect-camera-popup-server.snackbits.dev"

SERVER_DIR="../../server"
VERSION_FILE="${SERVER_DIR}/version.json"
ZIP="${SERVER_DIR}/public/app.zip"
DMG="${SERVER_DIR}/public/UniFi-Camera-Popup.dmg"
PIPER_SRC="${SERVER_DIR}/public/piper-source"

DRY_RUN=0
NGINX=0
YES=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --nginx) NGINX=1 ;;
    --yes) YES=1 ;;
    -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $arg (see --help)" >&2; exit 1 ;;
  esac
done

fail() { echo "ERROR: $*" >&2; exit 1; }
run() {
  echo "+ $*"
  if (( DRY_RUN == 0 )); then "$@"; fi
}
json() { plutil -extract "$1" raw -o - "$2"; }

# ---------------------------------------------------------------------------
# 1. Local checks – nothing is uploaded unless the release is complete and consistent.
# ---------------------------------------------------------------------------
for file in "$VERSION_FILE" "$ZIP" "$DMG"; do
  [[ -s "$file" ]] || fail "$file missing – run scripts/build-release.sh first."
done
[[ -d "$PIPER_SRC" ]] || fail "$PIPER_SRC missing – run scripts/build-release.sh first."

BUILD="$(json buildNumber "$VERSION_FILE")"
SHORT="$(json shortVersion "$VERSION_FILE")"
SHA="$(json sha256 "$VERSION_FILE")"
SIGNATURE="$(json signature "$VERSION_FILE")"
APP_BUILD="$(sed -nE 's/.*static let buildNumber = ([0-9]+).*/\1/p' AppConfig.swift)"

[[ "$BUILD" == "$APP_BUILD" ]] \
  || fail "version.json is build ${BUILD}, AppConfig.swift build ${APP_BUILD} – they must come from the same build-release.sh run."
[[ "$(shasum -a 256 "$ZIP" | awk '{print $1}')" == "$SHA" ]] \
  || fail "app.zip does not match the sha256 in version.json – run scripts/build-release.sh again."
[[ -n "$SIGNATURE" ]] || fail "version.json has no signature – the app would refuse the update."
hdiutil verify -quiet "$DMG" || fail "$DMG is damaged."

if [[ -n "$(git -C "$SERVER_DIR" status --porcelain)" ]]; then
  git -C "$SERVER_DIR" status --short >&2
  fail "server/ has uncommitted changes – commit and push them first (release files are git-ignored)."
fi
git -C "$SERVER_DIR" fetch --quiet
if [[ -n "$(git -C "$SERVER_DIR" rev-list '@{u}..HEAD')" ]]; then
  fail "server/ has commits that are not pushed – push them first, the server pulls from the remote."
fi

echo "Release ${SHORT} (build ${BUILD}) → ${SSH_HOST}:${RELEASE_DIR} (+ version.json → ${REMOTE_DIR})"
(( LEGACY )) && echo "  legacy: app.zip, DMG and piper-source/ also → ${REMOTE_DIR}/public"
(( DRY_RUN )) && echo "(dry run – nothing is changed)"

# ---------------------------------------------------------------------------
# 2. Server code, then the release files. version.json goes last: apps only see the new
#    version once app.zip is in place (rsync replaces each file atomically).
# ---------------------------------------------------------------------------
# The first pull after the release files left git deletes them from the checkout: keep copies and
# put them straight back, so /version and /app.zip never vanish (an empty version id would make
# the relay drop every connected app as outdated).
run ssh -n "$SSH_HOST" "cd '${REMOTE_DIR}' \
  && for f in version.json public/app.zip; do [ -f \"\$f\" ] && cp -p \"\$f\" \"\$f.keep\"; done; \
  ./scripts/pull-and-chown.sh; status=\$?; \
  for f in version.json public/app.zip; do [ -f \"\$f\" ] || { [ -f \"\$f.keep\" ] && mv \"\$f.keep\" \"\$f\"; }; rm -f \"\$f.keep\"; done; \
  exit \$status"
run ssh -n "$SSH_HOST" "mkdir -p '${RELEASE_DIR}'"
run rsync -a --delete "${PIPER_SRC}/" "${SSH_HOST}:${RELEASE_DIR}/piper-source/"
run rsync -a "$ZIP" "$DMG" "${SSH_HOST}:${RELEASE_DIR}/"
if (( LEGACY )); then
  run rsync -a --delete "${PIPER_SRC}/" "${SSH_HOST}:${REMOTE_DIR}/public/piper-source/"
  run rsync -a "$ZIP" "$DMG" "${SSH_HOST}:${REMOTE_DIR}/public/"
fi
run rsync -a "$VERSION_FILE" "${SSH_HOST}:${RELEASE_DIR}/version.json"
run rsync -a "$VERSION_FILE" "${SSH_HOST}:${REMOTE_DIR}/version.json"
run ssh -n "$SSH_HOST" "chown -R '${REMOTE_OWNER}' '${RELEASE_DIR}' '${REMOTE_DIR}/public' '${REMOTE_DIR}/version.json'"

if (( NGINX )); then
  GENERATED="$(mktemp)"
  trap 'rm -f "$GENERATED"' EXIT
  sed -e "s|__SERVER_DIR__|${REMOTE_DIR}|g" "${SERVER_DIR}/nginx/server.config" > "$GENERATED"
  echo "nginx: changes against the live ${NGINX_SITE}:"
  ssh -n "$SSH_HOST" "cat '${NGINX_SITE}'" | diff -u - "$GENERATED" || true
  if (( DRY_RUN == 0 )); then
    answer=y
    # Asked on the terminal: ssh above must not swallow the answer (ssh -n), and stdin may be a pipe.
    (( YES )) || read -r -p "Install this nginx config and reload nginx? [y/N] " answer < /dev/tty || answer=n
    if [[ "$answer" == [yYjJ]* ]]; then
      scp -q "$GENERATED" "${SSH_HOST}:${NGINX_SITE}.new"
      ssh -n "$SSH_HOST" "cp '${NGINX_SITE}' '${NGINX_SITE}.bak' && mv '${NGINX_SITE}.new' '${NGINX_SITE}' \
        && (nginx -t && systemctl reload nginx || { mv '${NGINX_SITE}.bak' '${NGINX_SITE}'; nginx -t; exit 1; })" \
        || fail "nginx rejected the config – the previous one is back in place."
      echo "nginx reloaded (previous config: ${NGINX_SITE}.bak)."
    else
      echo "nginx left unchanged."
    fi
  fi
fi

(( DRY_RUN )) && exit 0

# ---------------------------------------------------------------------------
# 3. Check what users actually get.
# ---------------------------------------------------------------------------
LIVE="$(mktemp -d)"
trap 'rm -rf "$LIVE"' EXIT
# check_files <manifest url> <base url>: manifest, app.zip, DMG and source mirror as users get them.
check_files() {
  curl -fsS "$1" -o "${LIVE}/version.json" || fail "GET $1 failed."
  [[ "$(json buildNumber "${LIVE}/version.json")" == "$BUILD" ]] \
    || fail "$1 still reports build $(json buildNumber "${LIVE}/version.json") instead of ${BUILD}."
  curl -fsS "$2/app.zip" -o "${LIVE}/app.zip" || fail "GET $2/app.zip failed."
  [[ "$(shasum -a 256 "${LIVE}/app.zip" | awk '{print $1}')" == "$SHA" ]] \
    || fail "$2/app.zip does not match version.json."
  local size
  size="$(curl -fsSI "$2/UniFi-Camera-Popup.dmg" | awk 'tolower($1)=="content-length:" {print $2}' | tr -d '\r')"
  [[ "$size" == "$(stat -f %z "$DMG")" ]] \
    || fail "$2/UniFi-Camera-Popup.dmg does not serve the new DMG (size ${size:-none})."
  curl -fsSI "$2/piper-source/2023.11.14-2/" >/dev/null || fail "GET $2/piper-source/ failed – is the nginx location installed?"
}
check_files "${RELEASE_URL}/version.json" "$RELEASE_URL"
if (( LEGACY )); then
  check_files "${BASE_URL}/version" "$BASE_URL"
else
  curl -fsS "${BASE_URL}/version" -o "${LIVE}/relay.json" || fail "GET ${BASE_URL}/version failed."
  [[ "$(json buildNumber "${LIVE}/relay.json")" == "$BUILD" ]] || fail "the relay still has build $(json buildNumber "${LIVE}/relay.json")."
fi

echo ""
echo "Live: ${SHORT} (build ${BUILD})"
echo "  ${RELEASE_URL}/version.json"
echo "  ${RELEASE_URL}/app.zip"
echo "  ${RELEASE_URL}/UniFi-Camera-Popup.dmg"
echo "  relay: ${BASE_URL}/version$( (( LEGACY )) && echo " (+ legacy app.zip, DMG, piper-source/)")"
echo ""
echo "Now record the release in app/: git add UniFiCameraPopup/AppConfig.swift && git commit -m \"Release ${SHORT} (build ${BUILD})\""
