#!/bin/zsh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORKER_DIR="$ROOT/node_worker"
APP_SUPPORT="${DIMASAVE_APP_SUPPORT:-$HOME/Library/Application Support/DimaSave}"
BROWSERS="${DIMASAVE_PLAYWRIGHT_BROWSERS:-$APP_SUPPORT/worker/ms-playwright}"

if ! command -v node >/dev/null 2>&1; then
  printf 'node не найден. Установите Node 24 LTS и повторите попытку.\n' >&2
  exit 1
fi

if ! command -v npm >/dev/null 2>&1; then
  printf 'npm не найден. Установите Node 24 LTS и повторите попытку.\n' >&2
  exit 1
fi

mkdir -p "$BROWSERS"

cd "$WORKER_DIR"
PLAYWRIGHT_BROWSERS_PATH="$BROWSERS" npm install
PLAYWRIGHT_BROWSERS_PATH="$BROWSERS" node ./node_modules/playwright/cli.js install chromium

printf '\nNode worker bootstrap complete.\n'
printf 'Node: %s\n' "$(command -v node)"
printf 'Worker: %s\n' "$WORKER_DIR/bridge.mjs"
printf 'Playwright browsers: %s\n' "$BROWSERS"
