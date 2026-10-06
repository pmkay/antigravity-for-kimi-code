# shellcheck shell=bash
# Persistent diagnostics and process-group cleanup for agy-delegate. Bash 3.2.
# Usage: source this file, call start_run, then run_child out err command [args].

run_json_string() {
  local value="$1" char code i
  printf '"'
  for ((i=0; i<${#value}; i++)); do
    char="${value:i:1}"
    case "$char" in
      '"') printf '\\"' ;;
      '\') printf '\\\\' ;;
      *) printf -v code '%d' "'$char"
         if [ "$code" -lt 32 ]; then printf '\\u%04x' "$code"; else printf '%s' "$char"; fi ;;
    esac
  done
  printf '"'
}

stop_run_child() {
  [ -n "${RUN_PID:-}" ] || return 0
  # run_child gives the command its own process group, including ordinary MCP/
  # terminal descendants. A child that deliberately creates a new session escapes
  # this group; this is lifecycle cleanup, not an execution sandbox.
  local i
  kill -TERM -- "-$RUN_PID" 2>/dev/null || true
  for ((i=0; i<20; i++)); do
    kill -0 -- "-$RUN_PID" 2>/dev/null || break
    sleep 0.1
  done
  kill -KILL -- "-$RUN_PID" 2>/dev/null || true
  wait "$RUN_PID" 2>/dev/null || true
  RUN_PID=""
}

finish_run() {
  local rc=$? state=failed
  trap - EXIT
  trap '' HUP INT TERM
  stop_run_child
  [ "$rc" -eq 0 ] && state="done"
  [ -n "$RUN_INTERRUPTED" ] && state=interrupted
  # Keep raw output even on success: an external SIGKILL cannot run a trap, so
  # diagnostics must already be durable before the command starts.
  printf '%s\n' "$rc" > "$RUN_DIR/exit_code"
  printf '%s\n' "$(date +%s)" > "$RUN_DIR/ended_at"
  printf '%s\n' "$RUN_INTERRUPTED" > "$RUN_DIR/interruption"
  printf '%s\n' "$state" > "$RUN_DIR/state"
  exit "$rc"
}

start_run() {
  local root="${AGY_RUNS_DIR:-${KIMI_CODE_HOME:-$HOME/.kimi-code}/antigravity-runs}" started event guard=false
  (umask 077; mkdir -p "$root") || die "cannot create run directory: $root"
  root="$(cd "$root" && pwd -P)" || die "cannot resolve run directory: $root"
  RUN_DIR="$(mktemp -d "$root/run.XXXXXXXX")" || die "cannot create run diagnostics in $root"
  RUN_PID=""; RUN_INTERRUPTED=""
  trap finish_run EXIT
  trap 'RUN_INTERRUPTED=HUP; exit 129' HUP
  trap 'RUN_INTERRUPTED=INT; exit 130' INT
  trap 'RUN_INTERRUPTED=TERM; exit 143' TERM
  started="$(date +%s)"
  [ -n "$TO_CMD" ] && guard=true
  event="$(printf '{"run_id":'; run_json_string "${RUN_DIR##*/}"
    printf ',"log_dir":'; run_json_string "$RUN_DIR"
    printf ',"wrapper_pid":%s,"started_at":%s,"print_timeout_seconds":%s,"guard_timeout_seconds":%s,"minimum_harness_timeout_seconds":%s,"wall_clock_guard_available":%s}' \
      "$$" "$started" "$PRINT_SECS" "$TO_SECS" "$HARNESS_SECS" "$guard")"
  (umask 077
    printf '%s\n' "$event" > "$RUN_DIR/run.json"
    printf '%s\n' starting > "$RUN_DIR/state"
    : > "$RUN_DIR/stdout"; : > "$RUN_DIR/stderr"; : > "$RUN_DIR/events.log"
  ) || die "cannot initialize run diagnostics: $RUN_DIR"
  printf 'AGY_RUN %s\n' "$event" >&2
}

run_child() {
  local out="$1" err="$2" rc
  shift 2
  # Monitor mode assigns a separate process group without requiring setsid (not
  # shipped on macOS). Wait on an asynchronous child so TERM interrupts wait and
  # runs our trap immediately, instead of waiting for a foreground command.
  set -m
  "$@" < /dev/null >"$out" 2>"$err" &
  RUN_PID=$!
  set +m
  printf '%s\n' "$RUN_PID" > "$RUN_DIR/child_pid"
  if wait "$RUN_PID"; then rc=0; else rc=$?; fi
  stop_run_child
  return "$rc"
}
