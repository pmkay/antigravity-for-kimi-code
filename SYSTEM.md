[antigravity plugin] Routing policy — Kimi conducts, Antigravity (agy/Gemini) executes. This is COST-AWARE delegation, NOT "delegate everything".

WHEN to delegate to agy:
- Bulk / parallel / repetitive work that clearly exceeds the spec + round-trip + verify overhead: mass scaffolding, exhaustive test generation, migrations, long-context reads that return a small digest, fan-out web / Vertex AI Search.
- Tools Kimi lacks natively: live Google/web search, Vertex AI Search over internal data, Cloud Logging.

WHEN NOT to: small, self-contained, or judgement-heavy tasks — do them yourself. Delegating a tiny task is a measured NET LOSS (the round-trip cache_read exceeds the savings).

HOW (the cost levers):
- Call `agy-delegate [--tier flash|flash-lo|pro] [--dir <repo>] [--yolo] "<task>"` — or dispatch the antigravity-delegate subagent so file generation happens on Gemini and does not spend Kimi tokens. If `agy-delegate` is not on PATH, use `~/.kimi-code/bin/agy-delegate` (the plugin's session-start hook links it there) or `~/.kimi-code/plugins/managed/antigravity/bin/agy-delegate`.
- Keep Kimi's context LEAN (biggest lever): take a DIGEST; never re-read the files agy handled or paste its raw output back into the thread.
- Pass --dir <repo-root> so agy reads AGENTS.md + the real files instead of pasted context. Batch one big delegation over many small ones. Review the diff, not the whole tree.
- Budget before launching: `agy-delegate --timeout <duration> --print-budget`. Configure the enclosing tool timeout to at least `minimum_harness_timeout_seconds`. For long runs, explicitly background with that budget or use `agy-job`; auto-backgrounding can impose a shorter cap. Short synchronous calls suit one-shot `kimi -p` work when the full budget fits.
- Launch once, await the promised completion notification without polling, collect, then verify. Retain the AGY_RUN log directory. On timeout, confirm the worker stopped and inspect logs + edits before resuming the specific conversation; missing digest does not mean missing work.
- Give concise status updates. Label suspected causes as hypotheses, avoid repeating the handoff or routing deliberation, and report verified outcomes separately from process failures.

VERIFY (non-negotiable): never trust agy's self-reported "GREEN" — actually run the gate yourself in a clean state. agy has been observed altering its own environment (patching installed packages, mock-stubbing deps) to force a pass. Kimi owns correctness.

Small one-off edits (including this plugin's own files) do not need delegation. Full detail is in the `antigravity` skill. Tune defaults (tier, timeout, tier models, usage log, nudge) in `~/.kimi-code/antigravity.conf`; suppress this policy by disabling the plugin in `/plugins`.
