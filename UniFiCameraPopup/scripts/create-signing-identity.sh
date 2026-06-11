#!/bin/bash
set -euo pipefail

# ---------------------------------------------------------------------------
# Creates a STABLE, self-signed code signing identity in the login keychain.
#
# Why: macOS binds privacy grants (e.g. Full Disk Access, needed for Focus /
# Do Not Disturb detection) to the app's code signature. An ad-hoc signature
# (`codesign --sign -`) has no stable identity, so its CDHash changes on every
# build and the granted access is silently revoked after each update.
#
# Signing with a fixed self-signed certificate gives the app a stable
# "designated requirement", so the grant survives rebuilds and auto-updates.
# No Apple Developer account required. For public distribution / notarization
# you still want a real "Developer ID Application" certificate later.
#
# Idempotent: re-running reuses the existing identity.
# ---------------------------------------------------------------------------

IDENTITY_NAME="${SIGNING_IDENTITY:-UniFi Camera Popup (Self-Signed)}"
KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"

if security find-certificate -c "$IDENTITY_NAME" "$KEYCHAIN" >/dev/null 2>&1; then
  echo "Signing identity already exists: ${IDENTITY_NAME}"
  exit 0
fi

echo "Creating self-signed code signing identity: ${IDENTITY_NAME}"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

CONF="${TMP_DIR}/codesign.cnf"
cat > "$CONF" <<EOF
[ req ]
distinguished_name = dn
x509_extensions    = ext
prompt             = no
[ dn ]
CN = ${IDENTITY_NAME}
[ ext ]
basicConstraints   = critical,CA:false
keyUsage           = critical,digitalSignature
extendedKeyUsage   = critical,codeSigning
EOF

# 10-year self-signed cert + key.
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout "${TMP_DIR}/key.pem" \
  -out "${TMP_DIR}/cert.pem" \
  -days 3650 \
  -config "$CONF"

# Apple's `security import` cannot read the modern PKCS#12 MAC/cipher emitted by
# OpenSSL 3, so force the legacy SHA1/3DES encoding. A throwaway password is
# used because some toolchains reject MAC-less, password-less archives.
P12_PASS="unifi"
P12_LEGACY_FLAG=""
if openssl pkcs12 -help 2>&1 | grep -q -- "-legacy"; then
  P12_LEGACY_FLAG="-legacy"
fi

openssl pkcs12 -export ${P12_LEGACY_FLAG} \
  -inkey "${TMP_DIR}/key.pem" \
  -in "${TMP_DIR}/cert.pem" \
  -name "$IDENTITY_NAME" \
  -out "${TMP_DIR}/identity.p12" \
  -macalg sha1 \
  -certpbe PBE-SHA1-3DES \
  -keypbe PBE-SHA1-3DES \
  -passout "pass:${P12_PASS}"

# Import into the login keychain and pre-authorize codesign so signing does
# not prompt on every build.
security import "${TMP_DIR}/identity.p12" \
  -k "$KEYCHAIN" \
  -P "$P12_PASS" \
  -T /usr/bin/codesign \
  -T /usr/bin/security \
  -A

echo ""
echo "Done. Identity '${IDENTITY_NAME}' added to the login keychain."
echo "The first build may ask permission to use the key — choose 'Always Allow'."
