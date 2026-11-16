#!/bin/zsh
# Build, sign, package, notarize and staple longhand as a DMG.
#
#   scripts/release.sh            # full release (needs a notarytool keychain profile)
#   SKIP_NOTARIZE=1 scripts/release.sh
#
# One-time setup for notarization:
#   xcrun notarytool store-credentials "longhand-notary" --apple-id <you@example.com> --team-id 4DLAG2P9L6
set -euo pipefail
cd "$(dirname "$0")/.."

IDENTITY="Developer ID Application: Wajahat Karim (4DLAG2P9L6)"
PROFILE="${NOTARY_PROFILE:-longhand-notary}"
VERSION=$(awk '/MARKETING_VERSION/ {print $2}' project.yml)
DMG="dist/longhand-$VERSION.dmg"
APP_BUILD="build/release/Build/Products/Release/longhand.app"

echo "▸ longhand $VERSION"
rm -rf build/release dist && mkdir -p dist
xcodegen generate >/dev/null

echo "▸ Building Release (Developer ID, hardened runtime)"
xcodebuild -project Longhand.xcodeproj -scheme Longhand -configuration Release \
  -destination 'generic/platform=macOS' ONLY_ACTIVE_ARCH=NO \
  -derivedDataPath build/release -clonedSourcePackagesDirPath .build-pkgs build -quiet

codesign --verify --deep --strict --verbose=2 "$APP_BUILD"
echo "  architectures: $(lipo -archs "$APP_BUILD/Contents/MacOS/longhand")"
codesign -dvv "$APP_BUILD" 2>&1 | grep -E "Authority=Developer ID Application|flags=.*runtime" >/dev/null \
  || { echo "✗ app is not Developer ID signed with hardened runtime"; exit 1; }

echo "▸ Packaging $DMG"
STAGE=$(mktemp -d)
cp -R "$APP_BUILD" "$STAGE/longhand.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "longhand $VERSION" -srcfolder "$STAGE" -ov -format UDZO -fs HFS+ "$DMG" >/dev/null
rm -rf "$STAGE"
codesign --sign "$IDENTITY" --timestamp "$DMG"

if [[ -n "${SKIP_NOTARIZE:-}" ]]; then
  echo "✓ Signed (not notarized): $DMG"; exit 0
fi

echo "▸ Notarizing (this takes a few minutes)"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature --verbose "$DMG"
cp "$DMG" dist/longhand.dmg   # stable name for releases/latest/download/longhand.dmg
shasum -a 256 "$DMG"
echo "✓ Ready: $DMG (+ dist/longhand.dmg)"
