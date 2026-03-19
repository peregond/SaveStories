#!/bin/zsh

set -euo pipefail

APP_SUPPORT="${DIMASAVE_APP_SUPPORT:-$HOME/Library/Application Support/DimaSave}"
if ! mkdir -p "$APP_SUPPORT" 2>/dev/null; then
  APP_SUPPORT="$(pwd)/.runtime/DimaSave"
fi

WORKER_ROOT="$APP_SUPPORT/worker"
VENV="$WORKER_ROOT/.venv"
BROWSERS="$WORKER_ROOT/ms-playwright"

mkdir -p "$WORKER_ROOT"

python3 -m venv "$VENV"
"$VENV/bin/pip" install --upgrade pip setuptools wheel
"$VENV/bin/pip" install playwright

export PLAYWRIGHT_BROWSERS_PATH="$BROWSERS"
"$VENV/bin/python" -m playwright install chromium

printf '\nWorker bootstrap complete.\n'
printf 'Python: %s\n' "$VENV/bin/python"
printf 'Browser profile: %s\n' "$WORKER_ROOT/browser-profile"
printf 'Playwright browsers: %s\n' "$BROWSERS"
