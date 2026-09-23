#!/usr/bin/env python3
"""measure-session.py — token + tool accounting for one Kimi Code session.

Usage:
    python3 measure-session.py [session-id | session-dir | wire.jsonl] [--include-subagents] [label]

With no argument, measures the most recent session for the CURRENT working
directory per ${KIMI_CODE_HOME:-~/.kimi-code}/session_index.jsonl — one JSON
per line with sessionId / sessionDir / workDir; the index is append-ordered,
so the LAST match for a workDir is the most recent. A bare session id is
resolved through the same index (exact, then unambiguous prefix), falling back
to a session-dir glob for sessions the index never recorded.

A session holds one wire.jsonl per agent:
    <sessionDir>/agents/main/wire.jsonl       the main agent (the default)
    <sessionDir>/agents/agent-*/wire.jsonl    subagents (opt in with the flag)

Token records are lines with "type":"usage.record" carrying
    usage: {"inputOther":N, "output":N, "inputCacheRead":N, "inputCacheCreation":N}
plus agentId / model / usageScope ("turn" — one record per turn, so summing is
safe) / time. Tool calls are "context.append_loop_event" lines whose nested
event has type "tool.call".

NOTE: this measures the KIMI (orchestrator) side only — agy/Gemini tokens are
reported separately, in agy-delegate's AGY_USAGE lines on stderr / AGY_USAGE_LOG.
"""
import json, os, sys, glob, math

# Hardcoded last resort when prices.json is unreadable. Keep in sync with the
# "kimi_k3" deck and the cache multipliers in prices.json — a test checks drift,
# and a stale hardcoded rate quotes a wrong number exactly where nobody can see
# where it came from.
FALLBACK_DECK = {"in": 3.0, "out": 15.0}
FALLBACK_CACHE_WRITE_MULT = 1.0
FALLBACK_CACHE_READ_MULT = 0.10

def kimi_home():
    return os.path.expanduser(os.environ.get("KIMI_CODE_HOME") or "~/.kimi-code")

def load_prices():
    here = os.path.dirname(os.path.abspath(__file__))
    for p in (os.path.join(here, "..", "prices.json"),
              os.path.join(here, "prices.json"), "prices.json"):
        try:
            with open(p) as f:
                return json.load(f)
        except Exception:
            continue
    return None

def price_deck(pr):
    """Use one validated set of rates for both USD and input-equivalent totals."""
    if isinstance(pr, dict):
        name = pr.get("orchestrator", "kimi_k3")
        deck = pr.get(name) if isinstance(name, str) else None
        if isinstance(deck, dict):
            rates = (deck.get("in"), deck.get("out"),
                     pr.get("cache_write_mult", FALLBACK_CACHE_WRITE_MULT),
                     pr.get("cache_read_mult", FALLBACK_CACHE_READ_MULT))
            if all(isinstance(v, (int, float)) and not isinstance(v, bool)
                   and math.isfinite(v) and v >= 0 for v in rates) and rates[0] > 0:
                return (name, *rates, "prices.json")
    return ("kimi_k3", FALLBACK_DECK["in"], FALLBACK_DECK["out"],
            FALLBACK_CACHE_WRITE_MULT, FALLBACK_CACHE_READ_MULT,
            "hardcoded fallback — prices.json unreadable or invalid")

def load_index():
    try:
        rows = []
        with open(os.path.join(kimi_home(), "session_index.jsonl")) as f:
            for line in f:
                try:
                    rows.append(json.loads(line))
                except Exception:
                    continue
        return [r for r in rows if isinstance(r, dict)]
    except OSError:
        return []

def resolve(arg):
    """Return (session_dir, session_id). arg=None: newest session for the cwd."""
    rows = load_index()
    if arg is None:
        cwd = os.getcwd()
        match = None
        for r in rows:
            if r.get("workDir") == cwd:
                match = r            # last match wins: the index is append-ordered
        if match:
            return match.get("sessionDir"), match.get("sessionId")
        return None, None
    hits = [r for r in rows if r.get("sessionId") == arg]
    if not hits:
        hits = [r for r in rows if str(r.get("sessionId") or "").startswith(arg)]
        if len(hits) > 1:
            sys.stderr.write("warning: %d sessions match '%s'; using %s\n"
                             % (len(hits), arg, hits[-1].get("sessionId")))
    if hits:
        return hits[-1].get("sessionDir"), hits[-1].get("sessionId")
    dirs = [d for d in sorted(glob.glob(os.path.join(kimi_home(), "sessions", "*", arg + "*")))
            if os.path.isdir(d)]
    if len(dirs) > 1:
        sys.stderr.write("warning: %d session dirs match '%s'; using %s\n" % (len(dirs), arg, dirs[0]))
    if dirs:
        return dirs[0], os.path.basename(dirs[0])
    return None, None

def measure(paths):
    ti = to = tcc = tcr = turns = 0
    tools = {}
    agents = {}
    models = {}
    for path in paths:
        try:
            f = open(path, encoding="utf-8", errors="replace")
        except OSError:
            continue
        with f:
            for line in f:
                try:
                    o = json.loads(line)
                except Exception:
                    continue
                if not isinstance(o, dict):
                    continue
                t = o.get("type")
                if t == "usage.record":
                    u = o.get("usage")
                    if not isinstance(u, dict):
                        continue
                    turns += 1
                    ti += u.get("inputOther", 0) or 0
                    to += u.get("output", 0) or 0
                    tcc += u.get("inputCacheCreation", 0) or 0
                    tcr += u.get("inputCacheRead", 0) or 0
                    aid = str(o.get("agentId") or "?")
                    agents[aid] = agents.get(aid, 0) + 1
                    m = str(o.get("model") or "?")
                    models[m] = models.get(m, 0) + 1
                elif t == "context.append_loop_event":
                    ev = o.get("event")
                    if isinstance(ev, dict) and ev.get("type") == "tool.call":
                        n = str(ev.get("name") or "?")
                        tools[n] = tools.get(n, 0) + 1
    return dict(turns=turns, input=ti, output=to, cache_create=tcc, cache_read=tcr,
                total=ti + to + tcc + tcr, tools=tools, agents=agents, models=models)

if __name__ == "__main__":
    include_sub = False
    pos = []
    for a in sys.argv[1:]:
        if a == "--include-subagents":
            include_sub = True
        elif a in ("-h", "--help"):
            print(__doc__); sys.exit(0)
        else:
            pos.append(a)
    target = pos[0] if pos else None

    if target and os.path.isfile(target):
        # single wire.jsonl (or any JSONL in the same record shapes), old-style
        files = [target]
        label = pos[1] if len(pos) > 1 else os.path.basename(target)
        scope = "single file only — sibling agents NOT counted"
    else:
        if target and os.path.isdir(target):
            session_dir, session_id = target, os.path.basename(target.rstrip("/"))
        else:
            session_dir, session_id = resolve(target)
        if not session_dir or not os.path.isdir(session_dir or ""):
            print("session not found: %s" % (target or "no session for cwd %s" % os.getcwd()))
            sys.exit(1)
        files = [os.path.join(session_dir, "agents", "main", "wire.jsonl")]
        if include_sub:
            files += sorted(glob.glob(os.path.join(session_dir, "agents", "agent-*", "wire.jsonl")))
        files = [f for f in files if os.path.isfile(f)]
        if not files:
            print("no wire.jsonl under %s/agents" % session_dir); sys.exit(1)
        label = pos[1] if len(pos) > 1 else session_id
        if include_sub:
            scope = "main agent + subagents (agents/agent-*)"
        else:
            scope = "main agent only — subagent wire.jsonl files NOT counted (pass --include-subagents)"

    r = measure(files)
    deck_name, IN, OUT, cw, crd, source = price_deck(load_prices())
    # Normalize the configured prices to input=1, including user overrides.
    # The shipped K3 ratios are output 5x, cache writes 1x, cache reads 0.1x.
    output_mult = OUT / IN
    weighted = (r['output'] * output_mult + r['input'] +
                r['cache_create'] * cw + r['cache_read'] * crd)
    usd = weighted * IN / 1e6
    print(f"=== {label} ===")
    print(f"  turns          {r['turns']}")
    print(f"  output         {r['output']:,}   <- {output_mult:g}x input")
    print(f"  input          {r['input']:,}")
    print(f"  cache_create   {r['cache_create']:,}   <- {cw:g}x input (cache writes)")
    print(f"  cache_read     {r['cache_read']:,}   <- {crd:g}x input (cache reads)")
    print(f"  TOTAL tokens   {r['total']:,}")
    print(f"  COST-WEIGHTED  {weighted:,.0f}   <- input-equivalent units ({deck_name} deck)")
    print(f"  est. USD       ${usd:,.4f}   ({deck_name} deck, {source} — VERIFY)")
    print(f"  models         {r['models']}")
    if include_sub:
        print(f"  agents         {r['agents']}")
    print(f"  tool calls     {sum(r['tools'].values())}  {r['tools']}")
    print(f"  scope          {scope}")
