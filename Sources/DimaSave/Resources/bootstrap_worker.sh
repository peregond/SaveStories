#!/bin/zsh

set -euo pipefail

APP_SUPPORT="${DIMASAVE_APP_SUPPORT:-$HOME/Library/Application Support/DimaSave}"
if ! mkdir -p "$APP_SUPPORT" 2>/dev/null; then
  APP_SUPPORT="$(pwd)/.runtime/DimaSave"
fi

WORKER_ROOT="$APP_SUPPORT/worker"
BROWSERS="$WORKER_ROOT/ms-playwright"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKER_DIR=""

for candidate in \
  "$(pwd)/node_worker" \
  "$SCRIPT_DIR/node_worker" \
  "$SCRIPT_DIR/../../../../node_worker" \
  "$SCRIPT_DIR/../../../node_worker" \
  "$SCRIPT_DIR/../../node_worker"; do
  if [ -d "$candidate" ]; then
    WORKER_DIR="$(cd "$candidate" && pwd)"
    break
  fi
done

mkdir -p "$WORKER_ROOT"

if ! command -v node >/dev/null 2>&1; then
  printf 'node не найден. Установите Node 24 LTS и повторите попытку.\n' >&2
  exit 1
fi

if ! command -v npm >/dev/null 2>&1; then
  printf 'npm не найден. Установите Node 24 LTS и повторите попытку.\n' >&2
  exit 1
fi

if [ -z "$WORKER_DIR" ] || [ ! -d "$WORKER_DIR" ]; then
  printf 'Не удалось найти каталог node_worker рядом с проектом.\n' >&2
  exit 1
fi

export PLAYWRIGHT_BROWSERS_PATH="$BROWSERS"

cd "$WORKER_DIR"
npm install
node ./node_modules/playwright/cli.js install chromium

printf '\nWorker bootstrap complete.\n'
printf 'Node: %s\n' "$(command -v node)"
printf 'Worker: %s\n' "$WORKER_DIR/bridge.mjs"
printf 'Browser profile: %s\n' "$WORKER_ROOT/browser-profile"
printf 'Playwright browsers: %s\n' "$BROWSERS"
