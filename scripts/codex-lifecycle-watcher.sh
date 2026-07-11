#!/bin/zsh
set -u

ROOT="${CODEX_METER_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
POLL_SECONDS="${CODEX_METER_POLL_SECONDS:-3}"
SESSION_FILE="$ROOT/quota-window.session"
PID_FILE="$ROOT/quota-window.pid"
SERVER_PATH="$ROOT/server.js"
LAUNCHER="${CODEX_METER_LAUNCHER:-$ROOT/launch-floating-window.command}"
EVENT_LOG="${CODEX_METER_EVENT_LOG:-}"
DRY_RUN="${CODEX_METER_DRY_RUN:-0}"
TEST_SEQUENCE="${CODEX_METER_TEST_SEQUENCE:-}"
CODEX_PATTERN='^/Applications/ChatGPT\.app/Contents/MacOS/ChatGPT$'

typeset -a test_sessions
if [[ -n "$TEST_SEQUENCE" ]]; then
  test_sessions=("${(@s:,:)TEST_SEQUENCE}")
fi

record_event() {
  [[ -n "$EVENT_LOG" ]] && print -r -- "$1" >> "$EVENT_LOG"
  return 0
}

current_codex_session() {
  local pid start_time
  pid=$(/usr/bin/pgrep -f "$CODEX_PATTERN" 2>/dev/null | /usr/bin/head -n 1)
  [[ -n "$pid" ]] || return 1
  start_time=$(/bin/ps -p "$pid" -o lstart= 2>/dev/null)
  [[ -n "$start_time" ]] || return 1
  print -r -- "$pid:$start_time"
}

current_test_session() {
  local value="${test_sessions[$1]:--}"
  [[ "$value" != "-" ]] || return 1
  print -r -- "$value"
}

stop_owned_service() {
  local pid command
  [[ -f "$PID_FILE" ]] || return 0

  pid="$(/usr/bin/tr -d '[:space:]' < "$PID_FILE")"
  if [[ "$pid" == <-> ]]; then
    command=$(/bin/ps -p "$pid" -o command= 2>/dev/null)
    if [[ -n "$command" && "$command" == *"$SERVER_PATH"* ]]; then
      /bin/kill -TERM "$pid" >/dev/null 2>&1 || true
    fi
  fi

  /bin/rm -f "$PID_FILE"
}

launch_meter() {
  record_event "launch:$1"
  [[ "$DRY_RUN" == "1" ]] || /bin/zsh "$LAUNCHER"
}

stop_meter() {
  record_event "stop:$1"
  if [[ "$DRY_RUN" != "1" ]]; then
    /usr/bin/pkill -x CodexQuotaFloat >/dev/null 2>&1 || true
    stop_owned_service
  fi
}

stop_now() {
  local previous_session="manual"
  [[ -f "$SESSION_FILE" ]] && previous_session="$(<"$SESSION_FILE")"
  stop_meter "$previous_session"
  /bin/rm -f "$SESSION_FILE"
}

if [[ "${1:-}" == "--stop" ]]; then
  stop_now
  exit 0
fi

typeset -i iteration=0
while true; do
  current_session=""
  previous_session=""

  if [[ -n "$TEST_SEQUENCE" ]]; then
    current_session="$(current_test_session "$((iteration + 1))" 2>/dev/null || true)"
  else
    current_session="$(current_codex_session 2>/dev/null || true)"
  fi
  [[ -f "$SESSION_FILE" ]] && previous_session="$(<"$SESSION_FILE")"

  if [[ -n "$current_session" && "$current_session" != "$previous_session" ]]; then
    launch_meter "$current_session" || true
    print -r -- "$current_session" > "$SESSION_FILE"
  elif [[ -z "$current_session" && -n "$previous_session" ]]; then
    stop_meter "$previous_session"
    /bin/rm -f "$SESSION_FILE"
  fi

  ((iteration += 1))
  if [[ -n "$TEST_SEQUENCE" && iteration -ge ${#test_sessions} ]]; then
    break
  fi
  /bin/sleep "$POLL_SECONDS"
done
