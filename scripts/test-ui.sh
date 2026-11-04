#!/usr/bin/env bash
# Runs the UI test suite on one simulator and exports screenshots + a summary.
#   scripts/test-ui.sh <simulator-udid> <output-dir>
set -euo pipefail
UDID="$1"; OUT="$2"
mkdir -p "$OUT"
RESULT="$OUT/ui.xcresult"
rm -rf "$RESULT"
set +e
xcodebuild test -project VNReader.xcodeproj -scheme VNReader -configuration Debug \
  -destination "id=$UDID" -resultBundlePath "$RESULT" \
  CODE_SIGNING_ALLOWED=NO 2>&1 | tee "$OUT/xcodebuild.log" | grep -E '^(Test Suite|Test Case.*(passed|failed|skipped)|.*error:|\*\* )'
STATUS=${PIPESTATUS[0]}
set -e
# Screenshots (XCTAttachment) → PNG files.
if xcrun xcresulttool export attachments --help >/dev/null 2>&1; then
  xcrun xcresulttool export attachments --path "$RESULT" --output-path "$OUT/attachments" || true
  [[ -f "$OUT/attachments/manifest.json" ]] && /usr/bin/python3 scripts/ci/rename_attachments.py "$OUT/attachments" || true
fi
xcrun xcresulttool get test-results summary --path "$RESULT" > "$OUT/summary.json" 2>/dev/null || true
xcrun xcresulttool get test-results tests --path "$RESULT" > "$OUT/tests.json" 2>/dev/null || true
exit $STATUS
