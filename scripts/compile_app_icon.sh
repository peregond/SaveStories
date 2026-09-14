#!/bin/zsh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="${1:?usage: compile_app_icon.sh <resources-directory>}"
ICON_NAME="SaveMe"
ICON_DOCUMENT="$ROOT/packaging/AppBundle/$ICON_NAME.icon"
STATIC_ICON="$ROOT/packaging/AppBundle/$ICON_NAME.icns"
ACTOOL="$(xcrun --find actool 2>/dev/null || true)"

mkdir -p "$OUTPUT_DIR"

if [ -n "$ACTOOL" ] && [ -d "$ICON_DOCUMENT" ]; then
  WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/saveme-icon.XXXXXX")"
  trap 'rm -rf "$WORK_DIR"' EXIT

  DOCUMENT_COPY="$WORK_DIR/$ICON_NAME.icon"
  COMPILED_DIR="$WORK_DIR/compiled"
  PARTIAL_PLIST="$WORK_DIR/icon-info.plist"
  mkdir -p "$COMPILED_DIR"
  ditto "$ICON_DOCUMENT" "$DOCUMENT_COPY"
  xattr -cr "$DOCUMENT_COPY" 2>/dev/null || true

  if "$ACTOOL" \
    --compile "$COMPILED_DIR" \
    --platform macosx \
    --minimum-deployment-target 14.0 \
    --target-device mac \
    --app-icon "$ICON_NAME" \
    --output-partial-info-plist "$PARTIAL_PLIST" \
    "$DOCUMENT_COPY" && \
    [ -f "$COMPILED_DIR/$ICON_NAME.icns" ] && [ -f "$COMPILED_DIR/Assets.car" ]; then
    cp "$COMPILED_DIR/$ICON_NAME.icns" "$OUTPUT_DIR/$ICON_NAME.icns"
    cp "$COMPILED_DIR/Assets.car" "$OUTPUT_DIR/Assets.car"
    exit 0
  fi

  printf 'The selected Xcode could not compile the Icon Composer document; using the static icon.\n' >&2
fi

if [ -f "$STATIC_ICON" ]; then
  rm -f "$OUTPUT_DIR/Assets.car"
  cp "$STATIC_ICON" "$OUTPUT_DIR/$ICON_NAME.icns"
else
  printf 'No Icon Composer document or fallback icon found for %s.\n' "$ICON_NAME" >&2
  exit 1
fi
