#!/bin/bash

# Generate app icons script
# This script creates all the required icon sizes from the SVG rocket icon

set -e

echo "🚀 Generating rocket app icons..."

# Check if we have the required tools
if ! command -v rsvg-convert &> /dev/null; then
    echo "Installing rsvg-convert via Homebrew..."
    brew install librsvg
fi

# Icon sizes needed for macOS app
SIZES=(16 32 64 128 256 512 1024)
ICON_DIR="macos/Runner/Assets.xcassets/AppIcon.appiconset"

# Create the icon directory if it doesn't exist
mkdir -p "$ICON_DIR"

# Generate each icon size
for size in "${SIZES[@]}"; do
    echo "Generating ${size}x${size} icon..."
    rsvg-convert -w $size -h $size rocket_icon.svg -o "$ICON_DIR/app_icon_${size}.png"
done

echo "📱 Creating DMG background..."
# Generate DMG background
rsvg-convert -w 540 -h 360 assets/images/dmg_background.svg -o assets/images/dmg_background.png

echo "✅ All icons generated successfully!"
echo "📂 App icons saved to: $ICON_DIR"
echo "🖼️  DMG background saved to: assets/images/dmg_background.png"
