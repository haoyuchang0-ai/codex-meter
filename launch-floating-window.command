#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
NODE_BIN="${NODE:-$(command -v node || true)}"
HEALTH_URL="http://127.0.0.1:5487/api/health"
APP_DIR="$ROOT/CodexQuotaFloat.app"

if [[ -z "$NODE_BIN" ]]; then
  echo "Node.js 18+ is required. Install Node.js or set NODE=/path/to/node." >&2
  exit 1
fi

if [[ ! -x "$APP_DIR/Contents/MacOS/CodexQuotaFloat" ]]; then
  zsh "$ROOT/scripts/build-floating-window.sh"
fi

if ! /usr/bin/curl -fsS "$HEALTH_URL" >/dev/null 2>&1; then
  cd "$ROOT"
  "$NODE_BIN" server.js >> "$ROOT/quota-window.log" 2>&1 &
  sleep 1
fi

/usr/bin/open "$APP_DIR"
