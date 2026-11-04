#!/usr/bin/env bash
# Builds a Release archive for real devices (arm64, iphoneos SDK) WITHOUT signing
# and packages it as an IPA explicitly marked UNSIGNED.
#
# An unsigned IPA cannot be installed on an iPad. It proves the code (including the
# C++ unrar library) compiles and links for the device platform; sign it via
# scripts/archive-and-export.sh once a Team is configured.
#   scripts/build-unsigned-ipa.sh [output-dir]
set -euo pipefail
OUT="${1:-build/device}"
mkdir -p "$OUT"
ARCHIVE="$OUT/VNReader-unsigned.xcarchive"
rm -rf "$ARCHIVE"
xcodebuild archive -project VNReader.xcodeproj -scheme VNReader -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | tee "$OUT/archive.log" | grep -E '(error:|warning: .*unrar|\*\* ARCHIVE)' || true
test "${PIPESTATUS[0]}" -eq 0
APP="$ARCHIVE/Products/Applications/VNReader.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$APP/Info.plist")
BUNDLE=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Info.plist")
MINOS=$(/usr/libexec/PlistBuddy -c 'Print MinimumOSVersion' "$APP/Info.plist")
STAGE=$(mktemp -d)
mkdir -p "$STAGE/Payload"
cp -R "$APP" "$STAGE/Payload/"
IPA="VNReader-${VERSION}-${BUILD}-UNSIGNED.ipa"
(cd "$STAGE" && /usr/bin/zip -qry "$IPA" Payload)
mv "$STAGE/$IPA" "$OUT/"
rm -rf "$STAGE"
{
  echo "File: $IPA"
  echo "Signing: UNSIGNED — cannot be installed on a device as-is"
  echo "Platform: iphoneos (arm64)"
  echo "Bundle ID: $BUNDLE"
  echo "Version: $VERSION ($BUILD)"
  echo "Minimum OS: $MINOS"
  echo "Archs: $(lipo -archs "$APP/VNReader")"
  echo "Built with: $(xcodebuild -version | tr '\n' ' ')"
  echo "SDK: $(xcrun --sdk iphoneos --show-sdk-version)"
  echo "Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "Commit: $(git rev-parse --short HEAD 2>/dev/null || echo n/a)"
  echo "Size: $(du -h "$OUT/$IPA" | cut -f1)"
} | tee "$OUT/UNSIGNED-IPA-INFO.txt"
