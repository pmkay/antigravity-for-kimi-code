# Security policy

This is a community project (MIT, not affiliated with Google, Anthropic, or Moonshot AI). It
orchestrates the third-party `agy` CLI and runs shell commands on your machine, so
security reports are genuinely appreciated.

## Reporting a vulnerability

**Preferred:** use GitHub's private vulnerability reporting —
**Security → Report a vulnerability** on this repository
(https://github.com/pmkay/antigravity-for-kimi-code/security/advisories/new).
This keeps details private until a fix is available.

If that isn't available to you, open a normal issue describing the impact and a
non-destructive repro, and note that you'd prefer to coordinate privately — a
maintainer will follow up with a private channel.

Please include: affected file/commit, impact (what a malicious/injected input could
do), and a **non-destructive** proof-of-concept (exit codes / policy decisions, not
`rm -rf` — some endpoint security will kill the process on such strings).

## Scope — what matters most here

- **`hooks/nudge-delegation.sh` / `hooks/session-start.sh`** — they run on every prompt /
  session start, and the nudge's stdout is appended to the model's context. The nudge
  text is a **fixed string by design** — the user's prompt is never echoed back — so
  there is no escaping/injection surface to widen. A change that starts interpolating
  prompt or repo content into hook output is a security bug.
- **`scripts/agy-delegate.sh` / `agy-job.sh`** — the wrappers that invoke `agy`.
- **`agents/antigravity-delegate.md`** — the delegate subagent's contract (see the
  threat-model note below). Changes that widen its tool allowlist or loosen the
  "only the delegation wrappers" rule deserve disproportionate scrutiny.
- Trust boundary reminder: `agy` output and repo contents are **untrusted** — the plugin
  treats agy as a tool whose results Kimi must verify, never as a trusted authority.

## Threat model — the subagent gate, then and now

**Claude-era (removed):** the original plugin's *only* hard restriction on what the
prompt-injectable `antigravity-delegate` subagent could run via Bash was a per-subagent
`PreToolUse` hook, `hooks/validate-delegate-bash.sh` (allowlist: the delegation
wrappers, bare names only, no pipelines). A bypass there was arbitrary command execution
under prompt injection — the highest-severity class this project has, and the subject of
**GHSA-hwv2-vjgj-8rcv** (CVSS 8.6: basename authentication, living-off-the-land `git`,
and `cat $SECRET | agy-delegate -` exfiltration, all fixed in 0.25.0). That history is
kept as background because the *attack surface* — a subagent that runs shell commands on
behalf of untrusted-looking tasks — did not change.

**Kimi Code (current):** the per-agent gate is gone. Kimi plugin hooks are global;
there is no per-agent `PreToolUse` point to hang the old allowlist on. The delegate
has `tools: Bash, Read, Glob`. Omitting `Write`/`Edit` removes those dedicated tools,
but **Bash can still write files and execute arbitrary commands**.

The wrapper-only rule is a **prompt contract**: the agent is instructed to call
`agy-delegate` / `agy-job` without shell chaining, pipes, redirections, or command
substitution, and use `Read` / `Glob` for inspection. The platform does not enforce
that contract. Keep Kimi's approval flow enabled and review the entire command.
Blanket prefix allow rules can bypass that review; the documented command-pattern
matching suggests a wrapper prefix could also match a chained command. This is an
inference from [Kimi's permission rules](https://www.kimi.com/code/docs/en/kimi-code-cli/configuration/config-files#permission),
not a verified shell-parser guarantee. Remove any wrapper prefix allow rules
copied from earlier setup guidance; the plugin does not edit your configuration.
Never-ask modes remove the approval stop altogether.

Hard confinement requires a purpose-built restricted tool with validated arguments
and no shell evaluation, or an external execution boundary. This plugin provides
neither. The wrapper's agy-side permissions must also be considered: `--yolo` grants
agy broad tool access, regardless of the delegate's prompt contract.

Consequences worth a report: a way to make the subagent (or the main agent, via the
nudge/policy text) run something outside the wrapper contract **without an approval
prompt**; hook output that can be steered by untrusted repo content; wrapper argument
handling that smuggles extra flags through to `agy`.

## Not in scope

- Vulnerabilities in the upstream Antigravity CLI (`agy`) itself — report those to
  https://github.com/google-antigravity/antigravity-cli.
- Cost/quota surprises from using `--yolo` or delegating large jobs (documented behavior).

## Supported versions

Fixes land on the latest release. Update by re-installing
(`/plugins install https://github.com/pmkay/antigravity-for-kimi-code`) and `/reload`;
the `version` in `kimi.plugin.json` is what a re-install picks up.
