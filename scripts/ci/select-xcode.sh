#!/usr/bin/env bash
# Selects the newest non-beta Xcode installed on a GitHub macOS runner
# (override with XCODE_PATH=/Applications/Xcode_16.4.app).
set -euo pipefail
if [[ -z "${XCODE_PATH:-}" ]]; then
  XCODE_PATH=$(ls -d /Applications/Xcode_*.app 2>/dev/null | grep -viE 'beta|_rc|release_candidate' | sort -V | tail -1)
fi
echo "Available:"; ls -d /Applications/Xcode*.app || true
echo "Selecting $XCODE_PATH"
sudo xcode-select -s "$XCODE_PATH/Contents/Developer"
xcodebuild -version
xcrun simctl list runtimes | grep -E 'iOS' || true
