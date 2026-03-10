#!/bin/bash

# Generate app icons script
# Uses assets/images/app_icon_source.png (PNG) if present, else assets/images/rocket_icon_white_blue.svg

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "🚀 Generating rocket app icons..."

# Icon sizes needed for macOS app
SIZES=(16 32 64 128 256 512 1024)
ICON_DIR="macos/Runner/Assets.xcassets/AppIcon.appiconset"
mkdir -p "$ICON_DIR"

SOURCE_PNG="assets/images/app_icon_source.png"
SOURCE_SVG="assets/images/rocket_icon_white_blue.svg"

if [ -f "$SOURCE_PNG" ]; then
  echo "Using PNG source: $SOURCE_PNG"
  for size in "${SIZES[@]}"; do
    echo "Generating ${size}x${size} icon..."
    sips -z $size $size "$SOURCE_PNG" --out "$ICON_DIR/app_icon_${size}.png"
  done
elif [ -f "$SOURCE_SVG" ]; then
  if ! command -v rsvg-convert &> /dev/null; then
    echo "Installing rsvg-convert via Homebrew..."
    brew install librsvg
  fi
  echo "Using SVG source: $SOURCE_SVG"
  for size in "${SIZES[@]}"; do
    echo "Generating ${size}x${size} icon..."
    rsvg-convert -w $size -h $size "$SOURCE_SVG" -o "$ICON_DIR/app_icon_${size}.png"
  done
else
  echo "Error: need $SOURCE_PNG or $SOURCE_SVG" >&2
  exit 1
fi

echo "📱 Creating DMG background..."
# Generate DMG background
rsvg-convert -w 540 -h 360 assets/images/dmg_background.svg -o assets/images/dmg_background.png

echo "✅ All icons generated successfully!"
echo "📂 App icons saved to: $ICON_DIR"
echo "🖼️  DMG background saved to: assets/images/dmg_background.png"
