#!/usr/bin/env bash
# Archives a signed Release build and exports an IPA.
#
#   DEVELOPMENT_TEAM=ABCDE12345 scripts/archive-and-export.sh [development|ad-hoc|app-store-connect|testflight] [output-dir]
#
# testflight uploads straight to App Store Connect instead of writing an IPA.
# Or put DEVELOPMENT_TEAM (and optionally VN_BUNDLE_ID) in Config/Signing.xcconfig.
# Uses automatic signing; Xcode must be signed in to an account of that team
# (Xcode ▸ Settings ▸ Accounts). -allowProvisioningUpdates lets xcodebuild create
# or refresh the provisioning profile and register connected devices.
set -euo pipefail
METHOD="${1:-development}"
OUT="${2:-build/export-$METHOD}"
cd "$(dirname "$0")/.."

TEAM="${DEVELOPMENT_TEAM:-}"
if [[ -z "$TEAM" && -f Config/Signing.xcconfig ]]; then
  TEAM=$(sed -nE 's/^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*([A-Z0-9]+).*/\1/p' Config/Signing.xcconfig | tail -1)
fi
if [[ -z "$TEAM" || "$TEAM" == "ABCDE12345" ]]; then
  echo "error: set DEVELOPMENT_TEAM (env or Config/Signing.xcconfig)" >&2
  exit 1
fi

mkdir -p "$OUT"
ARCHIVE="$OUT/VNReader.xcarchive"
rm -rf "$ARCHIVE"
EXTRA=()
[[ -n "${VN_BUNDLE_ID:-}" ]] && EXTRA+=("VN_BUNDLE_ID=$VN_BUNDLE_ID")
[[ -n "${BUILD_NUMBER:-}" ]] && EXTRA+=("CURRENT_PROJECT_VERSION=$BUILD_NUMBER")

xcodebuild archive -project VNReader.xcodeproj -scheme VNReader -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic ${EXTRA[@]+"${EXTRA[@]}"} | tee "$OUT/archive.log" | grep -E '(error:|\*\* ARCHIVE)'
test "${PIPESTATUS[0]}" -eq 0

PLIST="$OUT/ExportOptions.plist"
sed "s/TEAM_ID_PLACEHOLDER/$TEAM/" "Config/ExportOptions-$METHOD.plist" > "$PLIST"
# Xcode's /usr/bin/rsync starts whichever rsync is first on PATH; Homebrew's rejects its options.
PATH=/usr/bin:/bin:/usr/sbin:/sbin xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$OUT" -exportOptionsPlist "$PLIST" \
  -allowProvisioningUpdates | tee "$OUT/export.log" | grep -E '(error:|\*\* EXPORT)'
test "${PIPESTATUS[0]}" -eq 0

APP="$ARCHIVE/Products/Applications/VNReader.app"
IPA=$(find "$OUT" -maxdepth 1 -name '*.ipa' | head -1)
{
  echo "File: ${IPA:+$(basename "$IPA")}"
  echo "Signing: $METHOD, team $TEAM"
  echo "Bundle ID: $(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Info.plist")"
  echo "Version: $(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Info.plist") ($(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$APP/Info.plist"))"
  echo "Minimum OS: $(/usr/libexec/PlistBuddy -c 'Print MinimumOSVersion' "$APP/Info.plist")"
  echo "Signed by: $(codesign -dvv "$APP" 2>&1 | grep -E '^Authority' | head -1)"
  echo "Built with: $(xcodebuild -version | tr '\n' ' ')"
  echo "Install status: NOT YET VERIFIED ON A DEVICE"
} | tee "$OUT/IPA-INFO.txt"
if [[ "$METHOD" == testflight ]]; then
  echo "Uploaded to App Store Connect; the build appears in TestFlight after processing."
else
  echo "IPA: $IPA"
fi
