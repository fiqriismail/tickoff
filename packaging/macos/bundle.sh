#!/bin/bash
# Builds a release binary and wraps it in dist/Tickoff.app, then zips it.
# Usage: packaging/macos/bundle.sh   (run from anywhere)
set -euo pipefail
cd "$(dirname "$0")/../.."

VERSION=$(grep -m1 '^version' Cargo.toml | cut -d'"' -f2)
ARCH=$(uname -m)
APP=dist/Tickoff.app

cargo build --release
rm -rf dist && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp target/release/Tickoff "$APP/Contents/MacOS/Tickoff"
cp packaging/macos/Tickoff.icns "$APP/Contents/Resources/Tickoff.icns"
sed "s/__VERSION__/$VERSION/g" packaging/macos/Info.plist > "$APP/Contents/Info.plist"

# Ad-hoc signature: required for arm64 binaries to launch, but not a Developer ID.
codesign --force --deep --sign - "$APP"

ZIP="dist/Tickoff-$VERSION-macos-$ARCH.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "Built $ZIP"
