#!/usr/bin/env bash
# Archives a signed Release build and exports or uploads it.
#
#   DEVELOPMENT_TEAM=ABCDE12345 scripts/archive-and-export.sh METHOD [output-dir] [ios|catalyst]
#   BUILD_NUMBER=6 scripts/archive-and-export.sh testflight build/ios-build-6 ios
#   BUILD_NUMBER=6 scripts/archive-and-export.sh testflight build/mac-build-6 catalyst
#
# METHOD: development, ad-hoc (iOS only), app-store-connect, or testflight.
# testflight uploads directly to App Store Connect; the other methods export locally.
# Uses the account signed into Xcode and Config/Signing.xcconfig (git-ignored).
# Each output directory is one immutable archive: choose a new directory to retry.
set -euo pipefail
METHOD="${1:-development}"
VN_PLATFORM="${3:-ios}"
case "$METHOD" in
  development|ad-hoc|app-store-connect|testflight) ;;
  *) echo "error: unsupported export method: $METHOD" >&2; exit 1 ;;
esac
case "$VN_PLATFORM" in
  ios) DESTINATION='generic/platform=iOS' ;;
  catalyst)
    DESTINATION='generic/platform=macOS,variant=Mac Catalyst'
    if [[ "$METHOD" == ad-hoc ]]; then
      echo "error: ad-hoc is an iOS distribution method; use development or app-store-connect for Catalyst" >&2
      exit 1
    fi
    ;;
  *) echo "error: platform must be ios or catalyst" >&2; exit 1 ;;
esac
OUT="${2:-build/export-$VN_PLATFORM-$METHOD}"
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
if [[ -e "$ARCHIVE" ]]; then
  echo "error: archive already exists: $ARCHIVE; choose a new output directory" >&2
  exit 1
fi
EXTRA=()
[[ -n "${VN_BUNDLE_ID:-}" ]] && EXTRA+=("VN_BUNDLE_ID=$VN_BUNDLE_ID")
[[ -n "${BUILD_NUMBER:-}" ]] && EXTRA+=("CURRENT_PROJECT_VERSION=$BUILD_NUMBER")
[[ -n "${VN_DERIVED_DATA:-}" ]] && EXTRA+=(-derivedDataPath "$VN_DERIVED_DATA")

xcodebuild archive -project VNReader.xcodeproj -scheme VNReader -configuration Release \
  -destination "$DESTINATION" -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic ${EXTRA[@]+"${EXTRA[@]}"} \
  2>&1 | tee "$OUT/archive.log" | grep -E '(error:|\*\* ARCHIVE)'

PLIST="$OUT/ExportOptions.plist"
sed "s/TEAM_ID_PLACEHOLDER/$TEAM/" "Config/ExportOptions-$METHOD.plist" > "$PLIST"
# Preserve the explicitly requested version for local exports as well as uploads.
/usr/libexec/PlistBuddy -c 'Set :manageAppVersionAndBuildNumber false' "$PLIST" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c 'Add :manageAppVersionAndBuildNumber bool false' "$PLIST"
# Xcode's /usr/bin/rsync starts whichever rsync is first on PATH; Homebrew's rejects its options.
PATH=/usr/bin:/bin:/usr/sbin:/sbin xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$OUT" -exportOptionsPlist "$PLIST" \
  -allowProvisioningUpdates 2>&1 | tee "$OUT/export.log" | grep -E '(error:|\*\* EXPORT)'

APP="$ARCHIVE/Products/Applications/VNReader.app"
if [[ "$VN_PLATFORM" == catalyst ]]; then
  APP_PLIST="$APP/Contents/Info.plist"
  MINIMUM_OS_KEY=LSMinimumSystemVersion
else
  APP_PLIST="$APP/Info.plist"
  MINIMUM_OS_KEY=MinimumOSVersion
fi
{
  echo "Platform: $VN_PLATFORM"
  echo "Archive: $ARCHIVE"
  echo "Signing: $METHOD, team $TEAM"
  echo "Bundle ID: $(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP_PLIST")"
  echo "Version: $(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP_PLIST") ($(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$APP_PLIST"))"
  echo "Minimum OS: $(/usr/libexec/PlistBuddy -c "Print $MINIMUM_OS_KEY" "$APP_PLIST")"
  echo "Signed by: $(codesign -dvv "$APP" 2>&1 | grep -E '^Authority' | head -1)"
  echo "Built with: $(xcodebuild -version | tr '\n' ' ')"
  echo "Install status: NOT YET VERIFIED ON A DEVICE"
} | tee "$OUT/BUILD-INFO.txt"
if [[ "$METHOD" == testflight ]]; then
  echo "Uploaded to App Store Connect; the build appears in TestFlight after processing."
else
  echo "Exported files: $OUT"
fi
