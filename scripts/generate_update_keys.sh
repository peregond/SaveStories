#!/bin/zsh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PRIVATE_DIR="$ROOT/.update-signing"
PRIVATE_KEY_PATH="$PRIVATE_DIR/ed25519-private.pem"
CONFIG_PATH="$ROOT/Sources/DimaSave/Resources/update_config.json"

mkdir -p "$PRIVATE_DIR"

if [ ! -f "$PRIVATE_KEY_PATH" ]; then
  openssl genpkey -algorithm ED25519 -out "$PRIVATE_KEY_PATH"
fi

PUBLIC_KEY="$(openssl pkey -in "$PRIVATE_KEY_PATH" -pubout -outform DER | python3 -c 'import base64, sys; data = sys.stdin.buffer.read(); prefix = bytes.fromhex("302a300506032b6570032100"); assert data.startswith(prefix), data.hex(); sys.stdout.write(base64.b64encode(data[len(prefix):]).decode())')"

python3 - "$CONFIG_PATH" "$PUBLIC_KEY" <<'PY'
import json
import sys
from pathlib import Path

config_path = Path(sys.argv[1])
public_key = sys.argv[2]
payload = json.loads(config_path.read_text(encoding="utf-8"))
payload["publicEDKey"] = public_key
config_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY

printf '\nUpdate signing key is ready.\n'
printf 'Private key: %s\n' "$PRIVATE_KEY_PATH"
printf 'Public key:  %s\n' "$PUBLIC_KEY"
printf '\nNext step: add the private key contents to GitHub secret UPDATE_SIGNING_PRIVATE_KEY.\n'
