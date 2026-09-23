#!/usr/bin/env bash
#
# SessionStart hook (Kimi Code): one fast health check on the Antigravity CLI
# (`agy`) plus linking the plugin's bin/ wrappers onto the model's PATH.
#
# Why the linking step exists: Kimi runs plugin hooks with cwd = plugin root and
# exports KIMI_PLUGIN_ROOT (Claude Code instead interpolated ${CLAUDE_PLUGIN_ROOT}
# into the hooks.json command strings — there is no such interpolation here), but
# KIMI_PLUGIN_ROOT is NOT exported to model-run Bash, so the model's Bash tool
# never sees this plugin's bin/ on PATH. On typical installs ~/.kimi-code/bin IS
# on PATH (the `kimi` binary itself lives there), so we symlink agy-delegate &
# friends into ${KIMI_CODE_HOME:-~/.kimi-code}/bin at every session start. The
# links are cheap, idempotent, and follow plugin updates because they point at
# the live plugin root. Existing commands and unrelated links are preserved.
#
# The health check is ported from the Claude-era check-agy.sh: warn on stderr if
# agy is missing or unusable, but NEVER fail the session (exit 0 always). The
# full health check lives in scripts/doctor.sh — this one stays fast (no
# `agy models` network call) so it doesn't slow every session start.
#
# The stdin payload is deliberately unused: in Kimi, SessionStart is
# observation-only (stdout/return values are ignored — it cannot inject
# context). Policy injection happens via the manifest's systemPromptPath
# (SYSTEM.md) instead. We still drain stdin so a large payload can never
# SIGPIPE the hook.
#
set -uo pipefail

# Drain stdin (payload unused — see header).
cat >/dev/null 2>&1 || true

# --- 1. agy health check (ported from check-agy.sh) --------------------------
if ! command -v agy >/dev/null 2>&1; then
  echo "[antigravity] agy not on PATH — install the Antigravity CLI to enable delegation:" >&2
  echo "[antigravity]   https://antigravity.google/docs/cli-using" >&2
elif ! agy --version >/dev/null 2>&1; then
  echo "[antigravity] agy is on PATH but '--version' failed — it may need authentication (run \`agy\` once)." >&2
fi

# --- 2. Link plugin bin/ into KIMI_CODE_HOME/bin -----------------------------
# KIMI_PLUGIN_ROOT is set for plugin hooks; fall back to this script's parent
# dir (hooks/ -> plugin root) for manual runs outside the plugin runtime.
PLUGIN_ROOT="${KIMI_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SRC="$PLUGIN_ROOT/bin"
DEST="${KIMI_CODE_HOME:-$HOME/.kimi-code}/bin"

if [ ! -d "$SRC" ]; then
  echo "[antigravity] plugin bin/ not found at $SRC — skipping wrapper linking" >&2
elif ! mkdir -p "$DEST" 2>/dev/null; then
  echo "[antigravity] cannot create $DEST — agy-* wrappers will not be on PATH" >&2
else
  for f in "$SRC"/*; do
    # Regular executable files only; every failure is non-fatal.
    [ -f "$f" ] && [ -x "$f" ] || continue
    target="$DEST/$(basename "$f")"
    # A link to this exact shim already follows updates to the managed copy.
    # Do not infer ownership from a basename or replace links to other installs.
    if [ -L "$target" ] && [ "$(readlink "$target")" = "$f" ]; then
      continue
    fi
    # -e misses dangling symlinks; -L keeps those intact too. Directories must
    # be caught before ln, which would otherwise put a link INSIDE them.
    if [ -e "$target" ] || [ -L "$target" ]; then
      echo "[antigravity] wrapper collision at $target — preserved existing entry; use $f directly" >&2
    elif ! ln -sn "$f" "$target" 2>/dev/null; then
      # Another session may have linked the same shim since the checks above.
      if [ ! -L "$target" ] || [ "$(readlink "$target")" != "$f" ]; then
        echo "[antigravity] failed to link $target — existing entries are preserved; use $f directly" >&2
      fi
    fi
  done
fi

exit 0
