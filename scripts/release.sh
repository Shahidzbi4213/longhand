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
if codesign -d --entitlements - "$APP_BUILD" 2>/dev/null | grep -q get-task-allow; then
  echo "✗ get-task-allow entitlement present; notarization would reject it"; exit 1
fi
codesign -dvv "$APP_BUILD" 2>&1 | grep -E "Authority=Developer ID Application|flags=.*runtime" >/dev/null \
  || { echo "✗ app is not Developer ID signed with hardened runtime"; exit 1; }

echo "▸ Packaging $DMG"
# Background art: Design/dmg-background.tiff (regenerate with: swift scripts/dmg-background.swift
# && tiffutil -cathidpicheck Design/dmg-background.png Design/dmg-background@2x.png -out Design/dmg-background.tiff)
command -v create-dmg >/dev/null || { echo "✗ needs create-dmg (brew install create-dmg)"; exit 1; }
STAGE=$(mktemp -d)
cp -R "$APP_BUILD" "$STAGE/longhand.app"
SetFile -a E "$STAGE/longhand.app" 2>/dev/null || true   # show "longhand", not "longhand.app"
create-dmg \
  --volname "longhand" \
  --background "Design/dmg-background.tiff" \
  --window-pos 200 140 \
  --window-size 660 400 \
  --icon-size 112 \
  --text-size 13 \
  --icon "longhand.app" 180 205 \
  --hide-extension "longhand.app" \
  --app-drop-link 480 205 \
  --no-internet-enable \
  "$DMG" "$STAGE" >/dev/null
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
