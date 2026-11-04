#!/usr/bin/env bash
# Builds the app for the iOS Simulator (no signing needed) and optionally installs/launches it.
#   scripts/build-sim.sh ["iPad mini (A17 Pro)"]
set -euo pipefail
cd "$(dirname "$0")/.."
SIM="${1:-iPad mini (A17 Pro)}"
xcodebuild build -project VNReader.xcodeproj -scheme VNReader -configuration Debug \
  -destination "platform=iOS Simulator,name=$SIM" -derivedDataPath build/sim | grep -E '(error:|\*\* BUILD)'
APP=$(find build/sim/Build/Products -name VNReader.app -path '*iphonesimulator*' | head -1)
xcrun simctl boot "$SIM" 2>/dev/null || true
open -a Simulator || true
xcrun simctl install "$SIM" "$APP"
xcrun simctl launch "$SIM" "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Info.plist")"
