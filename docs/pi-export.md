# pi (pi.dev) skill discovery & local-model orchestration

Run this marketplace's skills inside **pi** ([pi.dev](https://pi.dev),
`@earendil-works/pi-coding-agent`) against a **local model** (mlx_lm.server /
ollama). The sibling of [`opencode-export.md`](opencode-export.md) — same goal
(local-model testing of our skills), a much thinner pipeline.

> **Why the `-export.md` suffix, when pi exports nothing here?** The name mirrors
> the OpenCode sibling so the pair stays findable together — but for **skills**
> pi has no static export step at all. It reads `SKILL.md` in place through the
> runtime adapter ([`../adapters/pi/`](../adapters/pi/), ADR-0022), and nothing
> is copied into `~/.pi/agent/skills/`. So this file is the pi **adapter** doc
> that happens to carry the sibling's name. (OpenCode's export is real: it
> projects **subagents and hooks**, because OpenCode reads neither
> `.claude/agents/` nor `hooks.json` — skills reach it through the same adapter.)

> **The tier installer is gone (#2093).** Skill discovery is now the
> **ADR-0022 adapter**'s job: `pi/tiers.yaml`, `scripts/install-pi.sh`,
> `scripts/check-pi-tiers.sh` and the `install-pi` / `install-pi-domain` /
> `pi-tiers` / `check-pi-tiers` recipes were removed after the adapter's
> retrieval eval gate was measured and frozen on 2026-07-22
> ([`../adapters/CUTOVER.md`](../adapters/CUTOVER.md)). Nothing needs to be
> copied into `~/.pi/agent/skills/` any more.

## Why pi needs almost no pipeline

pi loads Claude Code `SKILL.md` files **unmodified**. Validated on pi 0.80.6:
pi is *strictly more lenient* than the retired rulesync converter was — it
accepts display-name `name:` values (`UnoCSS`), unprefixed names
(`ground-response`), comma-string `allowed-tools`, and extra frontmatter, all of
which that converter's normalization layer had to rewrite. **None of it was ever
needed for pi**, and since #2094 none of it runs for OpenCode either — both
harnesses now read `SKILL.md` in place through the adapter. pi also reads
`CLAUDE.md` natively and does the same progressive disclosure as Claude Code
(only `name`+`description` surfaced up front; the body loads on demand via
`read` / `/skill:name`).

So the only thing worth building was a way to keep the *listing* affordable.

## The one real gap: pi doesn't budget the skill listing

Claude Code caps the up-front skill-description listing at
`skillListingBudgetFraction × context`. **pi has no such budget** — every
skill it discovers costs ~111 tokens of standing per-turn context (measured, pi
0.80.6), dead linear and uncapped:

| Skills in the listing | Standing cost/turn | On a 128K local context |
|------------------|--------------------|-------------------------|
| ~20 | ~2.2K | negligible |
| 94 | ~10.4K | ~8% — fine |
| ~200 | ~22K | tight |
| all ~400 | ~45K | fatal (401 skills hangs the turn >2min; ≤200 fine) |

On a 1M-context Claude at `skillListingBudgetFraction 0.1` this is invisible; on
a small local quant it wedges the agent.

Two answers were built for this. The **tier installer** (retired) curated a
~95-skill subset into pi's native scopes and paid ~9,900 standing tokens for it,
at the cost of a hand-maintained manifest that restated facts already in the
marketplace. The **adapter** (current) replaces the native listing outright.

## The adapter (ADR-0022)

`adapters/pi/` is a pi extension that strips the native `<available_skills>`
block and injects, in its place, a small set of pins plus a per-turn **ranked
top-k** slice — while exposing a `search_skills` **pull tool** for everything
else. All ~400 skills stay reachable at **~600 standing tokens/turn** instead of
the tier's ~9,900, and there is no curation manifest to drift.

Full documentation — configuration keys, the Trust caveat, the ranker, and the
eval harness — is [`../adapters/README.md`](../adapters/README.md) § pi. Read it
there rather than restating it here.

```
just pi-adapter-check        # prereqs: pi, bun deps, ollama embed model, the two packages in § Extension triad
just pi-adapter              # trial it, ZERO config changes (pi -e <path>)
just pi-adapter-register     # persist into ~/.pi/agent/settings.json extensions[]
just pi-adapter-unregister   # reverse the above
```

`just pi-adapter-register` is idempotent and non-clobbering. Note pi loads local
extensions from `extensions`, **not** the `packages` array `pi install` / `pi
list` manage — so `pi list` will not show it; that is expected, not a failure.

## Claude Code variables in pi

Claude Code substitutes `${CLAUDE_SKILL_DIR}` and `${CLAUDE_SESSION_ID}` into a
skill's text before the model sees it. pi does neither: it performs no variable
substitution, and its `bash` tool exports no such variables. Without the adapter,
a command such as `task-add`'s `bash "${CLAUDE_SKILL_DIR}/../../scripts/ensure-udas.sh" --check`
runs as `bash "/../../scripts/ensure-udas.sh" --check`. Around 50 skills that pi
loads are affected.

The adapter's `tool_call` handler rewrites the `bash` input before it runs.
Skill text is untouched, so Claude Code's behaviour does not change.

| Step | Behaviour |
|---|---|
| Record | A `read` of a `*/SKILL.md` records that directory; a `/skill:` expansion (`<skill … location="…">` in the prompt) records its directory too |
| Resolve | Every `${CLAUDE_SKILL_DIR}/<rel>` (or `$CLAUDE_SKILL_DIR/<rel>`) in the command must exist under the chosen directory. Read history is tried first (most recent first), then `/skill:` expansions, then every indexed skill |
| Rewrite | One line, `export CLAUDE_SKILL_DIR='…' CLAUDE_SESSION_ID='…' PI_SESSION_FILE='…'`, is prepended, single-quote-escaped. Heredocs, `set -e`, and a leading `cd` behave as before. Commands that reference neither variable pass through unchanged |
| Block | No candidate matches, or several indexed skills match different real files (two skills each shipping `scripts/run.sh`): the call is blocked and the reason tells the model to replace `${CLAUDE_SKILL_DIR}` with the absolute directory of the SKILL.md it is following |

pi clones tool arguments before `tool_call` runs, so the prepended line reaches
execution but not the transcript or the model's context.

`CLAUDE_SESSION_ID` is never pi's raw session id. pi mints UUIDv7 ids whose
first eight hex characters are timestamp bits, and four skills
(`task-claim`, `task-status`, `task-release`, `git-coworker-check`) build an
agent identity as `claude-${CLAUDE_SESSION_ID:0:8}`. Two sessions started within
about a minute would share it. The adapter exports a permutation of the pi id
with the random bits first. A command that references only `CLAUDE_SESSION_ID`
is never blocked. `PI_SESSION_FILE` carries pi's session transcript path for
scripts that need it.

## Extension triad

pi ships without subagents and without an MCP client by design, so running the
marketplace's skills, agents and `.mcp.json` servers under pi takes three
extensions:

| Surface | Extension | Install | Documented in |
|---|---|---|---|
| Skills | `adapters/pi/` (ADR-0022) | `just pi-adapter-register` | § The adapter |
| Subagents | `@tintinweb/pi-subagents` | `pi install npm:@tintinweb/pi-subagents` | § Subagents |
| MCP servers | `pi-mcp-adapter` | `pi install npm:pi-mcp-adapter` | § MCP servers, below |

`just pi-adapter-check` reports the two packages as `SUBAGENTS=` and
`MCP_ADAPTER=`. It reads the `packages` array of `~/.pi/agent/settings.json`
(or `$PI_CODING_AGENT_DIR/settings.json`), where an npm, git or local-path
source counts, and the `npm/node_modules/` tree that `pi install` fills. It
prints the install command for a package found in neither. The adapter is not a package (it is registered through `extensions`),
so the check covers it through its file and dependencies instead (`EXTENSION=`,
`NODE_MODULES=`).

### MCP servers (`pi-mcp-adapter`)

pi-mcp-adapter reads the same project `.mcp.json` that Claude Code does, plus
the user-global `~/.config/mcp/mcp.json`. Servers configured for this
repository, or written by `configure-plugin:configure-mcp`, connect without
changes, including `${VAR}` references in `env`. It does not register each
server's tools. The model gets one `mcp` proxy tool for searching, describing
and calling them (`mcp({ search: "…" })`, then `mcp({ tool: "…", args: {…} })`),
and by default a server connects only when one of its tools is first called.

It differs from Claude Code in four places:

- **Claude Code's own user-scoped servers are not loaded.** Host-specific
  configs are adopted explicitly with `/mcp setup` (or `pi-mcp-adapter init`),
  or loaded as a fallback when `settings.hostConfigDiscovery` is `"on"`.
- **`/mcp disable <server>` persists** in the project's `.pi/mcp.json`. In Claude
  Code it lasts one session.
- **No approval step** is documented for a project `.mcp.json` server; the
  adapter uses the file immediately. Per-call approval is opt-in through
  `settings.approveTools`.
- **Plugin hooks do not run.** Its `claudePlugins` setting loads a Claude
  plugin's `.mcp.json` and skills but never executes the plugin's hooks (#2634
  covers hooks). No marketplace plugin ships a `.mcp.json` today.

A subagent reaches the proxy through the extension's name, which pi-subagents
takes from the package directory: `pi-mcp-adapter`, not the `mcp` used in
pi-subagents' README examples. `tools: "*, ext:pi-mcp-adapter/mcp"` grants it,
but any `ext:` entry switches the agent's extension tools to an explicit
allowlist, which hides `search_skills` unless that is listed too. No marketplace
agent grants an MCP tool, so the exporter emits no such selector; #2647 tracks
the adapter's selector name, which an agent needs before it can list both.

## Pipeline

```
adapters/pi/index.ts ──▶ ~/.pi/agent/settings.json extensions[]  (just pi-adapter-register)
                         (search_skills pull + ranked top-k push, ~600 tok/turn)

.claude/agents/*.md   ──▶ dist/pi/agents ──▶ ~/.pi/agent/agents/    (just export-pi-agents)
                         (21 subagents; pi does not read .claude/agents/)

mlx_lm.server ──▶ models.json ──▶ pi --model mlx-local/<id>
```

### 1. Wire up skill discovery

```
just pi-adapter-check            # verify prereqs first
just pi-adapter-register         # persistent; or `just pi-adapter` to trial it
```

### 2. Serve the model

```
uv tool install mlx-lm
just serve-pi-model              # mlx_lm.server --model <pi_model> --port 8080
curl -s localhost:8080/v1/models # verify it is up
```

`pi_model` / `pi_port` are overridable (`just pi_model=… serve-pi-model`, or
`PI_MODEL` / `PI_PORT`).

### 3. Point pi at the local endpoint — `~/.pi/agent/models.json`

pi reads custom OpenAI-compatible providers from `~/.pi/agent/models.json`
(re-read on every in-session `/model` switch — no restart needed). For an
mlx_lm.server / ollama endpoint:

```json
{
  "providers": {
    "mlx-local": {
      "baseUrl": "http://localhost:8080/v1",
      "api": "openai-completions",
      "apiKey": "mlx",
      "compat": {
        "supportsDeveloperRole": false,
        "supportsReasoningEffort": false
      },
      "models": [
        {
          "id": "mlx-community/Qwen3.6-35B-A3B-4bit",
          "name": "Qwen3.6 35B A3B 4bit (local)",
          "contextWindow": 128000,
          "maxTokens": 32000,
          "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 }
        }
      ]
    }
  }
}
```

The `compat` flags matter for local servers: many OpenAI-compatible servers
don't understand the `developer` role reasoning-capable models use
(`supportsDeveloperRole: false` sends the system prompt as a plain system
message), nor `reasoning_effort` (`supportsReasoningEffort: false`).

`just setup-pi` runs the adapter prereq check, registers the adapter, installs
the subagents (§ Subagents), then prints this block (with your `pi_model` /
`pi_port` interpolated) plus the run command.

### 4. Run pi against the local model

```
cd <project>
pi --model mlx-local/mlx-community/Qwen3.6-35B-A3B-4bit
```

The end-to-end question this answers: does a **small local model actually
invoke** a skill (not merely list it)? That is the real fidelity test — listing
is cheap; a weak quant choosing and reading the right `SKILL.md` on intent is
what makes this useful for local-model testing. The adapter's retrieval quality
on exactly that question is what the eval harness measures
([`../adapters/README.md`](../adapters/README.md) § eval).

## Subagents (`just export-pi-agents`)

Subagents are the one surface pi **cannot** read in place: it never looks at
`.claude/agents/`, so all 21 marketplace agents stay invisible until they are
projected into pi-subagents' frontmatter (#2633). `just setup-pi` does this;
the recipes are standalone too:

```
just export-pi-agents              # -> dist/pi/agents/*.md (source read-only, output reproducible)
just install-pi-agents             # -> ~/.pi/agent/agents/   (additive, global scope)
just install-pi-agents .pi/agents  # -> project scope, which overrides global
```

`install-pi-agents` self-skips with a hint when `@tintinweb/pi-subagents` is not
installed — pi ignores `.pi/agents/` entirely without it, so installing anyway
would look like it worked and change nothing. Re-running is safe: the copy is
additive (your own agent files are never removed) and it takes its input from a
fresh export in a temp dir.

### What survives, and the two edges that do not

pi's agent schema is close to Claude Code's, so most of the projection is a
rename (`maxTurns` → `max_turns`) rather than a loss:

| Claude Code | pi | Note |
|---|---|---|
| `Read`, `Write`, `Edit` | `read`, `write`, `edit` | |
| `Glob` | `find` | pi's file-pattern search |
| `Grep` | `grep` | |
| `Bash(cmd *)` | `bash` | **scope dropped** — see below |
| `Agent(a, b)` | `allowed_subagents: a, b` | nesting; default-off and separate from `tools:` |
| `skills: [a, b]` | `skills: a, b` | both preload; pi's list form also drops the inherited rest |
| `model`, `color`, `thinking`, `maxTurns` | same, `max_turns` | `model: opus` resolves fuzzily in pi; a provider without it reports `(unavailable, fallback: inherit)` |
| `TodoWrite`, `TaskOutput`, `WebFetch`, `WebSearch` | *dropped* | no pi built-in exists |
| `context: fork` | *dropped* | a pi subagent is **always** its own session — fork-isolation is pi's default, and `inherit_context:` is the opposite direction, so no mapping is asserted |

The exporter reports rather than silently adjusts. On the corpus today it prints
`WIDENED_BASH=142` (every scoped `Bash(git diff *)` grant becomes an unscoped
`bash`, because pi's `tools:` is a name-only allowlist — that is a **privilege
widening**, and a property of the target schema, not something this repo can
narrow), `MODEL_PINS=21`, `AGENTS_WITH_NESTING=1`, and `DROPPED_TOOLS=` /
`DROPPED_KEYS=` naming each loss per agent.

`WebFetch`/`WebSearch` *can* be reached as `ext:pi-web-search/web_search`, but a
single `ext:` entry flips pi's extension tools into explicit-allowlist mode — the
agent would silently lose everything else the adapter exposes, `search_skills`
among it — so it is left to a human as an opt-in rather than applied here.

### Verifying it landed

`/agents` in a pi session lists every agent type it loaded, project and global.
`scripts/tests/test-export-pi-agents.sh` is the offline half: it executes the
exporter against a fixture and pins the mapping, the widening/drop reports, the
skip-on-missing-description path, and the emitted tool names against pi's seven
built-ins (an unknown `tools:` entry is a hard `tools-error:` in pi).

## Out of scope (deferred)

- **Hook porting (#2634).** Selective: only the *safety* hooks would earn a pi
  `pi.on` port; the style nudges are noise on a different harness. pi never
  evaluates a Claude Code `hooks.json`, so those guards are inert there today.
- **Prompt templates.** Nothing in the marketplace uses that surface yet.

## Related

- [`../adapters/README.md`](../adapters/README.md) § pi — the adapter (source of truth for skill discovery)
- [`../adapters/CUTOVER.md`](../adapters/CUTOVER.md) — the eval gate that authorized retiring the tier installer
- [`adrs/0022-adapter-over-export-for-foreign-harnesses.md`](adrs/0022-adapter-over-export-for-foreign-harnesses.md) — adapter-over-export decision
- [`opencode-export.md`](opencode-export.md) — the sibling harness: same adapter for skills, plus its own subagent/hook export
- [pi custom-provider docs](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/custom-provider.md) — upstream `models.json` schema
- [pi-mcp-adapter](https://github.com/nicobailon/pi-mcp-adapter) and [pi-subagents](https://github.com/tintinweb/pi-subagents) — upstream READMEs for the two packages in § Extension triad
