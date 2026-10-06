---
description: Delegate a well-scoped subtask to Antigravity (agy/Gemini), collect the result, then verify.
argument-hint: "[--tier flash|flash-lo|pro] <task>"
---

Task: $ARGUMENTS

Follow the `antigravity` skill. Use this lifecycle once per delegation:

1. **Specify.** Pick a tier (`flash` by default), pass `--dir <repo-root>`, and give
   the observed symptom, relevant paths, constraints, and verification commands.
   Label suspected causes as hypotheses; require the executor to establish the
   cause before changing behavior. Preserve intentional behavior such as snapshots.
   For visual changes, include a browser check under the reported loading conditions.
   Use `--digest` for a compact result with changed files, cause, and test evidence.
   Do not repeatedly draft the same prompt or narrate the routing deliberation.
2. **Grant.** Use an existing `permissions.allow` rule when it covers the work.
   A `write_file(<dir>)` rule grants recursive file writes; terminal and other tools
   need their own grant or `--yolo`, which auto-approves all agy tools. Run writes on
   a dedicated branch/worktree and review the diff. `--dir` and `--sandbox` do not
   contain `--yolo`. Review the complete wrapper command through Kimi's approval
   flow. See [permission troubleshooting](../docs/TROUBLESHOOTING.md) if a grant fails.
3. **Budget and launch.** Run `agy-delegate --timeout <duration> --print-budget`
   first. Set the enclosing Bash task's timeout to at least
   `minimum_harness_timeout_seconds`; this command does not set the tool timeout.
   If that exceeds the foreground limit, launch with `run_in_background: true` and
   an explicit timeout from the start, or use `agy-job start` with an explicit
   `--timeout`. Do not depend on foreground auto-backgrounding and its default cap.
   For `--timeout 15m`, the wrapper guard is 1,020s and the minimum harness budget
   is 1,080s; a 1,200s Bash background budget leaves further headroom.
4. **Await and collect.** Keep the `AGY_RUN` log directory or job ID. If Bash says
   `automatic_notification: true` and instructs you not to poll, await that event;
   do not call `TaskOutput` until completion. For `agy-job`, use its status/result
   commands; job start itself does not register a Kimi completion notification.
   Empty output means no result has been collected, not proof of progress or a hang.
   Give one short launch update and report meaningful changes only.
5. **Recover before retrying.** After a timeout/interruption, confirm the previous
   worker has stopped, inspect retained diagnostics and `git status`/`git diff`,
   then verify existing edits. Useful or complete edits may exist without a digest.
   If work remains, resume the recorded conversation with `--conversation <id>`
   when available, with a corrected budget and only the remaining scope. Avoid
   `--continue` when another run may have become the most recent conversation.
   Never automatically re-dispatch the original write task on an unknown state.
6. **Verify and report.** Review the diff and run the relevant checks independently.
   Report the result, evidence, and remaining limitations. Distinguish a failed
   delegation process from a verified code change; neither implies the other.

Invoke `agy-delegate` or `agy-job` by its bare name. If unavailable, use
`~/.kimi-code/bin/<name>` or `~/.kimi-code/plugins/managed/antigravity/bin/<name>`,
substituting the configured `KIMI_CODE_HOME` when applicable.

Short synchronous runs remain suitable for one-shot `kimi -p` work when the full
budget fits. Full timeout and recovery details: [delegation lifecycle](../docs/DELEGATION-LIFECYCLE.md).
