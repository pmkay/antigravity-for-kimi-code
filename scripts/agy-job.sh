#!/usr/bin/env bash
#
# agy-job.sh — background-job layer over agy-delegate.sh, à la `codex --background`.
# Fire a long delegation, keep working, then check :status / collect :result.
# This registry does not register a native Kimi Bash completion notification.
# For a direct wrapper call, calculate the enclosing budget with --print-budget.
#
# Usage:
#   agy-job.sh start  [agy-delegate options] "task"   # -> prints a JOB_ID, returns now
#   agy-job.sh list                                    # jobs started from this dir
#   agy-job.sh status <id>                             # running | done(rc) | failed
#   agy-job.sh result <id>                             # print stdout (+rc) when finished
#   agy-job.sh cancel <id>                             # terminate a running job
#
# Jobs live under ${ANTIGRAVITY_JOBS:-~/.antigravity-jobs}/<id>/ (out, err, rc, meta).
#
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DELEGATE="${AGY_DELEGATE:-$HERE/agy-delegate.sh}"
REG="${ANTIGRAVITY_JOBS:-$HOME/.antigravity-jobs}"

die() { echo "agy-job: $*" >&2; exit 1; }

# resolve a (possibly abbreviated) id to a job dir
jobdir() {
  [ -n "${1:-}" ] || die "need a job id"
  if [ -d "$REG/$1" ]; then echo "$REG/$1"; return; fi
  local hits; hits=$(ls -d "$REG/$1"* 2>/dev/null)
  [ -n "$hits" ] || die "no such job: $1"
  [ "$(printf '%s\n' "$hits" | grep -c .)" -eq 1 ] || die "ambiguous id '$1'"
  echo "$hits"
}

# echoes running | done | failed. (rc is read directly from the file by callers —
# a global set here would NOT survive the `$(job_state ...)` command-substitution subshell.)
job_state() {
  local jd="$1" rc
  if [ -f "$jd/rc" ]; then
    rc="$(cat "$jd/rc")"
    if [ "$rc" = "0" ]; then echo "done"; else echo "failed"; fi
  elif [ -f "$jd/pid" ] && kill -0 "$(cat "$jd/pid")" 2>/dev/null; then
    echo running
  else
    echo failed   # pid gone, no rc recorded = crashed/killed
  fi
}

# Human label for a delegate exit code (mirrors agy-delegate.sh structured codes).
rc_label() {
  case "$1" in
    0)  echo 'ok' ;;
    2)  echo 'agy failed' ;;
    3)  echo 'empty output' ;;
    10) echo 'QUOTA — retry later with --continue' ;;
    11) echo 'AUTH required — run `agy` once interactively' ;;
    12) echo 'TIMEOUT — inspect diagnostics and existing edits, verify, then resume the recorded conversation only if work remains (agy 1.1.28+: output may be PARTIAL)' ;;
    129|130|143) echo 'INTERRUPTED — inspect retained diagnostics and workspace edits before retrying' ;;
    13) echo 'agy MISSING — install the Antigravity CLI' ;;
    14) echo 'MODEL unavailable — check `agy models` / tier remap' ;;
    # Both denial shapes: the soft deny (agy 1.1.3+, and again from 1.1.20) and 1.1.13's hard error.
    15) echo 'PERMISSION denied (soft on 1.1.3+, a hard error by 1.1.13, soft again from 1.1.20; named in denied_actions since 1.1.27) — add a permissions.allow rule, or --yolo' ;;
    *)  echo 'error' ;;
  esac
}

cmd="${1:-}"; shift || true
case "$cmd" in
  start)
    [ $# -ge 1 ] || die "start needs delegate args, e.g.  start --tier pro \"task\""
    [ -x "$DELEGATE" ] || die "delegate not executable: $DELEGATE"
    id="$(date +%Y%m%d-%H%M%S)-$$-${RANDOM}"
    jd="$REG/$id"; mkdir -p "$jd"
    { echo "id=$id"; echo "cwd=$PWD"; echo "started=$(date -u +%FT%TZ 2>/dev/null || date)";
      echo "task=$(printf '%s' "${!#}" | tr '\n' ' ' | cut -c1-200)"; } > "$jd/meta"
    (
      nohup "$DELEGATE" "$@" < /dev/null >"$jd/out" 2>"$jd/err" &
      delegate_pid=$!
      echo "$delegate_pid" > "$jd/delegate_pid"
      wait "$delegate_pid"
      echo $? > "$jd/rc"
    ) >/dev/null 2>&1 &
    echo $! > "$jd/pid"
    disown 2>/dev/null || true
    echo "$id"
    ;;
  list)
    [ -d "$REG" ] || { echo "(no jobs)"; exit 0; }
    found=0
    for jd in "$REG"/*/; do
      [ -d "$jd" ] || continue
      cwd="$(sed -n 's/^cwd=//p' "$jd/meta" 2>/dev/null)"
      [ "${ALL:-0}" = "1" ] || [ "$cwd" = "$PWD" ] || continue
      found=1
      st="$(job_state "$jd")"
      printf '%-32s %-8s %s\n' "$(basename "$jd")" "$st" \
        "$(sed -n 's/^task=//p' "$jd/meta" 2>/dev/null)"
    done
    [ "$found" = "1" ] || echo "(no jobs for $PWD — set ALL=1 to see all)"
    ;;
  status)
    jd="$(jobdir "${1:-}")"; st="$(job_state "$jd")"
    rc="$(cat "$jd/rc" 2>/dev/null || true)"
    echo "job:    $(basename "$jd")"
    sed 's/^/  /' "$jd/meta" 2>/dev/null
    if [ -n "$rc" ]; then echo "  state=$st (rc=$rc: $(rc_label "$rc"))"; else echo "  state=$st"; fi
    run_record="$(grep -m1 '^AGY_RUN ' "$jd/err" 2>/dev/null || true)"
    if [ -n "$run_record" ]; then echo "  run=${run_record#AGY_RUN }"; fi
    sig="$(grep -m1 '^AGY_SIGNAL ' "$jd/err" 2>/dev/null || true)"
    if [ -n "$sig" ]; then echo "  signal=${sig#AGY_SIGNAL }"; fi
    ;;
  result)
    jd="$(jobdir "${1:-}")"; st="$(job_state "$jd")"
    if [ "$st" = "running" ]; then echo "still running — try again later"; exit 2; fi
    rc="$(cat "$jd/rc" 2>/dev/null || true)"
    [ -s "$jd/err" ] && { echo "----- stderr -----" >&2; cat "$jd/err" >&2; }
    cat "$jd/out" 2>/dev/null
    echo "[exit rc=${rc:-?}${rc:+: $(rc_label "$rc")}]" >&2
    ;;
  cancel)
    jd="$(jobdir "${1:-}")"
    if [ -f "$jd/rc" ]; then echo "not running"; exit 0; fi
    pid="$(cat "$jd/pid" 2>/dev/null || true)"
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      # Let the wrapper clean its process group and the worker collect its exit
      # code. Killing the worker first loses the result and can leave writers alive.
      # A start may have just returned before the delegate PID was written.
      for _ in 1 2 3 4 5 6 7 8 9 10; do
        [ -s "$jd/delegate_pid" ] && break
        sleep 0.1
      done
      delegate_pid="$(cat "$jd/delegate_pid" 2>/dev/null || true)"
      if [ -n "$delegate_pid" ]; then
        # Only signal a current child of this worker, not a recycled stored PID.
        actual_parent="$(ps -o ppid= -p "$delegate_pid" 2>/dev/null | tr -d '[:space:]')"
        if [ "$actual_parent" = "$pid" ]; then
          kill -TERM "$delegate_pid" 2>/dev/null || true
        elif [ -n "$actual_parent" ] && [ ! -f "$jd/rc" ]; then
          echo "worker identity changed; inspect job state before cancelling"
          exit 2
        fi
      else
        # Compatibility with jobs started by older plugin versions.
        pkill -TERM -P "$pid" 2>/dev/null || true
      fi
      for _ in 1 2 3 4 5 6 7 8 9 10; do
        [ -f "$jd/rc" ] && break
        sleep 0.5
      done
      if [ -f "$jd/rc" ]; then
        echo "cancelled $(basename "$jd") (rc=$(cat "$jd/rc"))"
      else
        echo "cancellation requested for $(basename "$jd"); confirm worker exit before retrying"
        exit 2
      fi
    else
      echo "not running"
    fi
    ;;
  ""|-h|--help|help)
    sed -n '/^# Usage:/,/^# Jobs live/p' "$0" | sed 's/^# \{0,1\}//' ;;
  *) die "unknown subcommand '$cmd' (start|list|status|result|cancel)" ;;
esac
