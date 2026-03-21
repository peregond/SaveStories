#!/bin/zsh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE_NAME="SaveStories"
BUILD_DIR="$ROOT/dist"
RELEASE_DIR="$BUILD_DIR/release"
APP_DIR="$RELEASE_DIR/$BUNDLE_NAME.app"
APP_ZIP="$RELEASE_DIR/$BUNDLE_NAME-notary.zip"
DMG_PATH="$RELEASE_DIR/$BUNDLE_NAME.dmg"
TEMP_DMG_PATH="$RELEASE_DIR/$BUNDLE_NAME-$RANDOM.tmp.dmg"
STAGING_DIR="$BUILD_DIR/dmg-staging"
RW_DMG_PATH="$RELEASE_DIR/$BUNDLE_NAME-layout.dmg"
BACKGROUND_DIR="$STAGING_DIR/.background"
BACKGROUND_SVG="$BACKGROUND_DIR/background.svg"
BACKGROUND_PNG="$BACKGROUND_DIR/background.png"
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
mkdir -p "$BACKGROUND_DIR"
cp -R "$APP_DIR" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"
python3 "$ROOT/packaging/generate_dmg_background.py" "$BACKGROUND_SVG"

if command -v qlmanage >/dev/null 2>&1; then
  qlmanage -t -s 1200 -o "$BACKGROUND_DIR" "$BACKGROUND_SVG" >/dev/null 2>&1 || true
  if [ -f "$BACKGROUND_DIR/background.svg.png" ]; then
    mv -f "$BACKGROUND_DIR/background.svg.png" "$BACKGROUND_PNG"
  fi
fi

if [ ! -f "$BACKGROUND_PNG" ] && command -v sips >/dev/null 2>&1; then
  sips -s format png "$BACKGROUND_SVG" --out "$BACKGROUND_PNG" >/dev/null 2>&1 || true
fi

rm -f "$DMG_PATH"
rm -f "$TEMP_DMG_PATH"
rm -f "$RW_DMG_PATH"
hdiutil create \
  -volname "$BUNDLE_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDRW \
  "$RW_DMG_PATH"

MOUNT_POINT="/Volumes/$BUNDLE_NAME"
ATTACH_OUTPUT="$(hdiutil attach "$RW_DMG_PATH" -noverify -noautoopen -mountpoint "$MOUNT_POINT")"
DEVICE="$(printf '%s\n' "$ATTACH_OUTPUT" | awk -v mount="$MOUNT_POINT" '$0 ~ mount {print $1; exit}')"

if [ -n "$DEVICE" ] && [ -d "$MOUNT_POINT" ]; then
  osascript <<EOF >/dev/null
tell application "Finder"
  tell disk "$BUNDLE_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set sidebar width of container window to 0
    set bounds of container window to {140, 140, 1080, 720}
    set theViewOptions to the icon view options of container window
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to 144
    set text size of theViewOptions to 15
    if exists file ".background:background.png" of container window then
      set background picture of theViewOptions to file ".background:background.png"
    end if
    set position of item "$BUNDLE_NAME.app" of container window to {378, 306}
    set position of item "Applications" of container window to {566, 306}
    close
    open
    update without registering applications
    delay 1
  end tell
end tell
EOF
fi

if [ -n "$DEVICE" ]; then
  hdiutil detach "$DEVICE" -force >/dev/null
else
  hdiutil detach "$MOUNT_POINT" -force >/dev/null
fi
hdiutil convert "$RW_DMG_PATH" -format UDZO -o "$TEMP_DMG_PATH" >/dev/null
rm -f "$RW_DMG_PATH"
mv -f "$TEMP_DMG_PATH" "$DMG_PATH"

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
