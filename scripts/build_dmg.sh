#!/bin/zsh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE_NAME="SaveStories"
BUILD_DIR="$ROOT/beta-build"
RELEASE_DIR="$BUILD_DIR/release"
APP_DIR="$RELEASE_DIR/$BUNDLE_NAME.app"
DMG_PATH="$RELEASE_DIR/$BUNDLE_NAME-beta.dmg"
STAGING_DIR="$BUILD_DIR/dmg-staging"
RW_DMG_PATH="$RELEASE_DIR/$BUNDLE_NAME-beta-layout.dmg"
BACKGROUND_DIR="$STAGING_DIR/.background"
BACKGROUND_SVG="$BACKGROUND_DIR/background.svg"
BACKGROUND_PNG="$BACKGROUND_DIR/background.png"

"$ROOT/scripts/build_beta_app.sh"

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
rm -f "$RW_DMG_PATH"
hdiutil create \
  -volname "$BUNDLE_NAME Beta" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDRW \
  "$RW_DMG_PATH"

MOUNT_POINT="/Volumes/$BUNDLE_NAME Beta"
ATTACH_OUTPUT="$(hdiutil attach "$RW_DMG_PATH" -noverify -noautoopen -mountpoint "$MOUNT_POINT")"
DEVICE="$(printf '%s\n' "$ATTACH_OUTPUT" | awk -v mount="$MOUNT_POINT" '$0 ~ mount {print $1; exit}')"

if [ -n "$DEVICE" ] && [ -d "$MOUNT_POINT" ]; then
  osascript <<EOF >/dev/null
tell application "Finder"
  tell disk "$BUNDLE_NAME Beta"
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
hdiutil convert "$RW_DMG_PATH" -format UDZO -o "$DMG_PATH" >/dev/null
rm -f "$RW_DMG_PATH"

printf '\nDMG created at:\n%s\n' "$DMG_PATH"
