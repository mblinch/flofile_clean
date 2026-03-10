#!/bin/bash
# Force macOS to drop cached icon for FloFile Beta so the new logo shows.
set -e
APP_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/build/macos/Build/Products/Release/FloFile Beta.app"
if [ ! -d "$APP_PATH" ]; then
  echo "Run a release build first: flutter build macos --release"
  exit 1
fi
# Touch the app so Finder re-reads the bundle
touch "$APP_PATH"
# Restart Dock so it picks up the new icon
killall Dock 2>/dev/null || true
echo "Icon cache refreshed. Open the app from: $APP_PATH"
