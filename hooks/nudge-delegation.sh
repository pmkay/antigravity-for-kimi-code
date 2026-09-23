#!/usr/bin/env bash
#
# UserPromptSubmit hook (Kimi Code): a cheap, deterministic nudge toward
# delegation when the user's prompt LOOKS like bulk work above the delegation
# break-even.
#
# Kimi semantics: anything this hook prints on stdout is appended to the model's
# context as plain text — no hookSpecificOutput JSON wrapper (that was Claude
# Code's wire format). Exit 2 would block the prompt; we never block. The
# payload's `prompt` field is NOT a string: it is an array of content blocks,
# [{"type":"text","text":"..."}] (plus an `is_steer` flag), so the extractor
# below joins the text blocks (and still accepts a bare string, defensively,
# for older/legacy shapes).
#
# Design principle: this supplies judgment MATERIAL — the DECISION stays with
# Kimi (per the skill's cost discipline). It never forces a delegation and it
# never fires the wrapper itself: full automation is a measured net loss below
# the break-even, so the break-even call must remain a per-task judgment.
#
# Heuristic is deliberately conservative (volume/fan-out phrases, EN + JA), and
# the nudge text is a FIXED string — the user's prompt is never echoed back into
# the context (no escaping/injection surface).
#
# Toggle via AGY_DELEGATION_NUDGE (off/false/0/no/disabled), loaded from
# ${AGY_CONFIG:-${KIMI_CODE_HOME:-~/.kimi-code}/antigravity.conf} by
# scripts/lib-config.sh; the environment wins over the file. Default: on.
#
set -uo pipefail

# Plugin hooks run with cwd = plugin root under Kimi, but derive lib-config's
# path from the script location so the hook also works when run by hand.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)/lib-config.sh"

raw="$(printf '%s' "${AGY_DELEGATION_NUDGE:-on}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
case "$raw" in off|false|0|no|disabled) exit 0 ;; esac

IN="$(cat 2>/dev/null || true)"
[ -n "$IN" ] || exit 0

# Extract ONLY the prompt text (matching on the whole payload would false-positive
# on cwd/paths). python3 is already a plugin dependency (measure-session, agy-trace).
PROMPT="$(printf '%s' "$IN" | python3 -c 'import json,sys
try:
    p = json.load(sys.stdin).get("prompt", "")
    if isinstance(p, list):
        print("\n".join(b.get("text", "") for b in p if isinstance(b, dict) and b.get("type") == "text"))
    elif isinstance(p, str):
        print(p)
except Exception: pass' 2>/dev/null || true)"
[ -n "$PROMPT" ] || exit 0

# Already delegating explicitly? Stay quiet.
case "$PROMPT" in *antigravity*|*agy-delegate*|*agy-job*) exit 0 ;; esac

shopt -s nocasematch
HIT=0
case "$PROMPT" in
  *"all files"*|*"every file"*|*"across the codebase"*|*"entire codebase"*|*"whole repo"*| \
  *migrate*|*migration*|*"generate tests"*|*"test coverage"*|*"exhaustive test"*| \
  *scaffold*|*boilerplate*|*"deep research"*|*"web search"*| \
  *一括*|*全ファイル*|*すべてのファイル*|*網羅*|*移行*|*大量*|*横断*|*リポジトリ全体*)
    HIT=1 ;;
esac
shopt -u nocasematch
[ "$HIT" -eq 1 ] || exit 0

# Fixed nudge, plain text on stdout (Kimi appends stdout to the model's context).
# Note the explicit "the judgment is yours" — this is material, not a mandate.
cat <<'EOF'
[antigravity plugin] This prompt looks like BULK work (mass edits / migration / exhaustive tests / fan-out search) — possibly above the delegation break-even. CONSIDER routing the bulk part to the antigravity-delegate subagent (or agy-delegate --digest) so it runs on the cheap executor, then verify its digest. THE JUDGMENT IS YOURS: if the task is actually small, self-contained, or judgement-heavy, do it yourself — delegating below the break-even is a measured net loss. Decide silently; don't mention this notice.
EOF
exit 0
