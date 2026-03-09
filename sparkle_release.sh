#!/bin/bash
# One-command Sparkle release: build, zip, sign (Keychain), update appcast, copy zip for GitHub Pages.
# Usage: ./sparkle_release.sh [version]
#   version: e.g. 1.0.1 (default: from pubspec.yaml)
#
# Requires:
#   - Flutter, Xcode, exiftool (brew)
#   - Sparkle sign_update: uses Keychain only (sign_update -p). Never uses .sparkle_private_key or SPARKLE_PRIVATE_KEY.
#     Set SIGN_UPDATE to the path to sign_update if not using tools/bin/sign_update.
#
# Optional: gh + auth to create a GitHub release. Zip is served from GitHub Pages.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

VERSION_ARG="${1:-}"
if [ -n "$VERSION_ARG" ]; then
  VERSION="$VERSION_ARG"
else
  VERSION=$(grep '^version:' pubspec.yaml | sed 's/version: *//' | tr -d '\r\n')
  [ -z "$VERSION" ] && VERSION="1.0.0"
fi

SHORT_VERSION="$VERSION"
SPARKLE_VERSION="${SPARKLE_VERSION:-$(echo "$VERSION" | sed 's/[^0-9]//g')}"
[ -z "$SPARKLE_VERSION" ] && SPARKLE_VERSION="1"

APP_NAME="FloFile Beta"
APP_PATH="build/macos/Build/Products/Release/${APP_NAME}.app"
ZIP_NAME="FloFileBeta.zip"
RELEASE_DIR="build/release"
ZIP_PATH="$RELEASE_DIR/$ZIP_NAME"
APPCAST_PATH="docs/appcast.xml"
PAGES_BASE="https://mblinch.github.io/flofile_clean"
PAGES_ZIP_URL="${PAGES_BASE}/releases/v${SHORT_VERSION}/${ZIP_NAME}"
DOCS_RELEASE_DIR="docs/releases/v${SHORT_VERSION}"
DOCS_ZIP_PATH="${DOCS_RELEASE_DIR}/${ZIP_NAME}"

# Path to sign_update (Keychain is used; no private key file)
SIGN_UPDATE="${SIGN_UPDATE:-$SCRIPT_DIR/tools/bin/sign_update}"

echo "=== Sparkle release: $SHORT_VERSION (build $SPARKLE_VERSION) ==="
echo ""

# 1) Icons (required so every release zip has current app icon)
if [ -f "generate_icons.sh" ]; then
  ./generate_icons.sh
fi

# 2) Build
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

# 4) Zip
mkdir -p "$RELEASE_DIR"
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"
ZIP_BYTES=$(stat -f%z "$ZIP_PATH" 2>/dev/null || stat -c%s "$ZIP_PATH" 2>/dev/null)
echo "Zip: $ZIP_PATH ($ZIP_BYTES bytes)"

# 5) Sign with Sparkle (Keychain; no key file)
ED_SIGNATURE=""
if [ -x "$SIGN_UPDATE" ]; then
  echo "Signing with Sparkle (Keychain)..."
  ED_SIGNATURE=$("$SIGN_UPDATE" -p "$ZIP_PATH" 2>/dev/null | tr -d '\n\r')
  if [ -z "$ED_SIGNATURE" ]; then
    echo "Error: sign_update produced no signature. Ensure your Sparkle key is in the Keychain (run generate_keys if needed)." >&2
    exit 1
  fi
  echo "Signed for Sparkle."
else
  echo "Error: sign_update not found at $SIGN_UPDATE. Set SIGN_UPDATE to your sign_update path or install Sparkle tools in tools/." >&2
  exit 1
fi

ENCLOSURE_ATTR="length=\"$ZIP_BYTES\" sparkle:edSignature=\"$ED_SIGNATURE\""

# 6) Update appcast: insert new item after </language> (newest first)
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
        ${ENCLOSURE_ATTR} />
    </item>
ENCLOSURE

if [ -f "$APPCAST_PATH" ]; then
  sed -e "/<\/language>/r $NEW_ITEM_FILE" "$APPCAST_PATH" > "$APPCAST_PATH.tmp" && mv "$APPCAST_PATH.tmp" "$APPCAST_PATH"
  echo "Updated $APPCAST_PATH"
fi

# 7) Copy zip to docs/releases/vX.Y.Z/ for GitHub Pages
mkdir -p "$DOCS_RELEASE_DIR"
cp "$ZIP_PATH" "$DOCS_ZIP_PATH"
echo "Copied zip to $DOCS_ZIP_PATH (commit + push to publish on Pages)"

# 8) Optional: GitHub release
if command -v gh >/dev/null 2>&1 && [ "${SPARKLE_SKIP_GH_RELEASE:-0}" != "1" ]; then
  if gh release view "v${SHORT_VERSION}" --repo mblinch/flofile_clean 2>/dev/null; then
    echo "Release v${SHORT_VERSION} already exists; skipping gh release create."
  else
    gh release create "v${SHORT_VERSION}" "$ZIP_PATH" \
      --repo mblinch/flofile_clean \
      --title "FloFile Beta ${SHORT_VERSION}" \
      --notes "Sparkle update ${SHORT_VERSION}. Download also at ${PAGES_ZIP_URL}"
    echo "Created GitHub release v${SHORT_VERSION}"
  fi
fi

echo ""
echo "Next: commit and push docs/appcast.xml and docs/releases/"
echo "  git add docs/appcast.xml docs/releases/ && git commit -m 'Release ${SHORT_VERSION}' && git push origin main"
echo "Done."
