#!/bin/bash
# Sparkle release: build, zip, sign from Keychain only, copy to docs/FloFileBeta.zip, update appcast.
# Usage: ./sparkle_release.sh [version]
#
# Apple signing: tool/macos_sign_and_notarize.sh (Developer ID + notarize + staple)
# Sparkle signing: Keychain only (sign_update -p). Set SIGN_UPDATE to override path.
# One-time notary setup:
#   xcrun notarytool store-credentials "flofile-notarize" \
#     --apple-id "you@example.com" --team-id "YOUR_TEAM_ID" \
#     --password "app-specific-password"
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Prefer pubspec `x.y.z+build` so Sparkle build matches CFBundleVersion (not 1013 from "1.0.13").
VERSION_ARG="${1:-}"
PUBSPEC_VER=$(grep '^version:' pubspec.yaml | sed 's/version: *//' | tr -d '\r\n')
[ -z "$PUBSPEC_VER" ] && PUBSPEC_VER="1.0.0+1"

if [ -n "$VERSION_ARG" ]; then
  if [[ "$VERSION_ARG" == *+* ]]; then
    VERSION="$VERSION_ARG"
  elif [[ "$PUBSPEC_VER" == "$VERSION_ARG"+* ]]; then
    VERSION="$PUBSPEC_VER"
  else
    VERSION="$VERSION_ARG"
  fi
else
  VERSION="$PUBSPEC_VER"
fi
[ -z "$VERSION" ] && VERSION="1.0.0+1"

SHORT_VERSION="${VERSION%%+*}"
if [[ "$VERSION" == *+* ]]; then
  SPARKLE_VERSION="${SPARKLE_VERSION:-${VERSION#*+}}"
else
  SPARKLE_VERSION="${SPARKLE_VERSION:-$(echo "$SHORT_VERSION" | sed 's/[^0-9]//g')}"
fi
[ -z "$SPARKLE_VERSION" ] && SPARKLE_VERSION="1"

APP_NAME="FloFile Beta"
APP_PATH="build/macos/Build/Products/Release/${APP_NAME}.app"
ZIP_NAME="FloFileBeta.zip"
RELEASE_DIR="build/release"
ZIP_PATH="$RELEASE_DIR/$ZIP_NAME"
APPCAST_PATH="docs/appcast.xml"
PAGES_BASE="https://mblinch.github.io/flofile_clean"
# Single zip URL for GitHub Pages (zip lives at docs/FloFileBeta.zip)
PAGES_ZIP_URL="${PAGES_BASE}/FloFileBeta.zip"
DOCS_ZIP_PATH="docs/FloFileBeta.zip"

# sign_update: DerivedData if found, else tools/bin; override with SIGN_UPDATE
DERIVED_SIGN_UPDATE=$(find ~/Library/Developer/Xcode/DerivedData -name sign_update -type f 2>/dev/null | head -1)
SIGN_UPDATE="${SIGN_UPDATE:-${DERIVED_SIGN_UPDATE:-$SCRIPT_DIR/tools/bin/sign_update}}"

echo "=== Sparkle release: $SHORT_VERSION (build $SPARKLE_VERSION) ==="
echo ""

# 1) Icons (force app icon refresh in build)
if [ -f "generate_icons.sh" ]; then
  ./generate_icons.sh
fi
# Touch appiconset so Xcode doesn't use a cached icon
touch "macos/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json" 2>/dev/null || true

# 2) Build
# Apply the GTMAppAuth keychain patch first so Google Sign-In works on macOS 26
# Developer ID builds (file-based login keychain, no provisioning profile needed).
# Must run BEFORE flutter build since the Swift packages compile during the build.
if [ -f "$SCRIPT_DIR/tool/patch_gtm_keychain.sh" ]; then
  "$SCRIPT_DIR/tool/patch_gtm_keychain.sh" || true
fi
echo "Building macOS app..."
flutter build macos --release --build-name="$SHORT_VERSION" --build-number="$SPARKLE_VERSION"

# 3) ExifTool libs
RES_DIR="$APP_PATH/Contents/Resources"
EXIF_PREFIX="$(brew --prefix exiftool 2>/dev/null || true)"
[ -z "$EXIF_PREFIX" ] && EXIF_PREFIX="$(ls -d /opt/homebrew/Cellar/exiftool/* 2>/dev/null | sort -V | tail -1 || true)"
LIB_SRC="${EXIF_PREFIX}/libexec/lib/perl5"
if [ -d "$LIB_SRC" ]; then
  mkdir -p "$RES_DIR/exiftool_lib"
  rsync -a "$LIB_SRC/" "$RES_DIR/exiftool_lib/"
fi

# 4) Developer ID sign + notarize (required for distribution outside App Store)
echo "Signing and notarizing with Developer ID..."
"$SCRIPT_DIR/tool/macos_sign_and_notarize.sh" "$APP_PATH"

# 5) Zip (this exact zip is Sparkle-signed and copied to docs/)
mkdir -p "$RELEASE_DIR"
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"
ZIP_BYTES=$(stat -f%z "$ZIP_PATH" 2>/dev/null || stat -c%s "$ZIP_PATH" 2>/dev/null)
echo "Zip: $ZIP_PATH ($ZIP_BYTES bytes)"

# 6) Sign with Keychain only (sign_update -p on that exact zip)
if [ ! -x "$SIGN_UPDATE" ]; then
  echo "Error: sign_update not found at $SIGN_UPDATE. Set SIGN_UPDATE to your path (e.g. DerivedData)." >&2
  exit 1
fi
echo "Signing with Sparkle (Keychain)..."
ED_SIGNATURE=$("$SIGN_UPDATE" -p "$ZIP_PATH" 2>/dev/null | tr -d '\n\r')
if [ -z "$ED_SIGNATURE" ]; then
  echo "Error: sign_update produced no signature. Keychain key must match SUPublicEDKey in Info.plist." >&2
  exit 1
fi
echo "Signed for Sparkle."

# 7) Copy that exact same signed zip to docs/FloFileBeta.zip
cp "$ZIP_PATH" "$DOCS_ZIP_PATH"
echo "Copied zip to $DOCS_ZIP_PATH"

# 8) Update appcast: insert new item after </language> with exact length and sparkle:edSignature
PUB_DATE=$(date -u +"%a, %d %b %Y %H:%M:%S %z")
NEW_ITEM_FILE="$RELEASE_DIR/appcast_item.xml"
mkdir -p "$RELEASE_DIR"
cat > "$NEW_ITEM_FILE" << ENCLOSURE
    <item>
      <title>Version ${SHORT_VERSION}</title>
      <pubDate>${PUB_DATE}</pubDate>
      <sparkle:version>${SPARKLE_VERSION}</sparkle:version>
      <sparkle:shortVersionString>${SHORT_VERSION}</sparkle:shortVersionString>
      <enclosure
        url="${PAGES_ZIP_URL}"
        type="application/octet-stream"
        length="${ZIP_BYTES}" sparkle:edSignature="${ED_SIGNATURE}" />
    </item>
ENCLOSURE

if [ -f "$APPCAST_PATH" ]; then
  sed -e "/<\/language>/r $NEW_ITEM_FILE" "$APPCAST_PATH" > "$APPCAST_PATH.tmp" && mv "$APPCAST_PATH.tmp" "$APPCAST_PATH"
  echo "Updated $APPCAST_PATH"
fi

echo ""
echo "Next: review, then commit and push docs/appcast.xml and docs/FloFileBeta.zip"
echo "  git add docs/appcast.xml docs/FloFileBeta.zip && git commit -m 'Release ${SHORT_VERSION}' && git push origin main"
echo "Done."
