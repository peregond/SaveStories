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
LEGACY_RELEASE_APP_CANDIDATES=(
  "$ROOT/dist/release/SaveStories.app"
  "$ROOT/dist/release/DimaSave.app"
)
VERSION_FILE="$ROOT/VERSION"
UPDATE_CONFIG_PATH="$ROOT/Sources/DimaSave/Resources/update_config.json"

read_update_config_value() {
  local key="$1"
  python3 - "$UPDATE_CONFIG_PATH" "$key" <<'PY'
import json
import sys
from pathlib import Path

config_path = Path(sys.argv[1])
key = sys.argv[2]

if not config_path.exists():
    sys.exit(0)

payload = json.loads(config_path.read_text(encoding="utf-8"))
value = payload.get(key, "")
if isinstance(value, str):
    sys.stdout.write(value)
PY
}

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
MACOS_UPDATE_FEED_URL="${DIMASAVE_MACOS_UPDATE_FEED_URL:-$(read_update_config_value macosFeedURL)}"
UPDATE_PUBLIC_KEY="${DIMASAVE_UPDATE_PUBLIC_KEY:-$(read_update_config_value publicEDKey)}"
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
if [ -n "$MACOS_UPDATE_FEED_URL" ]; then
  "$PLIST_BUDDY" -c "Delete :SUFeedURL" "$PLIST_PATH" >/dev/null 2>&1 || true
  "$PLIST_BUDDY" -c "Add :SUFeedURL string $MACOS_UPDATE_FEED_URL" "$PLIST_PATH"
fi
if [ -n "$UPDATE_PUBLIC_KEY" ]; then
  "$PLIST_BUDDY" -c "Delete :SUPublicEDKey" "$PLIST_PATH" >/dev/null 2>&1 || true
  "$PLIST_BUDDY" -c "Add :SUPublicEDKey string $UPDATE_PUBLIC_KEY" "$PLIST_PATH"
fi

cp "$ROOT/.build/release/$EXECUTABLE_NAME" "$MACOS_DIR/$EXECUTABLE_NAME"
cp "$ICON_PATH" "$RESOURCES_DIR/$ICON_BASENAME.icns"

RESOURCE_BUNDLE_PATH="$(find "$ROOT/.build" -maxdepth 4 -type d -name "$RESOURCE_BUNDLE_NAME" | head -n 1)"
if [ -n "$RESOURCE_BUNDLE_PATH" ] && [ -d "$RESOURCE_BUNDLE_PATH" ]; then
  cp -R "$RESOURCE_BUNDLE_PATH" "$RESOURCES_DIR/"
fi

SPARKLE_FRAMEWORK_PATH="$(find "$ROOT/.build" -type d -name 'Sparkle.framework' | head -n 1)"
if [ -z "$SPARKLE_FRAMEWORK_PATH" ] || [ ! -d "$SPARKLE_FRAMEWORK_PATH" ]; then
  printf 'Sparkle.framework not found in .build. The macOS updater bundle is incomplete.\n' >&2
  exit 1
fi
ditto "$SPARKLE_FRAMEWORK_PATH" "$FRAMEWORKS_DIR/Sparkle.framework"
if ! otool -l "$MACOS_DIR/$EXECUTABLE_NAME" | grep -q '@executable_path/../Frameworks'; then
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS_DIR/$EXECUTABLE_NAME"
fi

if [ ! -f "$NODE_SOURCE_WORKER_DIR/package.json" ]; then
  printf 'Node worker package.json not found: %s\n' "$NODE_SOURCE_WORKER_DIR/package.json" >&2
  exit 1
fi

rm -rf "$EMBEDDED_RUNTIME_DIR" "$NODE_BUILD_RUNTIME_DIR"
mkdir -p "$EMBEDDED_PLAYWRIGHT_DIR" "$EMBEDDED_NODE_BIN_DIR" "$NODE_BUILD_PLAYWRIGHT_DIR"
USED_LEGACY_RUNTIME=0
if [ -n "$NODE_SOURCE_EXECUTABLE" ] && [ -x "$NODE_SOURCE_EXECUTABLE" ] && [ -n "$NPM_SOURCE_EXECUTABLE" ] && [ -x "$NPM_SOURCE_EXECUTABLE" ]; then
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
else
  LEGACY_RUNTIME_APP=""
  for candidate in "${LEGACY_RELEASE_APP_CANDIDATES[@]}"; do
    if [ -d "$candidate/Contents/Frameworks/Python.framework" ] && \
       [ -d "$candidate/Contents/SharedSupport/runtime/site-packages" ] && \
       [ -d "$candidate/Contents/SharedSupport/runtime/ms-playwright" ]; then
      LEGACY_RUNTIME_APP="$candidate"
      break
    fi
  done

  if [ -z "$LEGACY_RUNTIME_APP" ]; then
    printf 'Neither Node 24 runtime nor legacy embedded Python runtime was found. Install Node 24 LTS or provide an existing release app.\n' >&2
    exit 1
  fi

  printf 'Node runtime not found. Reusing legacy embedded Python runtime from:\n%s\n' "$LEGACY_RUNTIME_APP"
  USED_LEGACY_RUNTIME=1
  cp -R "$LEGACY_RUNTIME_APP/Contents/Frameworks/Python.framework" "$FRAMEWORKS_DIR/"
  cp -R "$LEGACY_RUNTIME_APP/Contents/SharedSupport/runtime/site-packages" "$EMBEDDED_RUNTIME_DIR/"
  cp -R "$LEGACY_RUNTIME_APP/Contents/SharedSupport/runtime/ms-playwright" "$EMBEDDED_RUNTIME_DIR/"
fi

if [ -n "$SIGN_IDENTITY" ]; then
  codesign --force --deep --sign "$SIGN_IDENTITY" --timestamp --options runtime "$APP_DIR"
  codesign --verify --deep --verbose=2 "$APP_DIR"
else
  codesign --force --deep --sign - "$APP_DIR"
  codesign --verify --deep --verbose=2 "$APP_DIR"
fi

printf '\nRelease app created at:\n%s\n' "$APP_DIR"
if [ "$USED_LEGACY_RUNTIME" -eq 1 ]; then
  printf 'Embedded runtime: legacy Python fallback\n'
else
  printf 'Embedded runtime: Node worker\n'
fi
if [ -n "$SIGN_IDENTITY" ]; then
  printf 'Signing identity: %s\n' "$SIGN_IDENTITY"
else
  printf 'Signing identity: - (ad-hoc)\n'
fi
