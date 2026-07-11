#!/bin/zsh
set -eu

LABEL="com.haoyuchang.codex-meter"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOME_DIR="${CODEX_METER_HOME:-$HOME}"
PLIST="$HOME_DIR/Library/LaunchAgents/$LABEL.plist"
LOG_DIR="$HOME_DIR/Library/Logs/CodexMeter"
APP_SUPPORT="$HOME_DIR/Library/Application Support/CodexMeter"
RUNTIME="$APP_SUPPORT/runtime"
DOMAIN="gui/$(/usr/bin/id -u)"
LAUNCHCTL="${CODEX_METER_LAUNCHCTL:-/bin/launchctl}"
WATCHER="$RUNTIME/scripts/codex-lifecycle-watcher.sh"

prepare_runtime() {
  if [[ ! -x "$ROOT/CodexQuotaFloat.app/Contents/MacOS/CodexQuotaFloat" ]]; then
    /bin/zsh "$ROOT/scripts/build-floating-window.sh"
  fi

  /bin/rm -rf "$RUNTIME"
  /bin/mkdir -p "$RUNTIME/scripts"
  /usr/bin/ditto "$ROOT/CodexQuotaFloat.app" "$RUNTIME/CodexQuotaFloat.app"
  /usr/bin/ditto "$ROOT/src" "$RUNTIME/src"
  /usr/bin/ditto "$ROOT/public" "$RUNTIME/public"
  /bin/cp "$ROOT/server.js" "$RUNTIME/server.js"
  /bin/cp "$ROOT/launch-floating-window.command" "$RUNTIME/launch-floating-window.command"
  /bin/cp "$ROOT/scripts/codex-lifecycle-watcher.sh" "$WATCHER"
  /bin/chmod +x "$RUNTIME/launch-floating-window.command" "$WATCHER"
}

install_agent() {
  /bin/mkdir -p "${PLIST:h}" "$LOG_DIR"
  "$LAUNCHCTL" bootout "$DOMAIN/$LABEL" >/dev/null 2>&1 || true
  : > "$LOG_DIR/watcher.log"
  : > "$LOG_DIR/watcher-error.log"
  prepare_runtime

  /bin/rm -f "$PLIST"
  /usr/bin/plutil -create xml1 "$PLIST"
  /usr/bin/plutil -insert Label -string "$LABEL" "$PLIST"
  /usr/bin/plutil -insert ProgramArguments -array "$PLIST"
  /usr/bin/plutil -insert ProgramArguments.0 -string /bin/zsh "$PLIST"
  /usr/bin/plutil -insert ProgramArguments.1 -string "$WATCHER" "$PLIST"
  /usr/bin/plutil -insert WorkingDirectory -string "$RUNTIME" "$PLIST"
  /usr/bin/plutil -insert RunAtLoad -bool true "$PLIST"
  /usr/bin/plutil -insert KeepAlive -bool true "$PLIST"
  /usr/bin/plutil -insert ProcessType -string Background "$PLIST"
  /usr/bin/plutil -insert StandardOutPath -string "$LOG_DIR/watcher.log" "$PLIST"
  /usr/bin/plutil -insert StandardErrorPath -string "$LOG_DIR/watcher-error.log" "$PLIST"
  /usr/bin/plutil -lint "$PLIST" >/dev/null

  "$LAUNCHCTL" bootstrap "$DOMAIN" "$PLIST"
  "$LAUNCHCTL" enable "$DOMAIN/$LABEL"
  "$LAUNCHCTL" kickstart -k "$DOMAIN/$LABEL"
  print "Codex Meter autostart installed."
}

uninstall_agent() {
  "$LAUNCHCTL" bootout "$DOMAIN/$LABEL" >/dev/null 2>&1 || true
  if [[ -f "$WATCHER" ]]; then
    CODEX_METER_DRY_RUN="${CODEX_METER_DRY_RUN:-0}" /bin/zsh "$WATCHER" --stop
  fi
  /bin/rm -f "$PLIST"
  /bin/rm -rf "$RUNTIME"
  print "Codex Meter autostart removed."
}

case "${1:-}" in
  install)
    install_agent
    ;;
  uninstall)
    uninstall_agent
    ;;
  *)
    print -u2 "Usage: $0 install|uninstall"
    exit 2
    ;;
esac
