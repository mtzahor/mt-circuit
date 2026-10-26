#!/bin/bash
# Builds the release app and packages it as a drag-to-install disk image, named with the version
# in Packaging/Info.plist: build/MT-Circuit-<version>.dmg.
# Usage: scripts/package.sh
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Packaging/Info.plist)"
APP="build/MT Circuit.app"
DMG="build/MT-Circuit-$VERSION.dmg"
STAGING="build/dmg"

scripts/build-app.sh release

rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
# ditto keeps the bundle's code signature intact.
ditto "$APP" "$STAGING/MT Circuit.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "MT Circuit $VERSION" -srcfolder "$STAGING" -fs HFS+ -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"

echo "Packaged $DMG"
