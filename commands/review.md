---
description: Get an independent cross-model review of the current diff from Antigravity (Gemini), then reconcile as the final judge.
argument-hint: "[--adversarial] [scope: paths or git range]"
---

Use Antigravity (`agy` / Gemini) as an **independent, different-model reviewer** of the
current changes, then reconcile the findings yourself (you are the final judge).

Scope/flags: $ARGUMENTS

Do this:
1. Capture the diff: `git diff` (or the range/paths in the scope above; default to
   uncommitted + last commit if unspecified).
2. Delegate the review to agy (pro tier) — pipe the diff in on stdin:
   `git diff | agy-delegate --tier pro -`
   (This pipe form is a **main-agent pattern** — it runs as YOU, the conductor. Do not
   ask the `antigravity-delegate` subagent to do it: its contract restricts it to bare
   `agy-delegate`/`agy-job` invocations with no pipelines (the Claude-era gate that
   enforced this, GHSA-hwv2-vjgj-8rcv, is gone on Kimi, but the restriction stands —
   `git` with arbitrary arguments executes arbitrary commands and `cat` feeding the
   wrapper ships any file to the external model). If you delegate this step, pass `--dir`.)
   with an instruction to find correctness/security/performance bugs, be skeptical, and
   list each as `file:line — issue`. If `--adversarial` is set, also have it challenge the
   design decisions and tradeoffs, not just line bugs.
3. **Reconcile**: for each finding, corroborate it against the actual code. Drop false
   positives; keep what's real. Agreement across two model families is a stronger signal;
   disagreement is a prompt to look closer.
4. Report the reconciled findings (most severe first) and your verdict.
