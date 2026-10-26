#!/bin/bash
# Renders the app icon with Core Graphics and packs it into Packaging/AppIcon.icns.
set -euo pipefail
cd "$(dirname "$0")/.."
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
swift scripts/render-icon.swift "$WORK/AppIcon.iconset"
iconutil -c icns "$WORK/AppIcon.iconset" -o Packaging/AppIcon.icns
echo "Wrote Packaging/AppIcon.icns"
