#!/bin/zsh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE_NAME="SaveStories"
BUILD_DIR="$ROOT/beta-build"
RELEASE_DIR="$BUILD_DIR/release"
APP_DIR="$RELEASE_DIR/$BUNDLE_NAME.app"
DMG_PATH="$RELEASE_DIR/$BUNDLE_NAME-beta.dmg"
STAGING_DIR="$BUILD_DIR/dmg-staging"

"$ROOT/scripts/build_beta_app.sh"

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -R "$APP_DIR" "$STAGING_DIR/"

rm -f "$DMG_PATH"
hdiutil create \
  -volname "$BUNDLE_NAME Beta" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

printf '\nDMG created at:\n%s\n' "$DMG_PATH"
