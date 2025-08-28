#!/bin/bash

# Build DMG script for FloFile Beta
# Usage: ./build_dmg.sh [version_suffix]

set -e

# Get version suffix from command line or use timestamp
VERSION_SUFFIX=${1:-$(date +"%Y%m%d_%H%M%S")}

echo "Building FloFile Beta DMG with version suffix: $VERSION_SUFFIX"

# Create build_dmgs directory if it doesn't exist
mkdir -p build_dmgs

# Build the macOS app
echo "Building macOS app..."
flutter build macos --release

# Bundle ExifTool Perl libraries into the app (so DMG works offline)
APP_PATH="build/macos/Build/Products/Release/FloFile Beta.app"
RES_DIR="$APP_PATH/Contents/Resources"
echo "Copying ExifTool Perl libs into: $RES_DIR/exiftool_lib"

# Try to locate Homebrew exiftool prefix
EXIF_PREFIX="$(brew --prefix exiftool 2>/dev/null || true)"
if [ -z "$EXIF_PREFIX" ]; then
  # Fallback: find latest versioned Cellar path
  EXIF_PREFIX="$(ls -d /opt/homebrew/Cellar/exiftool/* 2>/dev/null | sort -V | tail -1 || true)"
fi

LIB_SRC="$EXIF_PREFIX/libexec/lib/perl5"
if [ -d "$LIB_SRC" ]; then
  mkdir -p "$RES_DIR/exiftool_lib"
  # Copy both the generic and arch-specific subfolders
  rsync -a "$LIB_SRC/" "$RES_DIR/exiftool_lib/"
  echo "Copied ExifTool libs from: $LIB_SRC"
else
  echo "WARNING: Could not find ExifTool Perl libs at: $LIB_SRC"
  echo "         Ensure exiftool is installed on the build machine before packaging."
fi

# Create DMG filename
DMG_NAME="FloFile_Beta_${VERSION_SUFFIX}.dmg"
DMG_PATH="build_dmgs/$DMG_NAME"

echo "Creating DMG: $DMG_PATH"

# Create the DMG with better icon positioning
create-dmg \
  --volname "FloFile Beta" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 128 \
  --icon "FloFile Beta.app" 150 150 \
  --hide-extension "FloFile Beta.app" \
  --app-drop-link 450 150 \
  --no-internet-enable \
  --format UDZO \
  "$DMG_PATH" \
  "build/macos/Build/Products/Release/"

echo "✅ DMG created successfully: $DMG_PATH"
echo "📁 DMG size: $(du -h "$DMG_PATH" | cut -f1)"
