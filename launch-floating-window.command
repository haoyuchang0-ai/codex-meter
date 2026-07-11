#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
HEALTH_URL="http://127.0.0.1:5487/api/health"
APP_DIR="$ROOT/CodexQuotaFloat.app"
PID_FILE="$ROOT/quota-window.pid"

if [[ ! -x "$APP_DIR/Contents/MacOS/CodexQuotaFloat" ]]; then
  zsh "$ROOT/scripts/build-floating-window.sh"
fi

if ! /usr/bin/curl -fsS "$HEALTH_URL" >/dev/null 2>&1; then
  CODEX_NODE="$HOME/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node"
  NODE_BIN="${NODE:-$(command -v node || true)}"
  if [[ -z "$NODE_BIN" && -x "$CODEX_NODE" ]]; then
    NODE_BIN="$CODEX_NODE"
  fi
  if [[ -z "$NODE_BIN" ]]; then
    echo "Node.js 18+ is required. Install Node.js or set NODE=/path/to/node." >&2
    exit 1
  fi

  nohup "$NODE_BIN" "$ROOT/server.js" >> "$ROOT/quota-window.log" 2>&1 &
  echo $! > "$PID_FILE"
  disown || true
  sleep 1
fi

/usr/bin/open "$APP_DIR"
