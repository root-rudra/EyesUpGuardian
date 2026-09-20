#!/bin/bash
# Assembles build/EyesUpGuardian.app from the SwiftPM binary and ad-hoc signs it with Hardened Runtime.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP="build/EyesUpGuardian.app"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/EyesUpGuardian" "$APP/Contents/MacOS/EyesUpGuardian"
cp Sources/EyesUpApp/Resources/Info.plist "$APP/Contents/Info.plist"
cp Sources/EyesUpApp/Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --options runtime --sign - "$APP"
codesign --verify --strict "$APP"
echo "Built $APP"
