#!/bin/bash

# Build DMG script for FloFile Beta
# Usage: ./build_dmg.sh [version_suffix]

set -e

# Get version suffix from command line or use timestamp
VERSION_SUFFIX=${1:-$(date +"%Y%m%d_%H%M%S")}

echo "Building FloFile Beta DMG with version suffix: $VERSION_SUFFIX"

# Create build_dmgs directory if it doesn't exist
mkdir -p build_dmgs

# Generate fresh rocket icons
echo "🚀 Generating rocket app icons..."
if [ -f "generate_icons.sh" ]; then
    ./generate_icons.sh
else
    echo "Warning: generate_icons.sh not found, using existing icons"
fi

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

echo "Creating clean DMG installer: $DMG_PATH"

# Remove any existing DMG with the same name
if [ -f "$DMG_PATH" ]; then
    echo "Removing existing DMG..."
    rm "$DMG_PATH"
fi

# Create the DMG with clean, professional layout
if [ -f "assets/images/dmg_background.png" ]; then
    BACKGROUND_ARG="--background assets/images/dmg_background.png"
else
    BACKGROUND_ARG=""
    echo "Note: DMG background not found, creating simple DMG"
fi

create-dmg \
  --volname "FloFile Beta" \
  --window-pos 200 120 \
  --window-size 540 360 \
  --icon-size 100 \
  --icon "FloFile Beta.app" 140 180 \
  --hide-extension "FloFile Beta.app" \
  --app-drop-link 400 180 \
  $BACKGROUND_ARG \
  --no-internet-enable \
  --format UDZO \
  "$DMG_PATH" \
  "build/macos/Build/Products/Release/"

echo "✅ DMG created successfully: $DMG_PATH"
echo "📁 DMG size: $(du -h "$DMG_PATH" | cut -f1)"
