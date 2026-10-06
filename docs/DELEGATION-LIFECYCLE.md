# Delegation lifecycle

A missing digest is a process outcome. Files may already be edited and tests may
already have run. Inspect and verify that work before deciding whether to resume.

## Choose a budget before launch

```bash
agy-delegate --timeout 15m --print-budget
```

This read-only command needs neither a prompt nor agy. It prints:

```json
{"print_timeout_seconds":900,"guard_timeout_seconds":1020,"minimum_harness_timeout_seconds":1080}
```

There are three deadlines: agy's print timeout, the wrapper's wall-clock guard,
and the enclosing tool/task timeout. The guard adds 25% (minimum 10s, maximum
120s) to the print timeout. The harness budget adds another 60s for startup,
termination, and result processing. Configure the enclosing task to allow at least
that budget; `--print-budget` cannot change a parent tool's deadline.

For a 15-minute run, use an explicit Bash background timeout of at least 1,080s
(1,200s gives more headroom), with `run_in_background: true` from the start. A
foreground call that auto-backgrounds can inherit a separate, shorter cap. One
reported run was terminated after 280s foreground + 600s background = 880s, before
agy's 900s timeout or the wrapper's 1,020s guard could report a result.

Alternatively, use `agy-job start --timeout 15m ...`, retain the job ID, and collect
with `agy-job status <id>` / `agy-job result <id>`. This job engine does not itself
register a Kimi Bash completion notification. When a native Bash task explicitly
promises an automatic notification and says not to poll, await that event instead.

GNU `timeout` or macOS `gtimeout` is required for the wall-clock guard. Without it,
agy's own timeout still applies, but a startup hang has no wrapper deadline. The
launch record reports `wall_clock_guard_available`; retain a finite harness limit.

## Inspect persistent diagnostics

Before probing or running agy, the wrapper emits one `AGY_RUN` JSON record to
stderr. It names a unique `run_id`, absolute `log_dir`, wrapper PID, start time,
and timeout budgets. It describes a launched run, not successful work or progress.

Records live under `${KIMI_CODE_HOME:-~/.kimi-code}/antigravity-runs`, or the
`AGY_RUNS_DIR` environment/config override. Each run directory is private (0700).
The stdout contract is unchanged: the caller gets the response/digest after agy
returns, while the original streams are captured directly to files during the run.

| File | Meaning |
| --- | --- |
| `run.json` | Immutable launch metadata |
| `state` | Last recorded phase: starting, probing, running, processing, done, failed, interrupted |
| `child_pid` | Last launched child process-group leader; may already have exited |
| `stdout`, `stderr` | Raw agy output, possibly partial or empty |
| `help`, `help.stderr` | Capability-probe output, if the probe ran |
| `events.log` | Available `AGY_USAGE` and `AGY_SIGNAL` records; usage includes the conversation ID when agy returns it |
| `response`, `error`, `denied_actions` | Decoded JSON fields, when available |
| `exit_code`, `ended_at`, `interruption` | Completion records written by the exit handler |

The wrapper retains these files on success and failure. They can contain code or
other sensitive tool output. There is no automatic pruning; delete completed run
directories when their diagnostics are no longer needed. `AGY_USAGE_LOG` remains
an optional additional accounting log.

Empty logs do not prove a hang: agy may buffer its response. A recorded `running`
state is not a live health check. SIGKILL cannot run an exit handler, so a forcibly
killed wrapper can leave a stale phase and no exit code. Check the actual worker
before retrying; never kill a reused PID based on an old record alone.

## Recover useful work

1. Confirm the previous worker has stopped. On HUP/INT/TERM, the wrapper terminates
   its child process group, gives it a short grace period, and escalates to KILL.
   SIGKILL cannot trigger cleanup; children that start their own sessions also
   escape the group. Check for remaining writers after external termination.
2. Inspect the retained logs and the workspace diff. Preserve valid edits and run
   the relevant checks independently. A missing digest does not mean no work was done.
3. If the changes satisfy the task, report verified success alongside the process
   interruption. If verification fails or work remains, report the remaining scope.
4. Resume the specific recorded conversation with `--conversation <id>` when
   available. Correct the timeout budget first. Do not use an unrelated latest
   conversation or launch a second writer while the previous worker is still active.

`agy-job cancel` signals the delegation wrapper and allows it to clean up before
collecting its exit code. If cancellation is still pending, it reports that state
rather than claiming the job has stopped. The wrapper reports HUP/INT/TERM as
129/130/143; agy or wrapper deadlines still map to exit 12 (TIMEOUT).

Keep updates short: announce the launch, meaningful changes, and the verified
result. Keep competing hypotheses in the task specification until evidence resolves
them. A lifecycle record is not a reason to narrate every internal decision.
