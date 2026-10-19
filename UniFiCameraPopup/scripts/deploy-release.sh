#!/bin/bash
# Puts a finished release (from build-release.sh) on the update server and checks it live:
#   version.json, public/app.zip, public/UniFi-Camera-Popup.dmg, public/piper-source/
# These files are not in the server's git (too big, they change every release) – they are
# uploaded with rsync. Server code (src/, nginx/, scripts/) still goes through git: commit and
# push it in server/ first, this script then runs the server's pull-and-chown.sh.
#
# Usage: scripts/deploy-release.sh [--dry-run] [--nginx]
#   --dry-run  checks everything locally and prints the steps, changes nothing
#   --nginx    also installs server/nginx/server.config (shows the diff and asks first)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/.."

SSH_HOST="${SSH_HOST:-snackbits}"
REMOTE_DIR="${REMOTE_DIR:-/var/www/snackbits.dev/subdomains/unifi-protect-camera-popup-server}"
REMOTE_OWNER="${REMOTE_OWNER:-snackbitsdev:snackbitsdev}"
BASE_URL="${BASE_URL:-https://unifi-protect-camera-popup-server.snackbits.dev}"
NGINX_SITE="/etc/nginx/sites-available/unifi-protect-camera-popup-server.snackbits.dev"

SERVER_DIR="../../server"
VERSION_FILE="${SERVER_DIR}/version.json"
ZIP="${SERVER_DIR}/public/app.zip"
DMG="${SERVER_DIR}/public/UniFi-Camera-Popup.dmg"
PIPER_SRC="${SERVER_DIR}/public/piper-source"

DRY_RUN=0
NGINX=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --nginx) NGINX=1 ;;
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

echo "Release ${SHORT} (build ${BUILD}) → ${SSH_HOST}:${REMOTE_DIR}"
(( DRY_RUN )) && echo "(dry run – nothing is changed)"

# ---------------------------------------------------------------------------
# 2. Server code, then the release files. version.json goes last: apps only see the new
#    version once app.zip is in place (rsync replaces each file atomically).
# ---------------------------------------------------------------------------
# The first pull after the release files left git deletes them from the checkout: keep copies and
# put them straight back, so /version and /app.zip never vanish (an empty version id would make
# the relay drop every connected app as outdated).
run ssh "$SSH_HOST" "cd '${REMOTE_DIR}' \
  && for f in version.json public/app.zip; do [ -f \"\$f\" ] && cp -p \"\$f\" \"\$f.keep\"; done; \
  ./scripts/pull-and-chown.sh; status=\$?; \
  for f in version.json public/app.zip; do [ -f \"\$f\" ] || { [ -f \"\$f.keep\" ] && mv \"\$f.keep\" \"\$f\"; }; rm -f \"\$f.keep\"; done; \
  exit \$status"
run rsync -a --delete "${PIPER_SRC}/" "${SSH_HOST}:${REMOTE_DIR}/public/piper-source/"
run rsync -a "$ZIP" "$DMG" "${SSH_HOST}:${REMOTE_DIR}/public/"
run rsync -a "$VERSION_FILE" "${SSH_HOST}:${REMOTE_DIR}/version.json"
run ssh "$SSH_HOST" "chown -R '${REMOTE_OWNER}' '${REMOTE_DIR}/public' '${REMOTE_DIR}/version.json'"

if (( NGINX )); then
  GENERATED="$(mktemp)"
  trap 'rm -f "$GENERATED"' EXIT
  sed -e "s|__SERVER_DIR__|${REMOTE_DIR}|g" "${SERVER_DIR}/nginx/server.config" > "$GENERATED"
  echo "nginx: changes against the live ${NGINX_SITE}:"
  ssh "$SSH_HOST" "cat '${NGINX_SITE}'" | diff -u - "$GENERATED" || true
  if (( DRY_RUN == 0 )); then
    read -r -p "Install this nginx config and reload nginx? [y/N] " answer
    if [[ "$answer" == [yYjJ]* ]]; then
      scp -q "$GENERATED" "${SSH_HOST}:${NGINX_SITE}.new"
      ssh "$SSH_HOST" "cp '${NGINX_SITE}' '${NGINX_SITE}.bak' && mv '${NGINX_SITE}.new' '${NGINX_SITE}' \
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
curl -fsS "${BASE_URL}/version" -o "${LIVE}/version.json" || fail "GET /version failed."
[[ "$(json buildNumber "${LIVE}/version.json")" == "$BUILD" ]] \
  || fail "/version still reports build $(json buildNumber "${LIVE}/version.json") instead of ${BUILD}."
curl -fsS "${BASE_URL}/app.zip" -o "${LIVE}/app.zip" || fail "GET /app.zip failed."
[[ "$(shasum -a 256 "${LIVE}/app.zip" | awk '{print $1}')" == "$SHA" ]] \
  || fail "the live app.zip does not match version.json."
DMG_SIZE="$(curl -fsSI "${BASE_URL}/UniFi-Camera-Popup.dmg" | awk 'tolower($1)=="content-length:" {print $2}' | tr -d '\r')"
[[ "$DMG_SIZE" == "$(stat -f %z "$DMG")" ]] \
  || fail "GET /UniFi-Camera-Popup.dmg does not serve the new DMG (size ${DMG_SIZE:-none}) – is the nginx location installed? (--nginx)"
curl -fsSI "${BASE_URL}/piper-source/2023.11.14-2/" >/dev/null || fail "GET /piper-source/ failed – is the nginx location installed? (--nginx)"

echo ""
echo "Live: ${SHORT} (build ${BUILD})"
echo "  ${BASE_URL}/version"
echo "  ${BASE_URL}/app.zip"
echo "  ${BASE_URL}/UniFi-Camera-Popup.dmg"
echo ""
echo "Now record the release in app/: git add UniFiCameraPopup/AppConfig.swift && git commit -m \"Release ${SHORT} (build ${BUILD})\""
