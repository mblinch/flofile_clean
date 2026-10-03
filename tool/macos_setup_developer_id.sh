#!/bin/bash
# Create / install a Developer ID Application certificate for the FloFile org team
# and store notarytool credentials for distribution outside the App Store.
#
# Prerequisites (one-time, in Safari while signed into the org Apple ID):
#   1. https://developer.apple.com/account → accept any pending agreements
#   2. Certificates → + → Developer ID Application → upload the CSR this script prints
#   3. Download the .cer and pass its path to this script (or drop it on Desktop)
#
# Usage:
#   ./tool/macos_setup_developer_id.sh                  # generate CSR + instructions
#   ./tool/macos_setup_developer_id.sh ~/Desktop/developerID_application.cer
#   NOTARY_APPLE_ID=you@example.com NOTARY_APP_PASSWORD=xxxx-xxxx-xxxx-xxxx \
#     ./tool/macos_setup_developer_id.sh ~/Desktop/developerID_application.cer
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEAM="$(grep '^DEVELOPMENT_TEAM' "$ROOT/macos/Runner/Configs/AppInfo.xcconfig" | sed 's/.*= *//' | tr -d '[:space:]')"
CERT_DIR="${FLOFILE_CERT_DIR:-$HOME/.flofile/certs}"
CSR_PATH="$CERT_DIR/flofile_developer_id.csr"
KEY_PATH="$CERT_DIR/flofile_developer_id.key"
NOTARY_PROFILE="${NOTARY_KEYCHAIN_PROFILE:-flofile-notarize}"

mkdir -p "$CERT_DIR"
chmod 700 "$CERT_DIR"

if [ ! -f "$KEY_PATH" ] || [ ! -f "$CSR_PATH" ]; then
  echo "Generating Developer ID key + CSR for team $TEAM..."
  openssl genrsa -out "$KEY_PATH" 2048
  openssl req -new -key "$KEY_PATH" -out "$CSR_PATH" \
    -subj "/emailAddress=dev@flofilecaptions.com/CN=1001746423 Ontario Inc./C=CA"
  security import "$KEY_PATH" -k "$HOME/Library/Keychains/login.keychain-db" \
    -T /usr/bin/codesign -T /usr/bin/security >/dev/null || true
  cp "$CSR_PATH" "$HOME/Desktop/flofile_developer_id.csr"
  echo "CSR copied to Desktop: flofile_developer_id.csr"
fi

CER_PATH="${1:-}"
if [ -z "$CER_PATH" ]; then
  # Auto-pick a freshly downloaded cert from Desktop / Downloads.
  for candidate in \
    "$HOME/Desktop/developerID_application.cer" \
    "$HOME/Downloads/developerID_application.cer" \
    "$HOME/Desktop/"developerID*.cer \
    "$HOME/Downloads/"developerID*.cer; do
    if [ -f "$candidate" ]; then
      CER_PATH="$candidate"
      break
    fi
  done
fi

if [ -z "$CER_PATH" ] || [ ! -f "$CER_PATH" ]; then
  cat <<EOF

CSR ready: $CSR_PATH
(also on Desktop: flofile_developer_id.csr)

In Safari (org Apple ID, team $TEAM):
  1. Open https://developer.apple.com/account/resources/certificates/add
  2. Choose "Developer ID Application" → Continue
  3. Upload flofile_developer_id.csr → Continue → Download
  4. Re-run:
       ./tool/macos_setup_developer_id.sh ~/Downloads/developerID_application.cer

Also accept any membership agreements at:
  https://developer.apple.com/account

EOF
  exit 0
fi

echo "Installing certificate: $CER_PATH"
security import "$CER_PATH" -k "$HOME/Library/Keychains/login.keychain-db" >/dev/null
cp "$CER_PATH" "$CERT_DIR/"

echo "Current Developer ID identities:"
security find-identity -v -p codesigning | grep 'Developer ID Application:' || true

ORG_ID="$(security find-identity -v -p codesigning \
  | grep "Developer ID Application:.*($TEAM)" || true)"
if [ -z "$ORG_ID" ]; then
  echo "Warning: No Developer ID Application cert found for team $TEAM yet." >&2
  echo "Confirm the .cer was created under 1001746423 Ontario Inc. ($TEAM)." >&2
  exit 1
fi
echo "Org Developer ID ready:"
echo "$ORG_ID"

if [ -n "${NOTARY_APPLE_ID:-}" ] && [ -n "${NOTARY_APP_PASSWORD:-}" ]; then
  echo "Storing notarytool profile '$NOTARY_PROFILE'..."
  xcrun notarytool store-credentials "$NOTARY_PROFILE" \
    --apple-id "$NOTARY_APPLE_ID" \
    --team-id "$TEAM" \
    --password "$NOTARY_APP_PASSWORD"
  echo "Notary credentials stored. Test with:"
  echo "  xcrun notarytool history --keychain-profile $NOTARY_PROFILE"
else
  cat <<EOF

Optional — store notarization credentials (app-specific password from
https://appleid.apple.com → Sign-In and Security → App-Specific Passwords):

  NOTARY_APPLE_ID='your-org-apple-id@email.com' \\
  NOTARY_APP_PASSWORD='xxxx-xxxx-xxxx-xxxx' \\
    ./tool/macos_setup_developer_id.sh "$CER_PATH"

EOF
fi

echo "Done."
