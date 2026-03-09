#!/bin/bash
# Build macOS release zip for Sparkle and optionally upload to GitHub Releases.
# Usage: ./build_release.sh [version]
#   version: e.g. 1.0.1 (default: from pubspec.yaml)
#
# For signing (required for Sparkle): set SPARKLE_PRIVATE_KEY to your private key,
# and optionally SIGN_UPDATE to path to sign_update (default: tools/sparkle/bin/sign_update).
#
# For upload: GitHub CLI must be installed and logged in (gh auth login).
#   ./build_release.sh 1.0.1   # build + zip + sign + update appcast + create release & upload

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Version: arg, or from pubspec, or default
VERSION_ARG="${1:-}"
if [ -n "$VERSION_ARG" ]; then
  VERSION="$VERSION_ARG"
else
  VERSION=$(grep '^version:' pubspec.yaml | sed 's/version: *//' | tr -d '\r\n')
  [ -z "$VERSION" ] && VERSION="1.0.0"
fi

SHORT_VERSION="$VERSION"
# Sparkle version is integer (e.g. 2 for 1.0.1 -> 101 or 2)
SPARKLE_VERSION="${SPARKLE_VERSION:-$(echo "$VERSION" | sed 's/[^0-9]//g')}"
[ -z "$SPARKLE_VERSION" ] && SPARKLE_VERSION="1"

APP_NAME="FloFile Beta"
APP_PATH="build/macos/Build/Products/Release/${APP_NAME}.app"
ZIP_NAME="FloFileBeta.zip"
RELEASE_DIR="build/release"
ZIP_PATH="$RELEASE_DIR/$ZIP_NAME"
APPCAST_PATH="docs/appcast.xml"
BASE_URL="https://github.com/mblinch/flofile_clean/releases/download"

echo "=== FloFile Beta Release ==="
echo "Version: $SHORT_VERSION (Sparkle: $SPARKLE_VERSION)"
echo ""

# 1) Icons (optional)
if [ -f "generate_icons.sh" ]; then
  echo "Generating icons..."
  ./generate_icons.sh || true
fi

# 2) Build macOS app
echo "Building macOS app..."
flutter build macos --release --build-name="$SHORT_VERSION" --build-number="$SPARKLE_VERSION"

# 3) Bundle ExifTool libs (same as build_dmg.sh)
RES_DIR="$APP_PATH/Contents/Resources"
EXIF_PREFIX="$(brew --prefix exiftool 2>/dev/null || true)"
[ -z "$EXIF_PREFIX" ] && EXIF_PREFIX="$(ls -d /opt/homebrew/Cellar/exiftool/* 2>/dev/null | sort -V | tail -1 || true)"
LIB_SRC="${EXIF_PREFIX}/libexec/lib/perl5"
if [ -d "$LIB_SRC" ]; then
  mkdir -p "$RES_DIR/exiftool_lib"
  rsync -a "$LIB_SRC/" "$RES_DIR/exiftool_lib/"
  echo "Bundled ExifTool libs."
fi

# 4) Zip the .app
mkdir -p "$RELEASE_DIR"
rm -f "$ZIP_PATH"
echo "Creating $ZIP_PATH ..."
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"
ZIP_BYTES=$(stat -f%z "$ZIP_PATH" 2>/dev/null || stat -c%s "$ZIP_PATH" 2>/dev/null)
echo "Zip size: $ZIP_BYTES bytes"

# 5) Sign for Sparkle (if key set)
ED_SIGNATURE=""
if [ -n "$SPARKLE_PRIVATE_KEY" ]; then
  SIGN_UPDATE="${SIGN_UPDATE:-$SCRIPT_DIR/tools/sparkle/bin/sign_update}"
  if [ -x "$SIGN_UPDATE" ]; then
    echo "Signing zip for Sparkle..."
    ED_SIGNATURE=$("$SIGN_UPDATE" "$ZIP_PATH" "$SPARKLE_PRIVATE_KEY")
    echo "Signature: ${ED_SIGNATURE:0:40}..."
  else
    echo "Warning: SIGN_UPDATE not found at $SIGN_UPDATE; skipping signing. Set SIGN_UPDATE or install Sparkle tools."
  fi
else
  echo "Warning: SPARKLE_PRIVATE_KEY not set; skipping signing. Enclosure will have no sparkle:edSignature."
fi

# 6) Update appcast.xml (new item at top)
if [ -n "$ED_SIGNATURE" ]; then
  ENCLOSURE_ATTR="length=\"$ZIP_BYTES\" sparkle:edSignature=\"$ED_SIGNATURE\""
else
  ENCLOSURE_ATTR="length=\"$ZIP_BYTES\""
fi
PUB_DATE=$(date -u +"%a, %d %b %Y %H:%M:%S %z")
ENCLOSURE_URL="${BASE_URL}/v${SHORT_VERSION}/${ZIP_NAME}"

# Write new item to temp file, then insert after </language>
NEW_ITEM_FILE="$RELEASE_DIR/appcast_item.xml"
mkdir -p "$RELEASE_DIR"
cat > "$NEW_ITEM_FILE" << ENCLOSURE
    <item>
      <title>Version ${SHORT_VERSION}</title>
      <pubDate>${PUB_DATE}</pubDate>
      <sparkle:version>${SPARKLE_VERSION}</sparkle:version>
      <sparkle:shortVersionString>${SHORT_VERSION}</sparkle:shortVersionString>
      <enclosure
        url="${ENCLOSURE_URL}"
        type="application/octet-stream"
        ${ENCLOSURE_ATTR} />
    </item>
ENCLOSURE

if [ -f "$APPCAST_PATH" ]; then
  sed -e "/<\/language>/r $NEW_ITEM_FILE" "$APPCAST_PATH" > "$APPCAST_PATH.tmp" && mv "$APPCAST_PATH.tmp" "$APPCAST_PATH"
  echo "Updated $APPCAST_PATH with version $SHORT_VERSION"
else
  echo "Warning: $APPCAST_PATH not found; appcast not updated."
fi

echo ""
echo "=== Release artifacts ==="
echo "  Zip: $ZIP_PATH"
echo "  Enclosure URL: $ENCLOSURE_URL"
echo ""

# 7) Upload via GitHub CLI (optional)
if command -v gh >/dev/null 2>&1; then
  echo "Create GitHub release and upload? (y/n)"
  read -r confirm
  if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
    gh release create "v${SHORT_VERSION}" "$ZIP_PATH" \
      --title "v${SHORT_VERSION}" \
      --notes "Release ${SHORT_VERSION}"
    echo "Release v${SHORT_VERSION} created and zip uploaded."
    echo "If appcast is served from this repo (e.g. gh-pages), commit and push docs/appcast.xml."
  fi
else
  echo "GitHub CLI (gh) not found. To upload: create release v${SHORT_VERSION} and upload $ZIP_PATH manually."
fi

echo "Done."
