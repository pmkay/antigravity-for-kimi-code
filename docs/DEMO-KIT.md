# Demo kit — Experiment B (scaled build): "Image #2" SDLC multi-agent on ADK

Goal: BUILD the Image-#2 architecture (an SDLC Expert Agent that turns a feature brief
into 要件定義 → 基本設計 → 詳細設計, each web-grounded), **deploy to Agent Engine**, and
measure 3 arms to test whether the hybrid wins on cost **at this larger scale** (it lost
on the small weather app — see `AB-RESULTS.md`).

> Ported to Kimi Code: the original kit drove `claude` with pinned session ids; the arms
> below drive `kimi` in per-arm directories and measure with `scripts/measure-session.py`
> (no argument = newest session for the current directory). The numbers this kit
> originally produced are Claude-era — see `AB-RESULTS.md`'s provenance note.

Commands verified against **google-adk 2.2.0** (run on a Vertex-enabled GCP project with
ADC + a service account holding `roles/aiplatform.user`). Adversarially reviewed; the
host-specific traps below are real.

---

## 0. One-time setup (do before any arm)

**Install ADK (host pip/uv point at a corp registry that 403s — bypass to PyPI, use 3.12):**
```bash
mkdir -p ~/expB
uv venv ~/expB/.venv312 --python 3.12
uv pip install --python ~/expB/.venv312/bin/python --default-index https://pypi.org/simple \
  google-adk 'google-cloud-aiplatform[agent_engines,adk]>=1.112'
~/expB/.venv312/bin/adk --version    # expect 2.2.0
# activate per shell:  source ~/expB/.venv312/bin/activate
```

**Verify deploy prereqs (don't discover these mid-demo):**
```bash
gcloud services enable aiplatform.googleapis.com --project YOUR_PROJECT
gcloud storage buckets create gs://YOUR_PROJECT-adk-staging --location=us-central1 || true  # optional; CLI deploy doesn't need a flag
# SA needs Vertex AI permissions — confirm your service account has roles/aiplatform.user (+ storage.objectAdmin on the bucket)
```

> Traps (verified): Python must be **3.9–3.12** (3.14 unsupported). `adk deploy agent_engine`
> **has no `--staging_bucket`** (deprecated/ignored). Region **us-central1** (managed
> sessions are region-limited). cloudpickle deploy is fragile — list deps in `requirements`.

---

## 1. The SHARED build spec (identical text in all 3 arms — fairness)

> Paste this SAME spec in every arm. Arms differ ONLY in launch flags (plugin/effort)
> and, for the hybrid arm, the prepended delegation instruction in §2.

```
TASK: Build a production ADK multi-agent system and deploy it to Vertex AI Agent Engine
(Gemini Enterprise Agent Platform), in the current directory.

GCP: project=YOUR_PROJECT, region=us-central1, ADC present, staging bucket
gs://YOUR_PROJECT-adk-staging. Use the venv at ~/expB/.venv312 (adk 2.2.0). Do NOT use
Python 3.14.

ARCHITECTURE (the "Agent グラウンドデザイン"):
- Root "Expert Agent" (LlmAgent) = single entry point; validates a feature brief, runs the
  dispatch harness, assembles + returns the final package.
- Task-dispatch harness = a SequentialAgent running 3 specialists IN ORDER, passing state
  via output_key:
  1. 要件定義 (requirements) LlmAgent  -> output_key='requirements'
  2. 基本設計 (basic_design) LlmAgent  -> reads {requirements}, output_key='basic_design'
  3. 詳細設計 (detailed_design) LlmAgent -> reads {requirements}+{basic_design}, output_key='detailed_design'
- GROUNDING: each specialist uses the built-in google_search tool as its SOLE tool (mixing
  google_search with custom function tools errors; if a specialist needs both, wrap the
  search in a sub-agent via AgentTool). No Vertex AI Search this round.
- Model: gemini-2.5-flash for the specialists.

EVAL CONTRACT (you own it; gate = `adk eval` green before deploy):
- CASE1 happy path: brief "Add SSO login (SAML + OIDC) to our web app." -> requirements,
  basic_design, detailed_design all present and non-empty.
- CASE2 freshness: brief "Integrate payments via Stripe." -> detailed_design cites
  version-correct Stripe API details (grounded, not guessed).
- CASE3 cross-stage consistency: every requirement is addressed by a basic_design
  component; every component has detailed_design detail.
- CASE4 underspecified: brief "make it better" -> requirements agent asks a clarifying
  question / states explicit assumptions (no hallucinated scope).
- TRAJECTORY: invocation order is exactly requirements -> basic_design -> detailed_design;
  each specialist calls google_search at least once; state handoff verified.
Create the evalset, configure LLM-as-judge, and run `adk eval` until green.

DELIVER: build it, pass `adk eval`, deploy to Agent Engine, capture the reasoningEngines
resource name, then query the deployed agent with a real brief and confirm it returns the
three ordered artifacts.

DEPLOY — use the SDK path, NOT `adk deploy` (VERIFIED 2026-06-18):
`adk deploy agent_engine` auto-generates requirements from import-detection and DROPS the
runtime `a2a` module → the container fails to start ("No module named 'a2a'"). The
working path is the SDK with EXPLICIT requirements:
```python
import vertexai
from vertexai.preview.reasoning_engines import AdkApp
from vertexai import agent_engines
from sdlc_agent.agent import root_agent
vertexai.init(project="YOUR_PROJECT", location="us-central1",
              staging_bucket="gs://YOUR_PROJECT-adk-staging")
app = AdkApp(agent=root_agent, enable_tracing=True)
remote = agent_engines.create(
    agent_engine=app, display_name="SDLC Expert Agent",
    requirements=["google-adk[a2a]", "a2a-sdk",
                  "google-cloud-aiplatform[agent_engines,adk]>=1.112"],
    extra_packages=["sdlc_agent"], env_vars={"GOOGLE_GENAI_USE_VERTEXAI": "TRUE"})
print(remote.resource_name)
```
Query the deployed agent: `agent_engines.get(<resource>).stream_query(user_id="u", message="<brief>")`.
DELETE when done (billable): `agent_engines.get(<resource>).delete(force=True)`.
```

---

## 2. The three arms

Pin the SAME model everywhere (`kimi -m <alias>` or the configured default); vary only
what each arm is meant to vary. Kimi Code has no `--session-id` to pin: each arm runs in
its OWN directory, and `measure-session.py` with no argument measures the newest session
for the current directory. Keep the plugin **disabled** for the solo arms (`/plugins`)
and **enabled** for the hybrid arm — plugins are per-user, across all projects.

**Arm 1 — SOLO @ high** (plugin OFF):
```bash
mkdir -p ~/expB/solo-high && git -C ~/expB/solo-high init -q && cd ~/expB/solo-high
kimi
```
Paste: `[§1 spec]` prepended with: `Build everything YOURSELF. Do NOT delegate to any other agent/tool.`

**Arm 2 — SOLO @ max** (plugin OFF, identical prompt, only reasoning effort differs —
use the deepest thinking mode your Kimi Code build exposes, e.g. a thinking model alias
via `/model`):
```bash
mkdir -p ~/expB/solo-max && git -C ~/expB/solo-max init -q && cd ~/expB/solo-max
kimi
```
Paste: the EXACT SAME prompt as Arm 1, verbatim.

**Arm 3 — HYBRID** (plugin ON; same model + effort as Arm 1):
```bash
mkdir -p ~/expB/hybrid && git -C ~/expB/hybrid init -q && cd ~/expB/hybrid
kimi        # antigravity plugin installed, then /reload (or a fresh session)
```
Paste: `[§1 spec]` prepended with:
```
Use the 'antigravity' plugin. YOU conduct (architecture, AGENTS.md/SPEC contract, the eval
contract, verification + adk eval + deploy). DELEGATE to agy: the ADK API web-research and
the bulk implementation + boilerplate evalset. Follow Cost discipline: do NOT Read files
agy wrote into --dir; have agy return a ===DIGEST=== only; prefer ONE big batched
delegation (single long wait, no keep-warm busy turns); review git diff only.
```

---

## 3. Measure (after all three finish)

Run inside each arm's directory — with no argument the script measures the newest
session for the current directory:

```bash
cd ~/expB/solo-high && python3 ~/antigravity-for-kimi-code/scripts/measure-session.py
cd ~/expB/solo-max  && python3 ~/antigravity-for-kimi-code/scripts/measure-session.py
cd ~/expB/hybrid    && python3 ~/antigravity-for-kimi-code/scripts/measure-session.py
```

Keep all three main-agent-only (the default) for comparability; `--include-subagents`
folds in the delegate subagent's turns if you want them counted. Conductor-side USD
prices on the `kimi_k3` deck in `prices.json` — quota-based subscriptions pay no
per-token rate, so treat that figure as a $-proxy unless you run on the paid platform
API. Also for the hybrid arm, price the **Gemini side** (not in measure-session.py):
`scripts/agy-cost-compare.sh` gives the per-token gap (chars/4 estimate; set real Vertex
rates first). Report a both-decks note.

**Record per arm:** COST-WEIGHTED (primary), output / cache_create / cache_read / total,
turns, wall-clock, and QUALITY (adk eval pass rate, deploy success + resource name,
deployed-agent returns 3 ordered artifacts).

**Success (hybrid wins at scale, flipping the small-task result) IFF BOTH:**
1. COST: hybrid COST-WEIGHTED < solo@high COST-WEIGHTED, **and**
2. QUALITY: hybrid ≥ solo (passes every eval case + trajectory + deploys + answers).

Watch `cache_create` (the v2/v3 trap): one batched delegation = one long wait = one
re-cache event, not many. Report both the raw number and a warm-cache counterfactual
(price cache_create at cache_read 0.1× — see AB-RESULTS Test 1c).

Fill the Test 2 table in `AB-RESULTS.md` with the three rows.

---

## Honest framing for the result
- If hybrid COST-WEIGHTED < solo@high here, that is the **defensible** sales claim:
  "above this task size, the hybrid cuts frontier spend by N% at equal quality — here's
  the data and the break-even." Not the slide's flat 8×/46%.
- If hybrid still loses, the break-even is even higher than this build — also a clear,
  honest finding. Either way the value beyond cost (Google-native ADK build, web-grounded
  multi-agent, verification gate, deploy) stands on its own for the CE/exec story.
