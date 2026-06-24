#!/bin/bash
# Ensures a Mac App Development profile exists for debug builds.
#
# Flutter's macOS xcodebuild invocation does not pass -allowProvisioningUpdates
# (iOS does). The first debug build on a machine therefore fails until Xcode
# creates the profile once — this script does that step.
#
# Usage: ./tool/macos_provision_debug.sh
# Then: flutter run -d macos
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT/macos"

TEAM="$(grep '^DEVELOPMENT_TEAM' Runner/Configs/AppInfo.xcconfig | sed 's/.*= *//')"
echo "Provisioning debug profile (team: ${TEAM})..."

xcodebuild \
  -workspace Runner.xcworkspace \
  -scheme Runner \
  -configuration Debug \
  -allowProvisioningUpdates \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM="$TEAM" \
  -quiet

echo "Done. You can run: flutter run -d macos"
