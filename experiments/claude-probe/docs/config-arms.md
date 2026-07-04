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

### HOME override and the tool sandbox

Pointing `$HOME` at a fake dir strips `~/.claude` memory but also unroots
`$HOME`-defaulting tools. The split is XDG-compliance:

- **XDG-compliant tools (mise, ruff, …) are fine** — mise resolves its dirs by
  precedence `MISE_*_DIR` > `XDG_*_HOME` > `$HOME` default, and the `XDG_*` vars
  here are absolute, so mise finds the real installed tools under any `$HOME`.
  The isolated arms just need to inherit `XDG_*` (they do).
- **HOME-defaulters break** — Go's `GOPATH` defaults to `$HOME/go` and
  `GOTOOLCHAIN=auto` auto-downloads a toolchain into the fake HOME. `run-one.sh`
  pins `GOTOOLCHAIN=local` + `GOPATH`/`GOMODCACHE` at the real HOME for the
  isolated arms. Other HOME-rooted config (`~/.gitconfig`, `~/.npmrc`, `~/.ssh`)
  would need the same treatment if a probe depends on it; the fixture sets its
  own local git config so the read-only probes don't.

Verified: a clean-arm task run lists the fixture files correctly with zero
toolchain download.

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
