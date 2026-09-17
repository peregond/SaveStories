#!/bin/zsh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE_NAME="SaveMe"
EXECUTABLE_NAME="SaveMe"
MEDIA_MUXER_NAME="SaveMeMediaMuxer"
BUILD_DIR="$ROOT/beta-build"
RELEASE_DIR="$BUILD_DIR/release"
APP_DIR="$RELEASE_DIR/$BUNDLE_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
SHARED_SUPPORT_DIR="$CONTENTS_DIR/SharedSupport"
HELPERS_DIR="$CONTENTS_DIR/Helpers"
NODE_WORKER_DIR="$SHARED_SUPPORT_DIR/node_worker"
RESOURCE_BUNDLE_NAME="$EXECUTABLE_NAME"_SaveMe.bundle
REQUIRED_SDK="${SAVEME_REQUIRE_SDK:-14.0}"
PREVIEW_BUNDLE_ID="${SAVESTORIES_BUNDLE_ID:-local.saveme.macos27.preview}"

python3 "$ROOT/scripts/macos_bundle.py" preflight --require-sdk "$REQUIRED_SDK"

mkdir -p "$BUILD_DIR" "$RELEASE_DIR"

export CLANG_MODULE_CACHE_PATH="$BUILD_DIR/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$BUILD_DIR/swiftpm-module-cache"

swift build --build-system native -c release --package-path "$ROOT" --sdk "$(xcrun --sdk macosx --show-sdk-path)"
BIN_DIR="$(swift build --build-system native -c release --package-path "$ROOT" --sdk "$(xcrun --sdk macosx --show-sdk-path)" --show-bin-path)"
RESOURCE_BUNDLE_PATH="$BIN_DIR/$RESOURCE_BUNDLE_NAME"
SPARKLE_FRAMEWORK_PATH="$BIN_DIR/Sparkle.framework"
for artifact in "$BIN_DIR/$EXECUTABLE_NAME" "$BIN_DIR/$MEDIA_MUXER_NAME" "$RESOURCE_BUNDLE_PATH" "$SPARKLE_FRAMEWORK_PATH"; do
  if [ ! -e "$artifact" ]; then
    printf 'Required preview artifact is missing: %s\n' "$artifact" >&2
    exit 1
  fi
done

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$FRAMEWORKS_DIR" "$SHARED_SUPPORT_DIR" "$HELPERS_DIR"

cp "$ROOT/packaging/AppBundle/Info.plist" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $PREVIEW_BUNDLE_ID" "$CONTENTS_DIR/Info.plist"
cp "$BIN_DIR/$EXECUTABLE_NAME" "$MACOS_DIR/$EXECUTABLE_NAME"
cp "$BIN_DIR/$MEDIA_MUXER_NAME" "$HELPERS_DIR/$MEDIA_MUXER_NAME"
chmod 755 "$HELPERS_DIR/$MEDIA_MUXER_NAME"
"$ROOT/scripts/compile_app_icon.sh" "$RESOURCES_DIR"

cp -R "$RESOURCE_BUNDLE_PATH" "$RESOURCES_DIR/"
ditto "$SPARKLE_FRAMEWORK_PATH" "$FRAMEWORKS_DIR/Sparkle.framework"
if ! otool -l "$MACOS_DIR/$EXECUTABLE_NAME" | grep -q '@executable_path/../Frameworks'; then
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS_DIR/$EXECUTABLE_NAME"
fi

if [ ! -f "$ROOT/node_worker/package.json" ] || [ ! -f "$ROOT/node_worker/bridge.mjs" ]; then
  printf 'Node worker sources are missing. The beta app bundle is incomplete.\n' >&2
  exit 1
fi
mkdir -p "$NODE_WORKER_DIR"
rsync -a --delete \
  --exclude node_modules \
  --exclude .DS_Store \
  "$ROOT/node_worker"/ "$NODE_WORKER_DIR"/

python3 "$ROOT/scripts/macos_bundle.py" stamp --app "$APP_DIR" --require-sdk "$REQUIRED_SDK" --preview
codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"
python3 "$ROOT/scripts/macos_bundle.py" verify --app "$APP_DIR" --require-sdk "$REQUIRED_SDK"

printf '\nBeta app created at:\n%s\n' "$APP_DIR"
