#!/bin/zsh

set -euo pipefail
setopt null_glob

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE_NAME="SaveStories"
EXECUTABLE_NAME="DimaSave"
ICON_BASENAME="DimaSave"
BUILD_DIR="$ROOT/dist"
RELEASE_DIR="$BUILD_DIR/release"
APP_DIR="$RELEASE_DIR/$BUNDLE_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
SHARED_SUPPORT_DIR="$CONTENTS_DIR/SharedSupport"
NODE_WORKER_DIR="$SHARED_SUPPORT_DIR/node_worker"
EMBEDDED_RUNTIME_DIR="$SHARED_SUPPORT_DIR/runtime"
EMBEDDED_PLAYWRIGHT_DIR="$EMBEDDED_RUNTIME_DIR/ms-playwright"
EMBEDDED_NODE_DIR="$EMBEDDED_RUNTIME_DIR/node"
EMBEDDED_NODE_BIN_DIR="$EMBEDDED_NODE_DIR/bin"
ICONSET_DIR="$BUILD_DIR/$ICON_BASENAME.iconset"
ICON_PATH="$BUILD_DIR/$ICON_BASENAME.icns"
SOURCE_PLIST="$ROOT/packaging/AppBundle/Info.plist"
STATIC_ICON_PATH="$ROOT/packaging/AppBundle/$ICON_BASENAME.icns"
PLIST_PATH="$CONTENTS_DIR/Info.plist"
PLIST_BUDDY="/usr/libexec/PlistBuddy"
NODE_SOURCE_EXECUTABLE="${DIMASAVE_NODE_EXECUTABLE:-$(command -v node || true)}"
NPM_SOURCE_EXECUTABLE="${DIMASAVE_NPM_EXECUTABLE:-$(command -v npm || true)}"
NODE_SOURCE_WORKER_DIR="$ROOT/node_worker"
NODE_BUILD_RUNTIME_DIR="$BUILD_DIR/node-runtime"
NODE_BUILD_PLAYWRIGHT_DIR="$NODE_BUILD_RUNTIME_DIR/ms-playwright"
VERSION_FILE="$ROOT/VERSION"

if [ -f "$VERSION_FILE" ]; then
  DEFAULT_VERSION="$(tr -d '\n\r' < "$VERSION_FILE")"
else
  DEFAULT_VERSION="$("$PLIST_BUDDY" -c 'Print :CFBundleShortVersionString' "$SOURCE_PLIST")"
fi
DEFAULT_BUILD="$("$PLIST_BUDDY" -c 'Print :CFBundleVersion' "$SOURCE_PLIST")"
SHORT_VERSION="${DIMASAVE_VERSION:-$DEFAULT_VERSION}"
BUILD_NUMBER="${DIMASAVE_BUILD:-$DEFAULT_BUILD}"
BUNDLE_ID="${DIMASAVE_BUNDLE_ID:-local.dimasave.release}"
COPYRIGHT_TEXT="${DIMASAVE_COPYRIGHT:-Direct distribution build}"
SIGN_IDENTITY="${APPLE_SIGN_IDENTITY:-}"
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
BUILD_HOME="$BUILD_DIR/home"
BUILD_CACHE="$BUILD_DIR/.cache"
mkdir -p "$CLANG_MODULE_CACHE_PATH" "$SWIFTPM_MODULECACHE_OVERRIDE" "$BUILD_HOME" "$BUILD_CACHE"

HOME="$BUILD_HOME" XDG_CACHE_HOME="$BUILD_CACHE" swift build -c release --package-path "$ROOT"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$FRAMEWORKS_DIR" "$SHARED_SUPPORT_DIR"

cp "$SOURCE_PLIST" "$PLIST_PATH"
"$PLIST_BUDDY" -c "Set :CFBundleIdentifier $BUNDLE_ID" "$PLIST_PATH"
"$PLIST_BUDDY" -c "Set :CFBundleShortVersionString $SHORT_VERSION" "$PLIST_PATH"
"$PLIST_BUDDY" -c "Set :CFBundleVersion $BUILD_NUMBER" "$PLIST_PATH"
"$PLIST_BUDDY" -c "Set :NSHumanReadableCopyright $COPYRIGHT_TEXT" "$PLIST_PATH"

cp "$ROOT/.build/release/$EXECUTABLE_NAME" "$MACOS_DIR/$EXECUTABLE_NAME"
cp "$ICON_PATH" "$RESOURCES_DIR/$ICON_BASENAME.icns"

RESOURCE_BUNDLE_PATH="$(find "$ROOT/.build" -maxdepth 4 -type d -name "$RESOURCE_BUNDLE_NAME" | head -n 1)"
if [ -n "$RESOURCE_BUNDLE_PATH" ] && [ -d "$RESOURCE_BUNDLE_PATH" ]; then
  cp -R "$RESOURCE_BUNDLE_PATH" "$RESOURCES_DIR/"
fi

if [ -z "$NODE_SOURCE_EXECUTABLE" ] || [ ! -x "$NODE_SOURCE_EXECUTABLE" ]; then
  printf 'node executable not found. Install Node 24 LTS or set DIMASAVE_NODE_EXECUTABLE.\n' >&2
  exit 1
fi

if [ -z "$NPM_SOURCE_EXECUTABLE" ] || [ ! -x "$NPM_SOURCE_EXECUTABLE" ]; then
  printf 'npm executable not found. Install Node 24 LTS or set DIMASAVE_NPM_EXECUTABLE.\n' >&2
  exit 1
fi

if [ ! -f "$NODE_SOURCE_WORKER_DIR/package.json" ]; then
  printf 'Node worker package.json not found: %s\n' "$NODE_SOURCE_WORKER_DIR/package.json" >&2
  exit 1
fi

rm -rf "$EMBEDDED_RUNTIME_DIR" "$NODE_BUILD_RUNTIME_DIR"
mkdir -p "$EMBEDDED_PLAYWRIGHT_DIR" "$EMBEDDED_NODE_BIN_DIR" "$NODE_BUILD_PLAYWRIGHT_DIR"

(
  cd "$NODE_SOURCE_WORKER_DIR"
  PLAYWRIGHT_BROWSERS_PATH="$NODE_BUILD_PLAYWRIGHT_DIR" "$NPM_SOURCE_EXECUTABLE" install --no-fund --no-audit
  PLAYWRIGHT_BROWSERS_PATH="$NODE_BUILD_PLAYWRIGHT_DIR" "$NODE_SOURCE_EXECUTABLE" ./node_modules/playwright/cli.js install chromium
)

rm -rf "$NODE_WORKER_DIR"
cp -R "$NODE_SOURCE_WORKER_DIR" "$NODE_WORKER_DIR"
cp -R "$NODE_BUILD_PLAYWRIGHT_DIR"/. "$EMBEDDED_PLAYWRIGHT_DIR/"
cp "$NODE_SOURCE_EXECUTABLE" "$EMBEDDED_NODE_BIN_DIR/node"
chmod +x "$EMBEDDED_NODE_BIN_DIR/node"

rm -rf "$EMBEDDED_PLAYWRIGHT_DIR"/chromium_headless_shell-*
find "$NODE_WORKER_DIR" -type d -name "__pycache__" -prune -exec rm -rf {} +
find "$NODE_WORKER_DIR" -type d -name ".bin" -prune -exec rm -rf {} +
rm -rf "$NODE_WORKER_DIR"/node_modules/playwright-core/.local-browsers \
       "$NODE_WORKER_DIR"/node_modules/playwright/.cache \
       "$NODE_WORKER_DIR"/node_modules/playwright-core/.cache

if [ -n "$SIGN_IDENTITY" ]; then
  codesign --force --deep --sign "$SIGN_IDENTITY" --timestamp --options runtime "$APP_DIR"
  codesign --verify --deep --verbose=2 "$APP_DIR"
else
  codesign --force --deep --sign - "$APP_DIR"
  codesign --verify --deep --verbose=2 "$APP_DIR"
fi

printf '\nRelease app created at:\n%s\n' "$APP_DIR"
if [ -n "$SIGN_IDENTITY" ]; then
  printf 'Signing identity: %s\n' "$SIGN_IDENTITY"
else
  printf 'Signing identity: - (ad-hoc)\n'
fi
