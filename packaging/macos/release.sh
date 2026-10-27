#!/bin/bash
# Builds Tickoff in Release, ad-hoc signs it and zips it to dist/Tickoff-<version>-macos-<arch>.zip.
# Usage: packaging/macos/release.sh   (run from anywhere)
# ARCHS="arm64"        builds for Apple Silicon only (the zip is named ...-macos-arm64.zip)
# ARCHS="arm64 x86_64" is the default: a universal app (the zip is named ...-macos-universal.zip)
set -euo pipefail
cd "$(dirname "$0")/../.."

ARCHS=${ARCHS:-"arm64 x86_64"}
ARCHIVE=build/Tickoff.xcarchive
APP=dist/Tickoff.app

VERSION=$(xcodebuild -project Tickoff.xcodeproj -scheme Tickoff -showBuildSettings 2>/dev/null \
    | awk '$1 == "MARKETING_VERSION" { print $3; exit }')
[ -n "$VERSION" ] || { echo "Could not read MARKETING_VERSION" >&2; exit 1; }

if [ "$ARCHS" = "arm64 x86_64" ] || [ "$ARCHS" = "x86_64 arm64" ]; then
    LABEL=universal
else
    LABEL=${ARCHS// /-}
fi

rm -rf "$ARCHIVE" dist
xcodebuild archive \
    -project Tickoff.xcodeproj -scheme Tickoff -configuration Release \
    -archivePath "$ARCHIVE" \
    ARCHS="$ARCHS" ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES \
    | tail -n 5

# There is no Developer ID, so "export" is just taking the app out of the archive.
mkdir -p dist
cp -R "$ARCHIVE/Products/Applications/Tickoff.app" "$APP"

# Ad-hoc signature: required for arm64 binaries to launch, but not a Developer ID.
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"

ZIP="dist/Tickoff-$VERSION-macos-$LABEL.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "Built $ZIP"
