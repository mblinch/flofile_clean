#!/usr/bin/env bash
# Run once after creating a Firebase project in the console.
# Prerequisites: Node/npm (for firebase-tools), Dart pub-cache bin on PATH.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$PATH:${PUB_CACHE:-$HOME/.pub-cache}/bin:/usr/local/bin"

if ! command -v firebase >/dev/null 2>&1; then
  echo "Installing Firebase CLI (npm)..."
  npm install -g firebase-tools
fi
if ! command -v flutterfire >/dev/null 2>&1; then
  echo "Installing FlutterFire CLI..."
  dart pub global activate flutterfire_cli
fi

echo "Log in to Google (browser will open if needed)..."
firebase login

# Default to your console project id; override: ./tool/complete_firebase_setup.sh my-other-project
PROJECT_ID="${1:-projectflo-e99c6}"
BUNDLE_ID="${2:-com.example.captionWriterFlutter}"

echo "Configuring FlutterFire for project: $PROJECT_ID (macOS + iOS bundle: $BUNDLE_ID)"
flutterfire configure -y \
  --platforms=macos,ios \
  --project="$PROJECT_ID" \
  --macos-bundle-id="$BUNDLE_ID" \
  --ios-bundle-id="$BUNDLE_ID" \
  --overwrite-firebase-options

echo "Fetching packages..."
dart pub get

echo ""
echo "Next: In Firebase Console → Build → Firestore → Create database."
echo "Then tighten Firestore rules before production."
echo "Done."
