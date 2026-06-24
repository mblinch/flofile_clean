#!/bin/bash
# Re-sign a Release .app with Developer ID and notarize for distribution outside the App Store.
#
# Prerequisites:
#   1. Paid Apple Developer Program membership (active)
#   2. Developer ID Application certificate in Keychain (create at developer.apple.com)
#   3. Notary credentials stored once:
#        xcrun notarytool store-credentials "flofile-notarize" \
#          --apple-id "you@example.com" \
#          --team-id "YOUR_TEAM_ID" \
#          --password "xxxx-xxxx-xxxx-xxxx"
#
# Usage:
#   ./tool/macos_sign_and_notarize.sh "build/macos/Build/Products/Release/FloFile Beta.app"
#
# Env:
#   DEVELOPER_ID_SIGNING_IDENTITY  Full cert name (auto-detected if unset)
#   NOTARY_KEYCHAIN_PROFILE        Default: flofile-notarize
#   SKIP_NOTARIZE=1                Sign only, skip notarytool (local testing)
set -euo pipefail

APP_PATH="${1:-}"
if [ -z "$APP_PATH" ] || [ ! -d "$APP_PATH" ]; then
  echo "Usage: $0 <path-to-.app>" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENTITLEMENTS="$ROOT/macos/Runner/Release.entitlements"
NOTARY_PROFILE="${NOTARY_KEYCHAIN_PROFILE:-flofile-notarize}"

resolve_signing_identity() {
  if [ -n "${DEVELOPER_ID_SIGNING_IDENTITY:-}" ]; then
    echo "$DEVELOPER_ID_SIGNING_IDENTITY"
    return
  fi
  local found
  found="$(security find-identity -v -p codesigning 2>/dev/null \
    | grep 'Developer ID Application:' \
    | head -1 \
    | grep -o '"[^"]*"' \
    | tr -d '"')"
  if [ -z "$found" ]; then
    echo "Error: No Developer ID Application certificate in Keychain." >&2
    echo "Create one at https://developer.apple.com/account/resources/certificates/list" >&2
    echo "Then download/install it, or set DEVELOPER_ID_SIGNING_IDENTITY." >&2
    exit 1
  fi
  echo "$found"
}

IDENTITY="$(resolve_signing_identity)"
echo "Signing identity: $IDENTITY"

if [ ! -f "$ENTITLEMENTS" ]; then
  echo "Error: entitlements not found: $ENTITLEMENTS" >&2
  exit 1
fi

echo "Re-signing nested binaries..."
# Deepest paths first so bundle signatures stay valid.
while IFS= read -r -d '' item; do
  if file "$item" 2>/dev/null | grep -qE 'Mach-O|executable'; then
    codesign --force --options runtime --timestamp \
      --sign "$IDENTITY" "$item" 2>/dev/null || true
  fi
done < <(find "$APP_PATH/Contents" -type f \( -name "*.dylib" -o -perm -111 \) -print0 | sort -rz)

while IFS= read -r -d '' fw; do
  codesign --force --options runtime --timestamp \
    --sign "$IDENTITY" "$fw" 2>/dev/null || true
done < <(find "$APP_PATH/Contents/Frameworks" -maxdepth 1 -name "*.framework" -print0 2>/dev/null | sort -rz)

echo "Signing app bundle..."
codesign --force --options runtime --timestamp \
  --entitlements "$ENTITLEMENTS" \
  --sign "$IDENTITY" \
  "$APP_PATH"

echo "Verifying signature..."
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

if [ "${SKIP_NOTARIZE:-0}" = "1" ]; then
  echo "SKIP_NOTARIZE=1 — not submitting to Apple notary."
  spctl -a -vv "$APP_PATH" || true
  exit 0
fi

NOTARY_ZIP="$(mktemp -t flofile_notarize).zip"
trap 'rm -f "$NOTARY_ZIP"' EXIT

echo "Zipping for notarization..."
ditto -c -k --keepParent "$APP_PATH" "$NOTARY_ZIP"

echo "Submitting to Apple notary (profile: $NOTARY_PROFILE)..."
xcrun notarytool submit "$NOTARY_ZIP" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait

echo "Stapling notarization ticket..."
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"

echo "Gatekeeper assessment:"
spctl -a -vv "$APP_PATH"

echo "Done: $APP_PATH is signed and notarized."
