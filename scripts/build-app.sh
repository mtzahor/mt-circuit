#!/bin/bash
# Builds MTCircuit and wraps the executable in a macOS .app bundle at build/MT Circuit.app.
# Usage: scripts/build-app.sh [debug|release]   (default: release)
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
APP="build/MT Circuit.app"

swift build -c "$CONFIG" --product MTCircuit
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

if [[ ! -f Packaging/AppIcon.icns ]]; then
    scripts/make-icon.sh
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/MTCircuit" "$APP/Contents/MacOS/MTCircuit"
cp Packaging/Info.plist "$APP/Contents/Info.plist"
cp Packaging/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signature so the bundle launches cleanly on Apple silicon.
codesign --force --sign - "$APP" >/dev/null

echo "Built $APP"
