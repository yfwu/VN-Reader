#!/usr/bin/env bash
# Runs the UI test suite on one simulator and exports screenshots + a summary.
#   scripts/test-ui.sh <simulator-udid> <output-dir> [derived-data-from-build-for-testing]
set -uo pipefail
UDID="$1"; OUT="$2"; DD="${3:-}"
mkdir -p "$OUT"
RESULT="$OUT/ui.xcresult"
rm -rf "$RESULT"
# Boot and wait first: a cold simulator can time out the first app launch.
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || true
COMMON=(-destination "id=$UDID" -resultBundlePath "$RESULT" -retry-tests-on-failure -test-iterations 2
        -test-timeouts-enabled YES -default-test-execution-time-allowance 300 -maximum-test-execution-time-allowance 420)
if [[ -n "$DD" ]]; then
  xcodebuild test-without-building -project VNReader.xcodeproj -scheme VNReader -derivedDataPath "$DD" "${COMMON[@]}" \
    2>&1 | tee "$OUT/xcodebuild.log" | grep -E '^(Test Suite|Test Case|.*error:|.*XCTAssert|\*\* )'
else
  xcodebuild test -project VNReader.xcodeproj -scheme VNReader -configuration Debug CODE_SIGNING_ALLOWED=NO "${COMMON[@]}" \
    2>&1 | tee "$OUT/xcodebuild.log" | grep -E '^(Test Suite|Test Case|.*error:|.*XCTAssert|\*\* )'
fi
STATUS=${PIPESTATUS[0]}
xcrun xcresulttool export attachments --path "$RESULT" --output-path "$OUT/attachments" >/dev/null 2>&1 \
  && /usr/bin/python3 scripts/ci/rename_attachments.py "$OUT/attachments" || echo "attachment export failed"
# Failure context in the job log (artifacts may not be downloadable everywhere).
if [[ $STATUS -ne 0 ]]; then
  for f in "$OUT"/attachments/App\ UI\ hierarchy*.txt; do
    [[ -f "$f" ]] || continue
    echo "===== $(basename "$f") ====="; head -c 6000 "$f"; echo
  done
fi
xcrun xcresulttool get test-results summary --path "$RESULT" > "$OUT/summary.json" 2>/dev/null || true
xcrun xcresulttool get test-results tests --path "$RESULT" > "$OUT/tests.json" 2>/dev/null || true
exit $STATUS
