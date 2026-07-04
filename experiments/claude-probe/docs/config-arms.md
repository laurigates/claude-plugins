# Config-isolation arms

An extra axis on top of the system-prompt A/B: hold model, effort, and
system-prompt fixed and vary **only which global config surface Claude Code
loads**. Answers "what does the workstation setup actually buy, and what does
it cost?"

## The three arms

| Arm | Loads | Realises |
|---|---|---|
| `clean` | system prompt + core tools | Claude before any user config |
| `plugins-only` | + marketplace skills, **no** global memory | a cloud / CI session |
| `full` | + 75k-ish rules + `CLAUDE.md` + hooks | the local workstation |

## What actually isolates the arms (measured this session, v2.1.201)

Three plausible mechanisms were tested with trivial probes; only one works, and
it has a caveat:

- **`--bare`** — refuses the subscription token (`Not logged in`). Unusable for
  isolated arms authenticated by `CLAUDE_CODE_OAUTH_TOKEN`.
- **`CLAUDE_CONFIG_DIR`** — relocates session/auth storage but **not** memory
  discovery: `~/.claude/CLAUDE.md` + `rules/` still load. Does not strip memory.
- **`HOME` override** — Claude discovers `~/.claude` from `$HOME`, so a per-arm
  `$HOME` **does** strip memory. This is the mechanism `run-one.sh` uses.
  Caveat below.

MCP servers are discovered from the **cwd** (`.mcp.json`), not `$HOME`, and load
~90k of tool schemas that swamp the arms — so every run passes
`--strict-mcp-config`, and the sweep runs from a neutral fixture repo
(`make-fixture.sh`) with no `.mcp.json` / project `.claude` in its ancestry.

### Measured per-layer eager cost (headless, neutral cwd, `ctx = cache_creation + cache_read`)

| Arm | ctx tokens | Δ = layer cost |
|---|---|---|
| `clean` | 21,019 | base (system prompt + core tools) |
| `plugins-only` | 26,205 | **+5,186** — 30 marketplace plugins' skill descriptions |
| `full` | 92,725 | **+66,520** — global memory + hooks |

Note this corrects the interactive `/context` figures: eager **skills cost ~5k,
not ~22k**, and **global memory is the ~67k lever**. Memory is where the
slimmer/fatter question lives; skills are nearly free eagerly.

### Known caveat: HOME override re-triggers tool init (outcome sweep is WIP)

For *context measurement* (trivial prompts) HOME override is clean. For real
*task* runs it is fragile: pointing `$HOME` at an empty dir makes mise/go and
other `$HOME`-rooted tooling re-initialise and download into the fake HOME (a
Go toolchain landed in `fh-clean/go`, whose read-only module cache then broke
`arm-prep`'s cleanup). Hardening options (not yet chosen): symlink the
tool-cache dirs (`go`, `.cache`, `.config`, `.local`) from the real HOME into
each fake HOME so only `~/.claude` differs; pin `GOTOOLCHAIN=local` and cache
env vars; or run each arm in a container. Until then the **outcome sweep**
(`run-config.sh`) should be treated as WIP; the **cost decomposition** above is
solid.

## Auth (one-time)

Both isolated arms lose the interactive OAuth login, so they authenticate from a
token. Mint a subscription-billed one and add it to `~/.api_tokens`:

```
claude setup-token
echo 'export CLAUDE_CODE_OAUTH_TOKEN="sk-ant-oat01-..."' >> ~/.api_tokens
```

`run-config.sh` sources it automatically. `ANTHROPIC_API_KEY` also works (bills
the API account instead of the subscription).

## Run

```
just run-config '0[1246]-*' 3   # read-only probes, clean/plugins-only/full, 3 runs
just compare-fast latest        # deterministic scores only (no LLM judge)
```

## Files

- `conditions.yaml` — `cfg-clean` / `cfg-plugins` / `cfg-full` (new `config` field)
- `scripts/run-one.sh` — maps `config` → `$HOME` + `--strict-mcp-config`
- `scripts/arm-prep.sh` — builds the per-arm fake HOMEs
- `scripts/make-fixture.sh` — neutral sample repo for the sweep cwd
- `scripts/run-config.sh` — sources token, preps, sweeps the 3 arms
- `scripts/score-run.py` — now surfaces `ctx=` (context size) per run
