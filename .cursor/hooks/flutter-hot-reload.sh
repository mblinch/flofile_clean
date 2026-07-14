#!/usr/bin/env bash
# Hot-reload the running Flutter app after Dart file edits.
# Sends "r" to the flutter run terminal for this project (debounced).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
STATE_DIR="${TMPDIR:-/tmp}/cw_flutter_hot_reload"
mkdir -p "$STATE_DIR"
TOKEN_FILE="$STATE_DIR/token"
LOG_FILE="$STATE_DIR/last.log"

input="$(cat || true)"
file_path="$(printf '%s' "$input" | jq -r '.file_path // empty' 2>/dev/null || true)"

# Only reload for Dart sources (UI/logic). Other files often need a full restart.
case "$file_path" in
  *.dart) ;;
  *) exit 0 ;;
esac

# Ignore edits outside this repo
case "$file_path" in
  "$REPO_ROOT"/*) ;;
  *) exit 0 ;;
esac

find_flutter_run_tty() {
  local pid cwd tty
  # flutter run shows up as dartvm running flutter_tools.snapshot run
  while IFS= read -r pid; do
    [[ -z "$pid" ]] && continue
    cwd="$(lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -1 || true)"
    if [[ "$cwd" == "$REPO_ROOT" ]]; then
      tty="$(ps -o tty= -p "$pid" 2>/dev/null | tr -d '[:space:]' || true)"
      if [[ -n "$tty" && "$tty" != "??" && -c "/dev/$tty" ]]; then
        printf '%s\n' "/dev/$tty"
        return 0
      fi
    fi
  done < <(pgrep -f 'flutter_tools\.snapshot[[:space:]]+run' 2>/dev/null || true)
  return 1
}

# Debounce: last edit within the window wins, then one reload fires.
token="$(date +%s%N 2>/dev/null || date +%s)-$RANDOM"
printf '%s\n' "$token" > "$TOKEN_FILE"

(
  sleep 1
  current="$(cat "$TOKEN_FILE" 2>/dev/null || true)"
  if [[ "$current" != "$token" ]]; then
    exit 0
  fi

  tty_path="$(find_flutter_run_tty || true)"
  if [[ -z "${tty_path:-}" ]]; then
    printf '%s\n' "$(date '+%Y-%m-%d %H:%M:%S') no flutter run tty for $REPO_ROOT (edited: $file_path)" >> "$LOG_FILE"
    exit 0
  fi

  # Flutter interactive "r" = hot reload through the frontend server
  if printf 'r' > "$tty_path" 2>>"$LOG_FILE"; then
    printf '%s\n' "$(date '+%Y-%m-%d %H:%M:%S') hot reload -> $tty_path (edited: $file_path)" >> "$LOG_FILE"
  else
    printf '%s\n' "$(date '+%Y-%m-%d %H:%M:%S') failed writing to $tty_path (edited: $file_path)" >> "$LOG_FILE"
  fi
) >/dev/null 2>&1 &

exit 0
