# 🚀 FloFile Beta DMG Installer

This project creates a clean, professional DMG installer for FloFile Beta with a rocket app icon.

## Features

- **Clean Interface**: Shows only the app and Applications folder for easy drag-and-drop
- **Rocket Icon**: Beautiful rocket-themed app icon in all required sizes
- **Professional Layout**: Clean background with clear installation instructions
- **No Clutter**: Hides all unnecessary files and extensions

## Quick Build

```bash
# Make sure you have create-dmg installed
brew install create-dmg

# Build the DMG installer
./build_dmg.sh
```

## What Gets Created

1. **Rocket App Icons**: Generated in all required macOS sizes (16px to 1024px)
2. **Clean DMG Background**: Professional installer background with instructions
3. **Optimized Layout**: 
   - App icon positioned at (140, 180)
   - Applications folder link at (400, 180)
   - Window size: 540x360 pixels
   - Icon size: 100px

## Files Created

- `macos/Runner/Assets.xcassets/AppIcon.appiconset/` - All app icon sizes
- `assets/images/dmg_background.png` - DMG installer background
- `build_dmgs/FloFile_Beta_[timestamp].dmg` - Final installer

## Manual Icon Generation

If you want to just generate the icons without building:

```bash
./generate_icons.sh
```

## Requirements

- Flutter (for app building)
- `create-dmg` (for DMG creation): `brew install create-dmg`
- `librsvg` (for SVG to PNG conversion): `brew install librsvg`

## DMG Features

- **Volume Name**: "FloFile Beta"
- **Window Position**: Centered at (200, 120)
- **Compressed Format**: UDZO for smaller file size
- **No Internet Check**: Works offline
- **Hidden Extensions**: Clean appearance

The resulting DMG provides a professional installation experience where users simply drag the app to Applications!
