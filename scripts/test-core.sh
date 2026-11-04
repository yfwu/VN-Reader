#!/usr/bin/env bash
# Runs ComicCore unit tests on the host (macOS or Linux) and, on macOS, on an iPad simulator.
#   scripts/test-core.sh [simulator-name]
set -euo pipefail
cd "$(dirname "$0")/../Packages/ComicCore"
swift test
if [[ "$(uname)" == "Darwin" ]]; then
  SIM="${1:-iPad mini (A17 Pro)}"
  xcodebuild test -scheme ComicCore -destination "platform=iOS Simulator,name=$SIM" | grep -E '(Test Suite|error:|\*\* TEST)'
fi
