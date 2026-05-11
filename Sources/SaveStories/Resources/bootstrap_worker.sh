#!/bin/zsh

set -euo pipefail

APP_SUPPORT="${SAVESTORIES_APP_SUPPORT:-$HOME/Library/Application Support/SaveMe}"
if ! mkdir -p "$APP_SUPPORT" 2>/dev/null; then
  APP_SUPPORT="$(pwd)/.runtime/SaveMe"
fi

WORKER_ROOT="$APP_SUPPORT/worker"
BROWSERS="$WORKER_ROOT/ms-playwright"
NODE_ROOT="$WORKER_ROOT/node"
NODE_BIN="$NODE_ROOT/bin/node"
NPM_BIN="$NODE_ROOT/bin/npm"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKER_DIR=""

for candidate in \
  "$(pwd)/node_worker" \
  "$SCRIPT_DIR/../../../SharedSupport/node_worker" \
  "$SCRIPT_DIR/../../SharedSupport/node_worker" \
  "$SCRIPT_DIR/../SharedSupport/node_worker" \
  "$SCRIPT_DIR/node_worker" \
  "$SCRIPT_DIR/../../../../node_worker" \
  "$SCRIPT_DIR/../../../node_worker" \
  "$SCRIPT_DIR/../../node_worker"; do
  if [ -f "$candidate/package.json" ] && [ -f "$candidate/bridge.mjs" ]; then
    WORKER_DIR="$(cd "$candidate" && pwd)"
    break
  fi
done

mkdir -p "$WORKER_ROOT"
printf 'Готовлю папку worker: %s\n' "$WORKER_ROOT"

use_system_node=0
if command -v node >/dev/null 2>&1; then
  system_node_major="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || true)"
  if [ "$system_node_major" = "24" ] && command -v npm >/dev/null 2>&1; then
    use_system_node=1
    NODE_BIN="$(command -v node)"
    NPM_BIN="$(command -v npm || true)"
  fi
fi

if [ "$use_system_node" -ne 1 ]; then
  if [ ! -x "$NODE_BIN" ] || [ "$("$NODE_BIN" -p 'process.versions.node.split(".")[0]' 2>/dev/null || true)" != "24" ]; then
    node_arch=""
    case "$(uname -m)" in
      arm64) node_arch="darwin-arm64" ;;
      x86_64) node_arch="darwin-x64" ;;
      *)
        printf 'Неподдерживаемая архитектура macOS для автоматической установки Node: %s\n' "$(uname -m)" >&2
        exit 1
        ;;
    esac

    node_base_url="https://nodejs.org/dist/latest-v24.x"
    temp_dir="$(mktemp -d)"
    trap 'rm -rf "$temp_dir"' EXIT

    printf 'Скачиваю Node 24 LTS...\n'
    node_archive="$(curl -fsSL "$node_base_url/SHASUMS256.txt" | awk -v arch="$node_arch" '$2 ~ ("-" arch "\\.tar\\.gz$") {print $2; exit}')"
    if [ -z "$node_archive" ]; then
      printf 'Не удалось найти архив Node 24 LTS для %s.\n' "$node_arch" >&2
      exit 1
    fi
    node_url="$node_base_url/$node_archive"
    curl -fsSL "$node_url" -o "$temp_dir/node.tar.gz"
    tar -xzf "$temp_dir/node.tar.gz" -C "$temp_dir"
    rm -rf "$NODE_ROOT"
    mkdir -p "$NODE_ROOT"
    extracted_node="$(find "$temp_dir" -maxdepth 1 -type d -name 'node-*' | head -n 1)"
    if [ -z "$extracted_node" ]; then
      printf 'Не удалось распаковать Node runtime.\n' >&2
      exit 1
    fi
    cp -R "$extracted_node"/. "$NODE_ROOT/"
  fi
fi

if [ ! -x "$NODE_BIN" ]; then
  printf 'node не найден и не был установлен автоматически.\n' >&2
  exit 1
fi

if [ -z "$NPM_BIN" ] || [ ! -x "$NPM_BIN" ]; then
  printf 'npm не найден и не был установлен автоматически.\n' >&2
  exit 1
fi

if [ -z "$WORKER_DIR" ] || [ ! -d "$WORKER_DIR" ]; then
  printf 'Не удалось найти каталог node_worker рядом с проектом.\n' >&2
  exit 1
fi

export PLAYWRIGHT_BROWSERS_PATH="$BROWSERS"
export PATH="$(dirname "$NODE_BIN"):$PATH"

if [ "$WORKER_DIR" != "$WORKER_ROOT" ]; then
  printf 'Копирую worker...\n'
  rsync -a --delete \
    --exclude node_modules \
    --exclude node \
    --exclude ms-playwright \
    --exclude browser-profile \
    --exclude .venv \
    --exclude .DS_Store \
    "$WORKER_DIR"/ "$WORKER_ROOT"/
fi

cd "$WORKER_ROOT"
printf 'Устанавливаю npm зависимости...\n'
"$NPM_BIN" install --no-fund --no-audit
printf 'Скачиваю Chromium...\n'
"$NODE_BIN" ./node_modules/playwright/cli.js install chromium

printf '\nWorker bootstrap complete.\n'
printf 'Node: %s\n' "$NODE_BIN"
printf 'Worker: %s\n' "$WORKER_ROOT/bridge.mjs"
printf 'Browser profile: %s\n' "$WORKER_ROOT/browser-profile"
printf 'Playwright browsers: %s\n' "$BROWSERS"
