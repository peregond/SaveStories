#!/bin/zsh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="DimaSave"
BUILD_DIR="$ROOT/dist"
RELEASE_DIR="$BUILD_DIR/release"
APP_DIR="$RELEASE_DIR/$APP_NAME.app"
APP_ZIP="$RELEASE_DIR/$APP_NAME-notary.zip"
DMG_PATH="$RELEASE_DIR/$APP_NAME.dmg"
STAGING_DIR="$BUILD_DIR/dmg-staging"
SIGN_IDENTITY="${APPLE_SIGN_IDENTITY:-}"
NOTARY_PROFILE="${APPLE_NOTARY_PROFILE:-}"

"$ROOT/scripts/build_release_app.sh"

if [ -n "$NOTARY_PROFILE" ] && [ -z "$SIGN_IDENTITY" ]; then
  printf 'APPLE_NOTARY_PROFILE задан, но APPLE_SIGN_IDENTITY отсутствует.\n' >&2
  exit 1
fi

if [ -n "$NOTARY_PROFILE" ]; then
  rm -f "$APP_ZIP"
  ditto -c -k --keepParent "$APP_DIR" "$APP_ZIP"
  xcrun notarytool submit "$APP_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP_DIR"
fi

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -R "$APP_DIR" "$STAGING_DIR/"
python3 "$ROOT/packaging/generate_install_guide.py" "$STAGING_DIR"
ln -s /Applications "$STAGING_DIR/Applications"

rm -f "$DMG_PATH"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

if [ -n "$SIGN_IDENTITY" ]; then
  codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG_PATH"
  codesign --verify --verbose=2 "$DMG_PATH"
else
  codesign --force --sign - "$DMG_PATH"
  codesign --verify --verbose=2 "$DMG_PATH"
fi

if [ -n "$NOTARY_PROFILE" ]; then
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG_PATH"
fi

printf '\nRelease DMG created at:\n%s\n' "$DMG_PATH"
printf 'Signing identity: %s\n' "${SIGN_IDENTITY:-- (ad-hoc)}"
if [ -n "$NOTARY_PROFILE" ]; then
  printf 'Notarization: complete via keychain profile %s\n' "$NOTARY_PROFILE"
else
  printf 'Notarization: <not requested>\n'
fi
