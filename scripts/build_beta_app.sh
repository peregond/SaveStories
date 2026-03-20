#!/bin/zsh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE_NAME="SaveStories"
EXECUTABLE_NAME="DimaSave"
ICON_BASENAME="DimaSave"
BUILD_DIR="$ROOT/beta-build"
RELEASE_DIR="$BUILD_DIR/release"
APP_DIR="$RELEASE_DIR/$BUNDLE_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICONSET_DIR="$BUILD_DIR/$ICON_BASENAME.iconset"
ICON_PATH="$BUILD_DIR/$ICON_BASENAME.icns"
STATIC_ICON_PATH="$ROOT/packaging/AppBundle/$ICON_BASENAME.icns"
RESOURCE_BUNDLE_NAME="$EXECUTABLE_NAME"_DimaSave.bundle

mkdir -p "$BUILD_DIR" "$RELEASE_DIR"

if [ -f "$STATIC_ICON_PATH" ]; then
  cp "$STATIC_ICON_PATH" "$ICON_PATH"
else
  python3 "$ROOT/packaging/generate_icon.py" "$ICONSET_DIR"
  iconutil --convert icns --output "$ICON_PATH" "$ICONSET_DIR"
fi

export CLANG_MODULE_CACHE_PATH="$BUILD_DIR/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$BUILD_DIR/swiftpm-module-cache"

swift build -c release --package-path "$ROOT"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$ROOT/packaging/AppBundle/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT/.build/release/$EXECUTABLE_NAME" "$MACOS_DIR/$EXECUTABLE_NAME"
cp "$ICON_PATH" "$RESOURCES_DIR/$ICON_BASENAME.icns"

RESOURCE_BUNDLE_PATH="$(find "$ROOT/.build" -maxdepth 4 -type d -name "$RESOURCE_BUNDLE_NAME" | head -n 1)"
if [ -n "$RESOURCE_BUNDLE_PATH" ] && [ -d "$RESOURCE_BUNDLE_PATH" ]; then
  cp -R "$RESOURCE_BUNDLE_PATH" "$RESOURCES_DIR/"
fi

printf '\nBeta app created at:\n%s\n' "$APP_DIR"
