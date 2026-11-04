#!/usr/bin/env bash
# CI only: copies screenshots (as JPEG), test summaries and the UNSIGNED IPA into the
# repository and pushes them to the current branch. Triggered manually
# by a commit whose message contains [publish]; normal pushes never create commits.
set -euo pipefail
A=artifacts
mkdir -p docs/screenshots docs/test-results/ci deliverables
for d in "$A"/ui-*/attachments; do
  [[ -d "$d" ]] || continue
  for f in "$d"/*.png; do
    [[ -f "$f" ]] || continue
    base=$(basename "$f" .png)
    sips -s format jpeg -s formatOptions 78 -Z 1600 "$f" --out "docs/screenshots/$base.jpg" >/dev/null
  done
done
cp "$A"/SUMMARY.md docs/test-results/ci/SUMMARY.md 2>/dev/null || true
for d in "$A"/ui-*; do
  [[ -f "$d/summary.json" ]] && cp "$d/summary.json" "docs/test-results/ci/$(basename "$d")-summary.json"
  [[ -f "$d/tests.json" ]] && cp "$d/tests.json" "docs/test-results/ci/$(basename "$d")-tests.json"
done
mkdir -p docs/test-results/ci/debug
rm -f docs/test-results/ci/debug/*.txt
for d in "$A"/ui-*/attachments; do
  for f in "$d"/App\ UI\ hierarchy*.txt; do
    [[ -f "$f" ]] && cp "$f" "docs/test-results/ci/debug/$(basename "$(dirname "$d")")-$(basename "$f" | tr ' ' '_')"
  done
done
grep -hE 'Executed .* tests' "$A"/core-macos.log | tail -1 > docs/test-results/ci/core-macos.txt || true
grep -hE '(Executed .* tests|\*\* TEST)' "$A"/core-ios.log | tail -2 > docs/test-results/ci/core-ios-simulator.txt || true
if ls "$A"/device/*.ipa >/dev/null 2>&1; then
  git rm -q --ignore-unmatch deliverables/*.ipa || true
  cp "$A"/device/*.ipa deliverables/
  cp "$A"/device/UNSIGNED-IPA-INFO.txt deliverables/
fi
{
  echo "Run: ${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"
  echo "Commit tested: ${GITHUB_SHA}"
  echo "Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > docs/test-results/ci/RUN.txt
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git add docs/screenshots docs/test-results/ci deliverables
git commit -qm "[ci] Publish screenshots, test results and UNSIGNED IPA from run ${GITHUB_RUN_ID}" || { echo "nothing to publish"; exit 0; }
BRANCH="${GITHUB_REF_NAME}"
for i in 1 2 3 4; do
  git pull -q --rebase origin "$BRANCH" && git push -q origin "HEAD:$BRANCH" && exit 0
  sleep $((i * 3))
done
echo "push failed" >&2; exit 1
