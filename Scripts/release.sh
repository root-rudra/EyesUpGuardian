#!/bin/bash
# Builds a distributable EyesUpGuardian.dmg.
#
# With no signing identity it produces an ad-hoc signed build: anyone downloading it has to
# right-click → Open once. Set DEVELOPER_ID (and NOTARY_PROFILE) to sign and notarize instead —
# no other change is needed.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(plutil -extract CFBundleShortVersionString raw Sources/EyesUpApp/Resources/Info.plist)"
APP="build/EyesUpGuardian.app"
DMG="build/EyesUpGuardian-$VERSION.dmg"

make app

if [ -n "${DEVELOPER_ID:-}" ]; then
    echo "Signing with: $DEVELOPER_ID"
    codesign --force --deep --options runtime --timestamp --sign "$DEVELOPER_ID" "$APP"
    codesign --verify --strict --verbose=2 "$APP"
else
    echo "No DEVELOPER_ID set — shipping the ad-hoc signature."
fi

rm -f "$DMG"
STAGING="$(mktemp -d)"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "EyesUpGuardian" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
rm -rf "$STAGING"

if [ -n "${NOTARY_PROFILE:-}" ]; then
    echo "Notarizing…"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
fi

echo "Built $DMG"
shasum -a 256 "$DMG"
