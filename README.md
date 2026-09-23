<div align="center">

# 🛰️ Antigravity for Kimi Code

> **Fork of [Antigravity for Claude Code](https://github.com/yuting0624/antigravity-for-claude-code)**, originally created by **[linyuting (@yuting0624)](https://github.com/yuting0624)**. This repository adapts that work for Kimi Code.

**Run the Antigravity CLI (Gemini) as a collaborating sub-agent, right inside Kimi Code.**
![Antigravity for Kimi Code — Kimi Code directing, Gemini executing](docs/hero.png)
Kimi conducts the judgement; Gemini does the heavy lifting — intelligent model routing across the SDLC.

[![CI](https://github.com/pmkay/antigravity-for-kimi-code/actions/workflows/ci.yml/badge.svg)](https://github.com/pmkay/antigravity-for-kimi-code/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
![Kimi Code plugin](https://img.shields.io/badge/Kimi%20Code-plugin-1E88E5)
[![Antigravity CLI](https://img.shields.io/badge/Antigravity%20CLI-agy-4285F4?logo=googlegemini&logoColor=white)](https://antigravity.google/docs/cli-using)

</div>

**Kimi port: 0.29.1.** See [CHANGELOG.md](CHANGELOG.md) for the release details.

> **Port scope:** Kimi Code replaces Claude Code as the conductor; the executor (`agy`) is unchanged. Claude-era differences are called out where they matter, and the measured A/B data below comes from the original project and is labelled as such.

---

## ⚡ Quick look

![Antigravity delegation demo](docs/demo.gif)

Kimi stays the conductor; the bulk, token-heavy read runs on cheaper Gemini, and Kimi verifies the result. *(Gif recorded on the Claude Code original — the workflow on Kimi Code is the same.)*

---

## 💡 Why

| | Kimi (conductor) | Gemini / `agy` (executor) |
|---|---|---|
| **Owns** | requirements · architecture · the hard 20% · **verification** · review | scaffold · implementation · test generation · search |
| **Strength** | judgement | cheap, fast throughput |

```
you → Kimi Code (conduct: design / verify / review)
         └── agy → Gemini (execute: implement / test / search)
```

> *Generation is solved; verification, judgement, and direction are the craft.*

## ✨ What it does

- **Routes work across the SDLC** — Kimi keeps the judgement calls; Antigravity handles scaffolding, **test generation**, **first-pass review**, and **migrations** under a shared `AGENTS.md`.
- **Adds Gemini-powered research and cloud workflows** — **Google/web search**, **Vertex AI Search** over your internal data, deep research, and Cloud Logging. Kimi reviews and re-checks the results.
- **Hears audio, watches video** — `/antigravity:media` delegates the perception to Gemini (natively multimodal, **no local ffmpeg/Whisper stack**): you get a **timestamped digest** while the full transcript is written to a file, so a 1-hour recording never lands in Kimi's context.
- **Cross-model verification** — an independent, different-model opinion on your code.
- **Background jobs** — fire a long delegation, keep working, collect later.
- **Internal fan-out** — one delegation, and agy spawns its own subagents on the cheap side (dynamic `define_subagent` on agy ≥ 1.0.16; `TypeName "self"` + Role on any version); each leaves a **readable trajectory** you audit with `agy-trace`.
- **Built-in cost discipline** — measured, not guessed (see below).
- **Loads the routing policy automatically** — [`SYSTEM.md`](SYSTEM.md) is included through the plugin manifest's `systemPromptPath`. The `antigravity-delegate` subagent is instructed to route file generation through agy/Gemini to reduce Kimi output tokens. This is a prompt contract; it does not restrict Bash execution.
- **No slash command required** — the delegate subagent is picked up **proactively** for bulk
  work, and a prompt-level nudge flags bulk-looking requests as delegation candidates.
  Both are advisory: **the break-even judgment stays with Kimi** (full auto-routing is a
  measured net loss below the break-even), and the nudge is toggleable (`AGY_DELEGATION_NUDGE`).

## 📊 Measured results

On a **large** ADK multi-agent build (+ `adk eval`), same task / same model, 3 ways:

| | Claude solo @high | solo @max | **hybrid** |
|---|---|---|---|
| frontier cost (COST-WEIGHTED) | 2.62M | 5.34M | **1.91M** |
| quality (`adk eval`) | ✅ 3/3 | ✅ 3/3 | ✅ **3/3** |

→ **−27% vs solo@high, −64% vs solo@max, at equal quality** — and the cheap Gemini work isn't even counted. Savings scale with task size; tiny one-off tasks are cheaper to just run on the conductor. Full A/B: [`docs/AB-RESULTS.md`](docs/AB-RESULTS.md).

> **Claude-era data:** these arms were measured with **Claude as conductor** on the original plugin (headless `claude -p`, Opus). The cost driver it isolates — the conductor re-reading context every turn (`cache_read` × turns) — is conductor-agnostic, and the same methodology carries over: with Kimi as conductor the numbers come from `scripts/measure-session.py` reading Kimi's own session records. Re-measurement on Kimi K3 is welcome (see CONTRIBUTING).

> **Note on cost figures:** `measure-session` sums token usage recorded by Kimi; `agy-cost-compare` estimates tokens from character counts. Dollar figures use the rates in [`prices.json`](prices.json). For quota-based Kimi Code subscriptions, the API rate deck is a comparison proxy, not your bill. The Claude-era percentages above are not measured Kimi savings. **Set your real rates before quoting any figure.**

## 🚀 Install

**Requirements:**

- [Kimi Code CLI](https://moonshotai.github.io/kimi-code/) ≥ 2.x.
- [Antigravity CLI](https://antigravity.google/docs/cli-using) (`agy`) installed and authenticated; `agy models` should list models available to your account.
- Bash 3.2+ and Python 3 on PATH. Python powers the prompt nudge, usage accounting, and structured-output parsing.
- Recommended: GNU `timeout` (or `gtimeout` on macOS) for the wrapper's outer timeout guard. Without it, a stalled agy process may outlive its own print timeout.

In the Kimi Code TUI:

```
/plugins install https://github.com/pmkay/antigravity-for-kimi-code
/reload
```

Then **start a new session** so the startup hook can link the wrappers, and run:

```text
/antigravity:setup
```

This checks agy installation/authentication and the plugin scripts.

A local path works too (`/plugins install ~/antigravity-for-kimi-code`). Plugins install **per-user, across all projects**. Paths below use the default `~/.kimi-code`; substitute your `KIMI_CODE_HOME` if customized.

- **Installs are copied.** Kimi runs the managed copy at `~/.kimi-code/plugins/managed/antigravity/`. After editing your checkout or updating the plugin, re-install and `/reload`, then start a new session to run the startup hook.
- **Startup links the wrappers.** The hook creates missing links in `~/.kimi-code/bin` and reuses links already pointing to this install. That directory must be on PATH for bare commands such as `agy-delegate` to work.
- **Existing commands are preserved.** Regular files, directories, and unrelated symlinks—including broken links or links to another install—are left intact. A collision warning prints the direct plugin wrapper path to use. Inspect the existing entry before moving or removing it.
- **Commands are namespaced:** `/antigravity:<name>`.

If a wrapper is missing from PATH or its name collides, run the managed copy directly, for example:

```bash
~/.kimi-code/plugins/managed/antigravity/bin/agy-doctor
```

**Upgrading from earlier port instructions?** Remove any wrapper prefix `allow` rules you added to `~/.kimi-code/config.toml`. Plugin updates preserve your configuration, so they do not remove these rules for you. Review complete Bash commands through Kimi's approval flow; see [Wrapper approvals](#wrapper-approvals).

**Coming from the Claude Code version?** Settings moved from the plugin-settings UI to a plain file, [`~/.kimi-code/antigravity.conf`](#configuration) (environment variables win over the file). The `agy-migrate` tool and `/antigravity:migrate` command were removed in the port — there is no Claude Code setup left to bring across.

**Platform support:** macOS, Linux, and **WSL** are the supported targets for headless delegation. **Native Windows (Git Bash/MSYS) is not recommended** — `agy -p` can hang with a 0-byte log when run without a real console (ConPTY); see [issue #6](https://github.com/yuting0624/antigravity-for-claude-code/issues/6) on the original repo. When GNU `timeout` or `gtimeout` is available, the wrapper bounds this with an outer timeout guard (returning TIMEOUT instead of hanging), and `doctor` distinguishes a hang from an auth failure — but for reliable headless use, run from **WSL/macOS/Linux**.

## ⚡ Quick start

```
/antigravity:setup                                    # health check (agy-doctor)
/antigravity:delegate --tier flash "Summarize this changelog in 3 bullets: ..."
```

Or just **ask for bulk work in plain language**. The agent instructions encourage proactive delegation through Kimi's `Agent` tool when a task exceeds the break-even, and the prompt nudge flags candidates. Kimi still chooses whether to delegate and verifies the result.

For a background analysis, run this in your shell from the repository you want analyzed, or ask Kimi to run it:

```bash
agy-job start --tier pro --digest --dir . "Map the APIv1 callers and summarize the migration work. Do not change files."
```

The command prints a job ID. Use it in the Kimi TUI:

```text
/antigravity:status
/antigravity:result <id>
/antigravity:cancel <id>
```

Write tasks also need an agy-side permission grant: a matching `permissions.allow` rule, or `--yolo` (which auto-approves all agy tools). Run writes on a dedicated branch and review the diff; see the guardrails below.

## 🧩 Slash commands

<img src="docs/image.png" alt="The /antigravity slash commands in a terminal session (screenshot from the Claude Code original; the menu works the same way in Kimi Code)" width="720">

*The plugin's commands show up natively in Kimi Code's `/` menu as `/antigravity:<name>`.*

| command | what it does |
|---|---|
| `/antigravity:setup` | health check — `agy` installed + authenticated, scripts ready |
| `/antigravity:delegate [--tier flash\|flash-lo\|pro] <task>` | delegate a subtask to agy under cost discipline, then verify |
| `/antigravity:review [--adversarial]` | independent cross-model review of the current diff; Kimi reconciles |
| `/antigravity:research <topic>` | Kimi-orchestrated deep research — agy does grounded web legwork, Kimi verifies citations across ≥2 sources |
| `/antigravity:media <file> [focus] [--convert]` | understand audio / video / images — agy transcribes + analyzes, returns a **timestamped digest**; full transcript goes to a file, not your context |
| `/antigravity:cloud-run-debug [--service <s>] [--region <r>] [--project <id>] [--since 1h] [--apply]` | diagnose a failing Cloud Run service — agy digests the error logs, Kimi infers the root cause + fix; read-only by default (`--apply` writes to a branch) |
| `/antigravity:status [id]` · `:result <id>` · `:cancel <id>` | manage background delegation jobs |

> Calculate the enclosing task budget with `agy-delegate --timeout 15m --print-budget` before launching. For long runs, explicitly background with that budget or use `agy-job`; foreground auto-backgrounding can impose a shorter cap. Short synchronous calls suit one-shot `kimi -p` work when the budget fits. Every launch reports an `AGY_RUN` diagnostic directory. After interruption, inspect the logs and verify existing edits before retrying. See [delegation lifecycle](docs/DELEGATION-LIFECYCLE.md).

<a id="configuration"></a>

## ⚙️ Configuration

Configuration lives in **`~/.kimi-code/antigravity.conf`**, loaded by `scripts/lib-config.sh`. Set `AGY_CONFIG` to use another file, or `KIMI_CODE_HOME` to change the default Kimi directory. Command-line options override defaults; nonempty environment values override the corresponding file settings. Every key is optional.

The file is **sourced as shell**, so keep it trusted and quote values containing spaces. For example:

```bash
AGY_DEFAULT_TIER=flash
AGY_TIMEOUT=5m
AGY_TIER_FLASH="Gemini 3.8 Flash (High)"
# AGY_USAGE_LOG="/absolute/path/to/agy-usage.log"
```

Use a model name from `agy models` when remapping tiers. `agy-doctor` also prints a sample configuration.

| key | default | what it controls |
|---|---|---|
| `AGY_DEFAULT_TIER` | `flash` | default delegation tier (`flash` / `flash-lo` / `pro`) |
| `AGY_TIMEOUT` | `5m` | default delegation timeout |
| `AGY_RUNS_DIR` | `~/.kimi-code/antigravity-runs` | persistent private run diagnostics (under `KIMI_CODE_HOME` when customized) |
| `AGY_DEFAULT_MODEL` | tier mapping | exact agy model name, overriding tiers |
| `AGY_TIER_FLASH` · `AGY_TIER_FLASH_LO` · `AGY_TIER_PRO` | Gemini tier models | per-tier model remaps (any name `agy models` lists) |
| `AGY_STRUCTURED_OUTPUT` | `on` | parse agy's `--output-format json` envelope (agy ≥ 1.1.8) |
| `AGY_DIGEST_WARN_CHARS` | `8000` (`0` = off) | warn when a "digest" comes back dump-sized |
| `AGY_DELEGATION_NUDGE` | `on` | the bulk-work prompt nudge hook |
| `AGY_USAGE_LOG` | unset | append every `AGY_USAGE` / `AGY_SIGNAL` line to this path |

### Wrapper approvals

Review the complete Bash command through Kimi's approval flow. The wrapper-only rule is a **prompt contract**, not shell confinement.
Removing `Write`/`Edit` does not prevent Bash from writing files or running other
commands. Avoid blanket prefix allow rules for the wrappers: Kimi documents
`allow` as immediate permission for a matching command, and a prefix match may
also cover chained shell commands (an inference from the matching rules, not a
verified shell-parser guarantee). See [Kimi's permission documentation](https://www.kimi.com/code/docs/en/kimi-code-cli/configuration/config-files#permission)
and [SECURITY.md](SECURITY.md). If you previously added the suggested wrapper
prefix allow rules, remove them; updating this plugin does not change your Kimi
configuration.

## 🔧 How it works

- **Routing policy via the system prompt.** [`SYSTEM.md`](SYSTEM.md) is wired into the manifest's `systemPromptPath`, so the cost-aware WHEN/HOW/VERIFY rules are present on every surface, every session — no hook injection needed (Kimi's `SessionStart` is observation-only and cannot inject context).
- **A nudge, not an auto-pilot.** The `UserPromptSubmit` hook (`hooks/nudge-delegation.sh`) appends a fixed-string plain-text note when your prompt *looks* like above-break-even bulk work. It never delegates by itself and never echoes your prompt back (no injection surface); the decision stays with Kimi. Toggle: `AGY_DELEGATION_NUDGE`.
- **A delegate subagent with a wrapper-only prompt contract.** `agents/antigravity-delegate.md` is dispatched through Kimi's `Agent` tool with `tools: Bash, Read, Glob`. Its instructions route file creation and bulky work through `agy-delegate` / `agy-job` to save Kimi tokens. Bash can still write files and execute arbitrary commands; omitting `Write`/`Edit` does not enforce this contract. See *Limitations*.
- **The digest contract.** `--digest` appends a digest-only output contract, and the wrapper warns when a reply comes back dump-sized (`AGY_DIGEST_WARN_CHARS`). Keeping raw output out of the conductor's context is the single biggest cost lever.
- **Verify discipline.** Kimi never trusts agy's self-reported pass — gates are re-run by the conductor in a clean state (agy has been observed patching its own environment to force a green check).

## 💸 Measuring the savings

Delegation doesn't save money by itself — these do (also in the skill):

1. **Delegate above the break-even** — bulk/parallel/repetitive work, not tiny tasks.
2. **Keep Kimi's context lean** — take a **digest**, not raw output; don't re-read what agy already handled. (Biggest lever — it collapses `cache_read`.)
3. **Batch** — one big delegation beats many round-trips.
4. **Review the diff, not the whole tree.**

The shipped `kimi_k3` deck uses these [official K3 API rates](https://platform.kimi.ai/), verified on **2026-09-23**:

| Token category | USD per 1M tokens | Weight relative to input |
|---|---:|---:|
| Input | $3.00 | 1× |
| Output | $15.00 | 5× |
| Cache creation (writes) | $3.00 | 1× |
| Cache reads (hits) | $0.30 | 0.1× |

With these defaults, `COST-WEIGHTED = input + 5 × output + cache_create + 0.1 × cache_read`. Estimated USD is `COST-WEIGHTED × 3 / 1,000,000`. Both calculations follow your configured rates; the historical Claude benchmark uses its original weights.

The accounting tools use [`prices.json`](prices.json):

- **`scripts/measure-session.py`** — conductor-side accounting for a Kimi session: reads `~/.kimi-code/session_index.jsonl` → the session's `agents/*/wire.jsonl` `usage.record` lines and prints turns, output, `cache_create`/`cache_read`, COST-WEIGHTED and est. USD on the `kimi_k3` deck. Both cost figures use the configured rates; COST-WEIGHTED normalizes them to input-token equivalents. With no argument it measures the most recent session for the current directory; `--include-subagents` folds in the delegate's turns.
- **`scripts/agy-cost-compare.sh`** — runs one task on agy and estimates prompt/reply tokens from character counts. It prices that same volume at Kimi K3 and Gemini rates (Flash by default, Pro with `--tier pro`); it does not measure end-to-end savings. Override with `KIMI_IN_PER_M` / `KIMI_OUT_PER_M` and `GEMINI_IN_PER_M` / `GEMINI_OUT_PER_M`.
- **`AGY_USAGE` / `AGY_USAGE_LOG`** — with structured output enabled and supported, the wrapper reports usage supplied by agy on stderr, including cache reads, model, tier, duration, and turns. Missing fields default to zero; plain-text fallbacks and some failed/partial runs provide no usage record. Set `AGY_USAGE_LOG` to retain records when trimming output. Price the Gemini side separately and account for missing records before claiming savings.

From your project directory, use the installed shim to measure the most recent Kimi session for that directory:

```bash
measure-session
measure-session --include-subagents
```

Pass a session ID, session directory, or `wire.jsonl` path to choose another session. The output identifies the price source; an unreadable or invalid deck uses a labeled K3 fallback. This measures Kimi usage only, so include the agy usage log when comparing the total cost of a hybrid run.

**Running a PoC in your org?** [`docs/POC-PLAYBOOK.md`](docs/POC-PLAYBOOK.md) is the step-by-step method — quality gate first, baseline, one lever at a time, break-even reporting, and org-level rollout (incl. Windows/WSL requirements).

## 🚧 Limitations

> **Something broken?** See **[docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)** — symptom-first fixes for PATH/install issues, Windows/WSL, writes that silently don't happen, and quota/auth/timeout codes.

- **The hard per-subagent gate does not exist on Kimi.** The Claude-era plugin restricted the delegate subagent's Bash to *only* the delegation wrappers via a per-agent `PreToolUse` hook. Kimi has no per-agent hooks (plugin hooks are global), so that enforcement point is gone. The wrapper-only rule is a prompt contract, and Bash remains capable of arbitrary commands and file writes. Review complete commands through Kimi's approval flow. Hard confinement requires a purpose-built restricted tool or an external execution boundary; this plugin provides neither — see [SECURITY.md](SECURITY.md).
- **Settings are a file, not a UI** (`~/.kimi-code/antigravity.conf`; environment wins). Plugin updates don't auto-apply: re-install + `/reload`.
- **Guardrails that are agy-side and unchanged:** always **verify** agy's output (re-run gates yourself in a clean state); `--yolo` auto-approves every tool call — a grant over your whole machine, not over `--dir`, and **`--sandbox` does not contain it** (measured on macOS with agy 1.1.19: a write outside `--dir` succeeded, `id` ran, `curl` returned 200); run write tasks on a dedicated branch and review the diff before merging.

<details>
<summary><b>🛠️ Direct script usage &amp; tiers</b></summary>

```bash
# one-shot delegation (plain text on stdout)
scripts/agy-delegate.sh --tier flash "Summarize this changelog in 3 bullets: ..."

# give Antigravity a workspace for multi-file agentic work
scripts/agy-delegate.sh --tier pro --dir ./src "List every TODO with file:line"

# bulk read -> digest-only reply (the biggest cost lever; wrapper warns on dump-sized replies)
scripts/agy-delegate.sh --digest --dir . "Map the auth flow end to end"

# write task: needs a grant — a permissions.allow write_file(<dir>) rule, or --yolo (run on a branch)
scripts/agy-delegate.sh --yolo --dir ./app "Implement X per SPEC.md"

# live web / Google search — and, since agy 1.1.28, any URL read — need --yolo (or a read_url(<target>) rule) headless
scripts/agy-delegate.sh --tier pro --yolo "Web-search <X>. Give URLs + dates."

# Vertex AI Search over internal data
scripts/agy-delegate.sh --tier pro --yolo "List Vertex AI Search engines (list_engines)."

# cross-model review / stdin / background job
scripts/agy-delegate.sh --tier pro "Review for bugs, be skeptical: <paste>"
cat big-prompt.txt | scripts/agy-delegate.sh -
ID=$(scripts/agy-job.sh start --tier pro --dir . "big task"); scripts/agy-job.sh result "$ID"
```

| tier | model | use for |
|------|-------|---------|
| `flash` (default) | Gemini 3.8 Flash (High) | most bulk work |
| `flash-lo` | Gemini 3.8 Flash (Low) | cheapest, trivial tasks |
| `pro` | Gemini 3.1 Pro (High) | harder reasoning / cross-checks |

**agy is multi-model.** Tiers default to Gemini, but you can use any model `agy models` lists
(Claude / GPT on plans that expose them): pass `--model "<exact name>"`, or set it persistently
in `antigravity.conf` — `AGY_DEFAULT_MODEL`, or per-tier `AGY_TIER_FLASH` / `AGY_TIER_FLASH_LO` /
`AGY_TIER_PRO`. Keep the executor a *different, cheaper* model than the Kimi conductor — that's
what gives both the cost saving and the cross-model verification.

> **The `flash` tiers moved to Gemini 3.8 Flash in 0.26.0** (3.7 in 0.24.0; 3.5 before that). 3.8, 3.7 and 3.6 carry *identical* list prices — $0.75 in / $3.75 out / $0.075 cached-in per 1M tokens — under promotional pricing that **ends 2026-12-31**, after which all three settle at $1.50 / $7.50 / $0.15 (3.5 is $1.50 / $9.00 / $0.15 throughout). Checked against two sources on 2026-09-03; [`prices.json`](prices.json) carries both sets. No quality claim is made here — the reason to move is currency at an unchanged list price, and the original repo retracted a model comparison before for being measured on a build where `--model` was ignored. An identical *per-token* price is not an identical *per-task* cost: thinking bills as output, nothing here has measured how much of it 3.8 does, so read the `AGY_USAGE` line. One quirk was measured while checking that release: under `--digest`, a prompt that gives agy nothing to inspect (a bare "reply OK" ping) makes 3.8 High run a *command* to find something to report — 6 of 7 runs, which headless without a grant is exit 15 (3.7 High 0 of 3, 3.8 Medium 1 of 6, 3.8 High without `--digest` 0 of 2). Given a real task — a file behind `--dir`, or code pasted into the prompt — 3.8 High answered 6 of 6. Give it a task, or drop `--digest` for a ping. **If your plan does not serve 3.8 yet** you find out immediately, not silently: `agy-doctor` warns that the tier model is absent from `agy models`, and a delegation exits **14** naming the fix. Remap with the `AGY_TIER_FLASH` / `AGY_TIER_FLASH_LO` config keys to anything `agy models` lists — `Gemini 3.7 Flash (High)` and `Gemini 3.6 Flash (High)` cost exactly the same. (agy 1.1.5 switched `agy models` to slugs like `gemini-3.8-flash-high`; both slugs and display names work with `--model`, and `doctor` matches either.)

</details>

<details>
<summary><b>🚧 Guardrails &amp; known limits (agy-side, carried over unchanged)</b></summary>

**Guardrails**

- Always **verify** agy's output (it can be wrong, and may even alter its environment to make a check pass — re-run gates yourself in a clean state).
- `--yolo` auto-approves every tool call — a grant over your whole machine, not over `--dir`.
  **`--sandbox` does not contain it.** Measured on macOS with agy 1.1.19: with `--yolo`, `--sandbox` changed nothing — a write to an absolute path OUTSIDE `--dir` succeeded (rc 0), `id` ran and returned a real uid, and `curl https://example.com` returned 200. agy's own help says "terminal restrictions"; whatever it restricts, it is not those, and not in this combination. Not tested on Linux. Use a throwaway checkout, or a
  `permissions.allow` rule instead of the flag.
- Write tasks: run on a dedicated branch/worktree, review the diff before merging.

**Compatibility notes (agy 1.0.x–1.2.x)**

- `-p`/`--print` **takes the prompt as its value** and must come last — the wrapper handles this.
- `--print` drops stdout on a non-TTY unless stdin is detached (handled via `< /dev/null`). **Structured output arrived in agy 1.1.8** (`--output-format json`): the wrapper now uses it internally on ≥1.1.8 to classify failures from the structured error and to report the executor's real token usage (incl. `cache_read`) as an `AGY_USAGE` line on stderr — stdout is unchanged. Since 0.28.0 that line also names the **model** that ran and the **tier** it was picked from (empty for an explicit `--model`), plus agy's own `duration_seconds` / `num_turns` (1.2.x; 0 on older agy), so a usage log prices itself per tier. Older agy falls back to plain text (toggle with `AGY_STRUCTURED_OUTPUT`). **If you're measuring, set `AGY_USAGE_LOG=/path`**: stderr is easily lost — `2>&1 | tail -N`, the natural way to keep Kimi's context lean, keeps the digest and drops the usage line.
- **Pipe hang and empty-output semantics moved upstream.** agy 1.1.24 fixed the cause of the issue-#37 hang (its MCP children kept the caller's pipes open); the wrapper keeps routing agy's output through files, which costs nothing and still covers older builds. Since agy 1.1.18 a dropped agent stream exits non-zero instead of rc 0 + empty, so the wrapper's exit `3` now means agy genuinely returned nothing (from agy's changelog; not reproduced here).
- **An expired `--print-timeout` is no longer a failure on agy's side (1.1.28).** agy returns the partial reply with rc 0 and one stderr line (`[agy] print timeout after 5s with turn in progress; returning partial output`, measured on 1.2.0) and reports no usage for the turn. The wrapper prints that partial reply and still exits `12`, so a truncated answer never passes as a finished one; `--continue` resumes the conversation.
- **The executor's trajectory is auditable.** Every agy run writes a step-by-step `transcript.jsonl`, and the `conversationId` in `AGY_USAGE` joins it to the cost 1:1. `agy-trace --audit <id>` (or `--audit --last`) shows step-type counts and every non-zero exit — a delegation can report SUCCESS while commands inside it failed. The command **strings** are recorded nowhere, so to attribute a filesystem change you must diff the tree.
- **Two write grants, and the narrow one is not `--yolo`.** Headless agy's
  no-permission behavior has shifted every few releases (describe-only pre-1.1.0 ·
  scratch-divert 1.1.0–1.1.2 · soft-deny 1.1.3+ · **hard error by 1.1.13** · soft again
  from **1.1.20**, measured on 1.1.25: rc 0, empty output, the `auto-denied` notice on
  stderr). An ungranted write always **leaves your workspace untouched**; what changed is
  how the run admits it — a stderr notice from 1.1.3, a failed run on 1.1.13–1.1.19, the
  notice again since 1.1.20
  ([#10](https://github.com/yuting0624/antigravity-for-claude-code/issues/10)). Two things
  grant it:

  - **`permissions.allow` in `~/.gemini/antigravity-cli/settings.json`** — a
    `write_file(<dir>)` entry allows writes **recursively beneath `<dir>`** and needs no
    flag. This is the narrower grant and usually the right one.
    **`<dir>` is a placeholder — substitute a real path.** Left as written it grants
    nothing on any agy version, and the write is denied with the rule sitting visibly
    in the file. A *different* mistake is the version-sensitive one: a `command(...)` rule
    that names no command (`command(time)`, a comment-only entry, `()`) matched **every**
    command before agy 1.1.11 and silently auto-approved anything the agent ran — broader
    than the `--yolo` it was chosen instead of. 1.1.11 makes that entry match nothing too.
    `agy-doctor` checks your entries and reports the consequence that actually applies.
  - **`--yolo`** — the wrapper's flag, sent to agy as `--dangerously-skip-permissions` (agy
    1.1.25 rejects a literal `--yolo`) — auto-approves **all** tools, not just
    writes. Needed when no rule covers the target, and for web search / URL reads (agy 1.1.28
    made fetching URLs ask first; the narrow rule is `read_url(<target>)`) / Vertex AI Search /
    terminal tools. Since agy 1.1.27 the wrapper names the refused tool from the envelope's
    `denied_actions` (measured on 1.2.0).

  Confirmed on **agy 1.1.9** by a controlled A/B ([#37](https://github.com/yuting0624/antigravity-for-claude-code/issues/37)):
  a covered target wrote with no flag; an uncovered one came back `PERMISSION_DENIED` with
  the rule as the only variable. agy's own denial text names the rule and offers `--yolo` as
  the alternative. Not verified on other versions, and a glob form (`write_file(/path/**)`)
  was reported *not* to match. Either way: run write tasks on a branch and verify with
  `git status`; the wrapper maps both denial shapes — the soft one (agy 1.1.3+, and again
  from 1.1.20; re-measured on 1.1.25) and 1.1.13's hard error — to exit `15`.
- **Native Windows (no ConPTY):** headless `agy -p` / `agy models` can hard-hang with a 0-byte log when stdio is redirected ([issue #6](https://github.com/yuting0624/antigravity-for-claude-code/issues/6)). The wrapper wraps agy in a wall-clock `timeout`/`gtimeout` guard so it returns a structured TIMEOUT (exit 12) instead of hanging; `doctor` reports the likely hang instead of a misleading "not authenticated". Without `timeout` on PATH there's no safety net — use **WSL/macOS/Linux** for headless delegation.
- **WSL:** running agy with `--add-dir` on a Windows mount (`/mnt/c/...`) is very slow — agy reads the workspace over a 9p bridge, so even trivial calls can take 20s+. Keep the repo on the WSL Linux filesystem (`~`). The wrapper and `doctor` warn about this.

</details>

<details>
<summary><b>📦 What's inside · local dev · tests</b></summary>

```
kimi.plugin.json    plugin manifest (name antigravity; systemPromptPath, hooks)
SYSTEM.md           the cost-aware routing policy, injected into the system prompt
skills/antigravity/SKILL.md   WHEN + HOW Kimi collaborates with agy
agents/             antigravity-delegate subagent (wrapper-only prompt contract)
commands/           slash commands (delegate, review, research, media, cloud-run-debug, setup, status, result, cancel)
hooks/              session-start.sh (agy health check + collision-safe bin/ links) · nudge-delegation.sh (bulk-work nudge)
bin/                PATH shims (bare names): agy-delegate · agy-job · agy-cost-compare · agy-doctor · cloud-debug · agy-trace · agy-media · measure-session
scripts/            agy-delegate · agy-job · agy-cost-compare · cloud-debug · agy-trace · agy-media · measure-session · doctor · lib-config
docs/               AB-RESULTS (measured A/B) · POC-PLAYBOOK · TROUBLESHOOTING · DEMO-KIT
prices.json         rate config — kimi_k3 orchestrator deck + Gemini (verify before quoting)
```

**Local development** (hack on the plugin):

```bash
git clone https://github.com/pmkay/antigravity-for-kimi-code ~/antigravity-for-kimi-code
# in the Kimi TUI:
/plugins install ~/antigravity-for-kimi-code
/reload
```

Remember the managed copy: the CLI runs `~/.kimi-code/plugins/managed/antigravity/`, so **re-install after every edit** (and `/reload`, or start a new session).

**Tests** (Bash + Python 3; stubs agy, no network or API credentials required):

```bash
bash tests/run-tests.sh
```

The suite covers startup collisions, K3 cache-write pricing and fallback rates, and version agreement across the manifest, skill, and newest changelog entry. CI also runs ShellCheck and the suite on Linux and macOS Bash 3.2; the PR-base changelog-placement check is intentionally skipped when no PR base is available.

</details>

---

## 🗳️ The same two models, arranged differently

This plugin is one shape of a frontier conductor and Gemini working together: **conductor and executor** — judgement on one side, throughput on the other, one workflow. It is also the shape for people who live in a terminal.

[**gemini-studio-mcp**](https://github.com/yuting0624/gemini-studio-mcp) is the same thesis on the other surface: **Claude Desktop**, for the colleagues who will never open one. An MCP server rather than a CLI delegation, and the verb flips from *execute* to *ingest* — Gemini reads the recording, the PDF corpus, the internal search index, and only the digest reaches the conductor. The split is not cosmetic: you can hand a developer a `--tier` flag and an `AGENTS.md`, but a business user drags a PDF into a chat window, so the routing that is explicit here is automatic there, and the cost discipline that is a documented practice here is a number printed on every response there. They also fail differently — delegated *writing* can silently not happen and has to be checked against the filesystem; delegated *reading* can quietly summarise away the one paragraph that mattered and has to be checked against citations. Same author as the original plugin.

[**quorum-review**](https://github.com/yuting0624/quorum-review) is the third shape: the two as **peers**. Both read the same pull request independently, neither sees the other's output, and where they agree independently *that is the result* — only the disagreements are worth a second opinion. Both run on **one** Google Cloud credential, so no vendor API keys live in the repository. Same author as the original plugin.

**This repo also uses quorum-review.** The workflow reviews eligible pull requests and supports on-demand reviews; fork heads are refused before checkout or authentication. Keeping the habit of not quoting numbers we haven't measured, here is what that has actually been worth (measured on the original repo):

- On a fixture holding three known bugs it found **two, with no false positives**, and reached the correct root cause on one that the single-model review took two rounds to get right.
- Reviewing the original repo's own CI, both of its models **independently** caught a fork-guard hole in the review workflow itself — one that would have put an outside contributor's code on the runner next to live credentials.
- It has also produced a confident **false positive that both models agreed on** — the code disproving it lived outside the checkout either model could read.

That last one is the useful lesson, and it cuts against the obvious pitch: two independent scans insure you against *one model's* blind spot. They do not insure you against a gap in what you handed **both** of them.

---

## 🤝 Contributing

Early-stage and MIT — issues, PRs, and ⭐ all welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) and the [`good first issue`](https://github.com/pmkay/antigravity-for-kimi-code/issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22) list.

**Automated review:** PRs get [quorum-review](https://github.com/yuting0624/quorum-review) in CI on top of the usual tests/shellcheck — see the section above. **From a fork:** the workflow refuses fork heads before any credential is minted, so automated review does not run — a maintainer reviews by hand. Fork code never reaches the credentialed quorum-review job; ordinary test CI runs separately.

---

## ⚠️ Disclaimer

Community project. **Not affiliated with, endorsed by, or supported by Google, Anthropic, or Moonshot AI.** "Antigravity", "Gemini", "Kimi", and "Claude" are trademarks of their respective owners. This plugin orchestrates the third-party `agy` CLI; you are responsible for your own API/cloud costs, credentials, and data-sharing choices. MIT licensed — see [LICENSE](LICENSE).
