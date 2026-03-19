#!/bin/zsh

set -euo pipefail
setopt null_glob

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="DimaSave"
BUILD_DIR="$ROOT/dist"
RELEASE_DIR="$BUILD_DIR/release"
APP_DIR="$RELEASE_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
SHARED_SUPPORT_DIR="$CONTENTS_DIR/SharedSupport"
EMBEDDED_RUNTIME_DIR="$SHARED_SUPPORT_DIR/runtime"
EMBEDDED_SITE_PACKAGES="$EMBEDDED_RUNTIME_DIR/site-packages"
EMBEDDED_PLAYWRIGHT_DIR="$EMBEDDED_RUNTIME_DIR/ms-playwright"
ICONSET_DIR="$BUILD_DIR/$APP_NAME.iconset"
ICON_PATH="$BUILD_DIR/$APP_NAME.icns"
SOURCE_PLIST="$ROOT/packaging/AppBundle/Info.plist"
STATIC_ICON_PATH="$ROOT/packaging/AppBundle/$APP_NAME.icns"
PLIST_PATH="$CONTENTS_DIR/Info.plist"
PLIST_BUDDY="/usr/libexec/PlistBuddy"
SOURCE_APP_SUPPORT="${DIMASAVE_APP_SUPPORT:-$HOME/Library/Application Support/DimaSave}"
SOURCE_WORKER_ROOT="$SOURCE_APP_SUPPORT/worker"
SOURCE_VENV="$SOURCE_WORKER_ROOT/.venv"
SOURCE_PLAYWRIGHT_DIR="$SOURCE_WORKER_ROOT/ms-playwright"

DEFAULT_VERSION="$("$PLIST_BUDDY" -c 'Print :CFBundleShortVersionString' "$SOURCE_PLIST")"
DEFAULT_BUILD="$("$PLIST_BUDDY" -c 'Print :CFBundleVersion' "$SOURCE_PLIST")"
SHORT_VERSION="${DIMASAVE_VERSION:-$DEFAULT_VERSION}"
BUILD_NUMBER="${DIMASAVE_BUILD:-$DEFAULT_BUILD}"
BUNDLE_ID="${DIMASAVE_BUNDLE_ID:-local.dimasave.release}"
COPYRIGHT_TEXT="${DIMASAVE_COPYRIGHT:-Direct distribution build}"
SIGN_IDENTITY="${APPLE_SIGN_IDENTITY:-}"
RESOURCE_BUNDLE_NAME="$APP_NAME"_DimaSave.bundle

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

cp "$ROOT/.build/release/$APP_NAME" "$MACOS_DIR/$APP_NAME"
cp "$ICON_PATH" "$RESOURCES_DIR/$APP_NAME.icns"

RESOURCE_BUNDLE_PATH="$(find "$ROOT/.build" -maxdepth 4 -type d -name "$RESOURCE_BUNDLE_NAME" | head -n 1)"
if [ -n "$RESOURCE_BUNDLE_PATH" ] && [ -d "$RESOURCE_BUNDLE_PATH" ]; then
  cp -R "$RESOURCE_BUNDLE_PATH" "$RESOURCES_DIR/"
fi

if [ ! -x "$SOURCE_VENV/bin/python3" ]; then
  printf 'Embedded runtime source not found: %s\n' "$SOURCE_VENV/bin/python3" >&2
  exit 1
fi

if [ ! -d "$SOURCE_PLAYWRIGHT_DIR" ]; then
  printf 'Embedded Playwright browsers not found: %s\n' "$SOURCE_PLAYWRIGHT_DIR" >&2
  exit 1
fi

PYTHON_BASE_PREFIX="$("$SOURCE_VENV/bin/python3" -c 'import sys; print(sys.base_prefix)')"
PYTHON_FRAMEWORK_ROOT="$(cd "$PYTHON_BASE_PREFIX/../.." && pwd)"
PYTHON_LIB_DIR="$(find "$SOURCE_VENV/lib" -maxdepth 1 -type d -name 'python3.*' | head -n 1)"
if [ -z "$PYTHON_LIB_DIR" ]; then
  printf 'Could not locate Python stdlib inside %s\n' "$SOURCE_VENV/lib" >&2
  exit 1
fi

PYTHON_VERSION_NAME="$(basename "$PYTHON_LIB_DIR")"
EMBEDDED_PYTHON_HOME="$FRAMEWORKS_DIR/Python.framework/Versions/3.13"
EMBEDDED_PYTHON_BIN="$EMBEDDED_PYTHON_HOME/bin/python3.13"
EMBEDDED_PYTHON_APP="$EMBEDDED_PYTHON_HOME/Resources/Python.app/Contents/MacOS/Python"

rm -rf "$FRAMEWORKS_DIR/Python.framework" "$EMBEDDED_RUNTIME_DIR"
cp -R "$PYTHON_FRAMEWORK_ROOT" "$FRAMEWORKS_DIR/"
mkdir -p "$EMBEDDED_RUNTIME_DIR"
cp -R "$PYTHON_LIB_DIR/site-packages" "$EMBEDDED_SITE_PACKAGES"
cp -R "$SOURCE_PLAYWRIGHT_DIR" "$EMBEDDED_PLAYWRIGHT_DIR"

rm -rf "$EMBEDDED_PLAYWRIGHT_DIR"/chromium_headless_shell-*

find "$EMBEDDED_SITE_PACKAGES" -type d -name "__pycache__" -prune -exec rm -rf {} +
find "$EMBEDDED_PYTHON_HOME/lib/$PYTHON_VERSION_NAME" -type d -name "__pycache__" -prune -exec rm -rf {} +

rm -rf "$EMBEDDED_SITE_PACKAGES/pip" \
       "$EMBEDDED_SITE_PACKAGES/setuptools" \
       "$EMBEDDED_SITE_PACKAGES/wheel" \
       "$EMBEDDED_SITE_PACKAGES/playwright/_impl/__pyinstaller" \
       "$EMBEDDED_SITE_PACKAGES/playwright/py.typed" \
       "$EMBEDDED_SITE_PACKAGES/playwright/driver/README.md" \
       "$EMBEDDED_SITE_PACKAGES/playwright/driver/LICENSE" \
       "$EMBEDDED_SITE_PACKAGES/playwright/driver/package/types" \
       "$EMBEDDED_SITE_PACKAGES/playwright/driver/package/bin" \
       "$EMBEDDED_SITE_PACKAGES/playwright/driver/package/README.md" \
       "$EMBEDDED_SITE_PACKAGES/playwright/driver/package/NOTICE" \
       "$EMBEDDED_SITE_PACKAGES/playwright/driver/package/ThirdPartyNotices.txt" \
       "$EMBEDDED_SITE_PACKAGES/playwright/driver/package/index.d.ts" \
       "$EMBEDDED_PYTHON_HOME/include" \
       "$EMBEDDED_PYTHON_HOME/share" \
       "$EMBEDDED_PYTHON_HOME/Headers" \
       "$EMBEDDED_PYTHON_HOME/lib/$PYTHON_VERSION_NAME/test" \
       "$EMBEDDED_PYTHON_HOME/lib/$PYTHON_VERSION_NAME/ensurepip" \
       "$EMBEDDED_PYTHON_HOME/lib/$PYTHON_VERSION_NAME/idlelib" \
       "$EMBEDDED_PYTHON_HOME/lib/$PYTHON_VERSION_NAME/turtledemo" \
       "$EMBEDDED_PYTHON_HOME/lib/$PYTHON_VERSION_NAME/tkinter" \
       "$EMBEDDED_PYTHON_HOME/lib/$PYTHON_VERSION_NAME/venv" \
       "$EMBEDDED_PYTHON_HOME/lib/$PYTHON_VERSION_NAME/pydoc_data" \
       "$EMBEDDED_PYTHON_HOME/bin/pip3" \
       "$EMBEDDED_PYTHON_HOME/bin/pip3.13" \
       "$EMBEDDED_PYTHON_HOME/bin/idle3" \
       "$EMBEDDED_PYTHON_HOME/bin/idle3.13" \
       "$EMBEDDED_PYTHON_HOME/bin/pydoc3" \
       "$EMBEDDED_PYTHON_HOME/bin/pydoc3.13" \
       "$EMBEDDED_PYTHON_HOME/bin/python3-config" \
       "$EMBEDDED_PYTHON_HOME/bin/python3.13-config"

rm -rf "$EMBEDDED_SITE_PACKAGES"/pip-*.dist-info \
       "$EMBEDDED_SITE_PACKAGES"/setuptools-*.dist-info \
       "$EMBEDDED_SITE_PACKAGES"/wheel-*.dist-info

rm -f "$EMBEDDED_PYTHON_HOME/lib/$PYTHON_VERSION_NAME/site-packages"
mkdir -p "$EMBEDDED_PYTHON_HOME/lib/$PYTHON_VERSION_NAME/site-packages"
rm -f "$EMBEDDED_PYTHON_HOME/lib/$PYTHON_VERSION_NAME/sitecustomize.py"

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
