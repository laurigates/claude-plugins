# OpenCode: adapter, agent/hook export, local-MLX orchestration

This repo's Claude Code skills, subagents, and hooks can run inside
[OpenCode](https://opencode.ai) against a **local** model served with MLX.

Three surfaces, three mechanisms — they are not interchangeable:

| Surface | How it reaches OpenCode | Why |
|---------|-------------------------|-----|
| **Skills** | The **adapter** — a `search_skills` pull tool plus ranked top-k push injection ([`adapters/opencode/`](../adapters/README.md), ADR-0022) | OpenCode reads Claude Code `SKILL.md` natively but does not budget the listing. All ~400 marketplace skills cost ~34,000 standing tokens per turn; the adapter reaches the same corpus at ~600. |
| **Subagents** | [`scripts/export-opencode-agents.py`](../scripts/export-opencode-agents.py) | OpenCode does **not** auto-load `~/.claude/agents/`, and its agent schema has no `model`/`tools`/`maxTurns`. |
| **Hooks** | [`scripts/generate-opencode-hook-plugins.py`](../scripts/generate-opencode-hook-plugins.py) | OpenCode has no Claude Code hook surface at all; `command`-type PreToolUse/PostToolUse hooks become OpenCode JS plugins. |

> **Skills are no longer exported.** Until #2094 this pipeline ran
> [rulesync](https://github.com/dyoshikawa/rulesync) to convert every skill into
> a flattened `skills/` tree. OpenCode has since implemented the Agent Skills
> standard natively, so the *conversion* solved a problem that no longer exists
> — and the *flattening* was never free. The export is now offline, dependency-
> free, and touches neither skills nor npm.

`just setup-opencode` runs install + configure in one shot and prints the
serve/run next steps.

## Pipeline overview

```mermaid
flowchart LR
    src["claude-plugins<br/>agents + hooks"] -->|just export-opencode| dist["dist/opencode/<br/>{agents,plugins,hook-scripts}"]
    dist -->|just install-opencode| cfg["~/.config/opencode/<br/>or .opencode/"]
    gen["just configure-opencode"] -->|opencode.json + orchestrator.md| cfg
    skills["claude-plugins<br/>~400 skills"] -.->|adapters/opencode/index.ts<br/>read in place| oc
    mlx["mlx_lm.server<br/>:8080 /v1"] -->|OpenAI-compatible| oc
    cfg --> oc["opencode (TUI)"]
    classDef step fill:#4a9eff,color:#fff
    classDef serve fill:#ffa500,color:#000
    classDef adapt fill:#6ba6ff,color:#000
    class src,dist,cfg,gen step
    class mlx serve
    class skills adapt
```

The dotted edge is the point: skills are **read in place** from this checkout at
run time. Nothing is copied, so nothing goes stale.

## 1. Skills — the adapter

`just configure-opencode` registers the adapter for you. Both halves land
together in `opencode.json`:

```json
{
  "plugin": [
    ["/abs/path/to/claude-plugins/adapters/opencode/index.ts", { "k": 5, "pins": [] }]
  ],
  "permission": { "skill": "deny" }
}
```

- The **plugin entry** loads the binding: a `search_skills` tool the model can
  call, plus a per-turn injection of the top-`k` skills ranked against the
  request.
- The **`permission.skill: "deny"`** line suppresses OpenCode's own
  `<available_skills>` block *and* its native `skill` tool. Without it the model
  gets two competing skill surfaces and pays the full uncapped listing anyway —
  it is not optional polish.

Prerequisite: `cd adapters && bun install` (the binding resolves
`@opencode-ai/plugin` from `adapters/node_modules`; OpenCode's own
background-install does not cover a checkout-resident plugin).

```
just oc-adapter-check                 # prereqs, registration, listing suppression
just oc-adapter-register              # wire into an EXISTING hand-tuned opencode.json
just oc-adapter-unregister            # reverse it
just eval-adapter                     # retrieval eval (BM25-only smoke)
```

`configure-opencode` writes the entry into a config it generates; it refuses to
clobber an existing `opencode.json`, so `oc-adapter-register` is the path for a
hand-tuned one. Both write the plugin entry and the deny together, and
`oc-adapter-unregister` removes both — leaving one behind is the failure mode
worth avoiding in either direction.

### The trade-off `permission.skill: "deny"` makes

The adapter indexes **this checkout**. Denying the native `skill` tool therefore
also hides any personal skills you keep in `~/.claude/skills/`. If you have
those and want them, pass `--no-adapter` to `configure-opencode` and accept the
uncapped listing, or move them into the marketplace where the adapter can rank
them.

### Why the adapter rather than a copy — the measurement

Measured 2026-08-24 against OpenCode 1.17.16 (full method and arms in
[`adapters/CUTOVER.md`](../adapters/CUTOVER.md) §8):

| | Standing cost per turn |
|---|---|
| Native listing, 382 skills installed flat | **33,856 tokens** (~88.3/skill) |
| Adapter (`search_skills` + top-5 injection) | **~600 tokens** |

The per-skill figure is a delta between 0/100/382-skill arms, tokenized with the
real tokenizer of the model the generated `opencode.json` targets — not a
chars/4 estimate. That measurement was #2094's last open prerequisite; the
retrieval gate had already frozen on 2026-07-22 at `main_hit_at_k_min = 0.57`
(measured 0.6727).

## 2. Agents and hooks — the export

```
just export-opencode
```

Produces `dist/opencode/{agents,plugins,hook-scripts}/`. Offline, no npm, no
network.

| Surface | Fidelity |
|---------|----------|
| **Subagents** | Structural — `name`, `description`, and the prompt body survive; `model`, `tools`, `maxTurns`, `color`, and dates are dropped (OpenCode's agent schema has none of them). An agent with no `description` is **skipped and reported**, never emitted bare: OpenCode routes subagents by description, so a description-less agent is one the model can never select. |
| **Hooks** | `command`-type **PreToolUse / PostToolUse** only — see [Hooks](#hooks). `prompt`/`agent` hooks and SessionStart / PreCompact have no OpenCode equivalent and are skipped with a per-plugin report. |

Regression guard:
[`scripts/tests/test-export-opencode-agents.sh`](../scripts/tests/test-export-opencode-agents.sh)
asserts the frontmatter shape, that the body survives verbatim, that a
description-less agent is skipped loudly — and that the export still emits **no**
`skills/` tree and invokes no `bunx`/`npx`/rulesync step. Both of those are
silent regressions otherwise: a re-added skills tree costs 34k tokens a turn
without erroring, and a reintroduced network step fails only in CI and the
sandbox.

### Hooks

OpenCode has no Claude Code hook surface, so
[`scripts/generate-opencode-hook-plugins.py`](../scripts/generate-opencode-hook-plugins.py)
(issue [#1605](https://github.com/laurigates/claude-plugins/issues/1605))
projects each plugin's `hooks.json` into an OpenCode JS plugin:

```
dist/opencode/
  plugins/<plugin>-hooks.js            # one OpenCode plugin per hook-bearing plugin
  hook-scripts/<plugin>/hooks/*.sh     # the referenced scripts, copied
```

The generated JS resolves its scripts relative to itself
(`../hook-scripts/<plugin>/`) and exports `CLAUDE_PLUGIN_ROOT` at that root, so
the scripts run unmodified. The two trees must travel together —
`install-opencode.sh` copies both.

| Claude Code | OpenCode | Semantics |
|-------------|----------|-----------|
| `PreToolUse` command hook | `tool.execute.before` | exit 2 or JSON `permissionDecision: "deny"` → **throw** (blocks the call); `"ask"` → `console.warn` + allow (OpenCode has no prompt-from-hook) |
| `PostToolUse` command hook | `tool.execute.after` | exit-2 stderr / JSON `decision: "block"` reason / `additionalContext` appended to the model-visible tool output |
| `prompt` / `agent` hooks | — | skipped: OpenCode has no model-evaluation hook (by design) |
| `SessionStart` / `PreCompact` | — | skipped: no context-injection equivalent |

Matchers translate too: bare tool names (`Bash` → `bash`), path-scoped forms
(`Write(docs/prds/**)` → `write` + glob on `filePath`), and `Skill(name)`
(→ the `skill` tool). Everything that cannot export is reported per plugin on
the export output **and** in the generated file's header comment. A script
that goes missing at runtime **fails open** (`console.error` + allow) rather
than blocking every matched call.

> Note the interaction with the adapter: a `Skill(name)` matcher targets
> OpenCode's native `skill` tool, which `permission.skill: "deny"` disables. Such
> a hook is inert under the adapter flow.

Regression guard: [`scripts/tests/test-export-opencode-hooks.sh`](../scripts/tests/test-export-opencode-hooks.sh)
asserts every referenced script resolves, blocking semantics survive, no
literal `${CLAUDE_PLUGIN_ROOT}` reaches generated code, and prompt hooks stay
skipped.

## 3. Serve the model

OpenCode talks to any OpenAI-compatible `/v1` endpoint. Serve a local model with
[mlx-lm](https://github.com/ml-explore/mlx-lm):

```
uv tool install mlx-lm
just serve-opencode-model
```

`serve-opencode-model` runs `mlx_lm.server --model <model> --port <port>` with
the configured defaults. Override per invocation:

```
just opencode_model=mlx-community/Qwen3-30B-A3B-4bit opencode_port=8080 serve-opencode-model
```

Verify it's up:

```
curl -s localhost:8080/v1/models
```

The response should list your model id. The model id is **your** choice — any id
your local `mlx_lm.server` exposes (an MLX MoE like `Qwen3-30B-A3B`, a 4-bit
community quant, etc.). It is a recipe variable, not a fixed value.

## 4. Provider config

`just configure-opencode` generates this `opencode.json` (real OpenCode schema):

```json
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "mlx-local": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Local MLX",
      "options": { "baseURL": "http://127.0.0.1:8080/v1" },
      "models": { "<model-id>": { "name": "<model-id>" } }
    }
  },
  "plugin": [
    "@openspoon/subtask2", "opencode-pty", "@tarquinen/opencode-dcp",
    ["/abs/path/to/claude-plugins/adapters/opencode/index.ts", { "k": 5, "pins": [] }]
  ],
  "permission": { "skill": "deny" },
  "model": "mlx-local/<model-id>",
  "default_agent": "orchestrator",
  "lsp": true,
  "agent": {
    "build": {
      "permission": {
        "bash": {
          "go test *": "allow", "npm test": "allow", "pytest*": "allow",
          "cargo test*": "allow", "just test*": "allow",
          "git status*": "allow", "git diff*": "allow", "git log*": "allow",
          "*": "ask"
        }
      }
    }
  }
}
```

Note the `plugin` array mixes **strings** (npm packages) and **`[path, config]`
tuples** (checkout-resident plugins with options). Both forms are valid.

The `agent.build.permission.bash` block is a `{pattern: allow|ask|deny}` map
(OpenCode's real shape — **not** `permissions`/`file_edits`/`{allow:[]}`, see
Gotchas). It lets the built-in `build` agent run test/status commands without a
permission prompt during the orchestrator's fan-out, while everything else still
falls through to `"*": "ask"`. Tune the patterns via the generated config.

`<model-id>` and the port come from the `opencode_model` / `opencode_port`
recipe variables; `--adapter-k` tunes the injection budget and `--no-adapter`
skips the adapter entirely. The generator is **non-destructive**: if
`opencode.json` already exists it writes `opencode.json.opencode-sample` instead
and prints a merge hint, so a hand-tuned config is never clobbered.

## 5. Orchestrator agent

`configure-opencode` also writes `agents/orchestrator.md` — a read-only primary
agent that decomposes a request and fans out to the exported subagents:

```markdown
---
description: Central router that decomposes a request and delegates to specialized subagents concurrently.
mode: primary
model: mlx-local/<model-id>
temperature: 0.1
permission:
  edit: deny
  bash: deny
  webfetch: deny
  write: deny
---

# The Orchestrator
You analyze the request, inspect project topology read-only (read/glob/grep/list),
and dispatch specialized subagents via the `task` tool — issuing multiple `task`
calls in one turn for independent work. You never edit files or run bash directly.
```

Why `permission:` and not `tools:`: OpenCode's agent frontmatter uses a
`permission:` map (`allow` / `ask` / `deny` per built-in capability). The
`tools:` form is a deprecated `name: bool` map, not a YAML list. The orchestrator
denies `edit` / `write` / `bash` / `webfetch` so it can only read and delegate —
the actual file edits and shell work happen inside the subagents it dispatches
with the built-in `task` tool.

OpenCode's built-in tools are: `read, write, edit, glob, grep, list, bash, task,
skill`. Under the adapter flow `skill` is denied and replaced by
`search_skills`.

## 6. Install + run

```
just setup-opencode               # global  → ~/.config/opencode
just setup-opencode .opencode     # project → ./.opencode
```

`setup-opencode` = `install-opencode` (copies `agents/`, `plugins/`, and
`hook-scripts/` **additively** — your own agents/plugins are preserved) +
`configure-opencode`, then prints the serve + run next steps.

> **Install into ONE scope only.** OpenCode *merges* global
> (`~/.config/opencode`) and project (`./.opencode`) agents and plugins, so
> installing this marketplace into both loads every agent twice and registers
> each hook plugin twice. `install-opencode` drops a
> `.claude-plugins-opencode-receipt` marker in each scope it installs into and
> emits `STATUS=WARN` + a `FIX=` remediation line if the complementary scope
> already carries one. Pick global *or* project; to switch, remove the other
> scope's `agents/`, `hook-scripts/`, generated `plugins/*-hooks.js`, and
> receipt first.

Then:

```
cd <project>
opencode
```

- Run `/init` once to have OpenCode write an `AGENTS.md` for the project.
- Switch agents with **Tab** or the `/agents` picker — reach `orchestrator` there
  (and it's the `default_agent`, so it's selected on launch).

## 7. Recommended ecosystem plugins

OpenCode has a community plugin ecosystem that can sharpen the orchestrated
local-model workflow. Every plugin below was **verified against npm / GitHub /
opencode.ai/docs** — AI-suggested OpenCode plugin lists have a high fabrication
rate, so names and install mechanisms here are the real ones, not the
brainstormed forms.

### How plugins load

A plugin is a JS/TS module. Three load paths:

- **npm package** listed in the `"plugin": [...]` array of `opencode.json` —
  bare (`opencode-pty`), scoped (`@openspoon/subtask2`), or version-pinned
  (`opencode-vibeguard@0.1.0`). OpenCode auto-installs them with Bun on startup.
- **Absolute path**, optionally as a `[path, config]` tuple — how the
  skill-discovery adapter is registered. Not auto-installed; its own
  dependencies must already be resolvable (hence `cd adapters && bun install`).
- **Local file** under `.opencode/plugins/` (project) or
  `~/.config/opencode/plugins/` (global) — how the generated hook plugins load.

There is **no `github:user/repo` shorthand** and **no central registry** —
discover plugins by searching npm for the `opencode-plugin` keyword.

### Baked-in defaults

`just configure-opencode` writes a small, curated `plugin:` array (overridable
via `OPENCODE_PLUGINS` or `just opencode_plugins="…" configure-opencode`):

| Plugin (npm) | Why it's a default |
|--------------|--------------------|
| `@openspoon/subtask2` | The only orchestration plugin installable via the npm `plugin:` array. Adds flow-control over `/commands` and **verifies a subtask's output against the codebase before merging it back** — directly strengthens the orchestrator's fan-out. |
| `opencode-pty` | Runs background/interactive processes (dev servers, test watchers, REPLs) in a pseudo-terminal and can send input (e.g. answer a `y/n` prompt), so a subagent doesn't hang on the synchronous built-in `bash` tool. |
| `@tarquinen/opencode-dcp` | **Dynamic context pruning** — dedupes repeated tool outputs and exposes a model-invokable `compress` tool, stretching a local model's smaller context window. The GitHub repo name `opencode-dynamic-context-pruning` is the **same package**; never list a second copy. |

All three are npm, no API key required, self-host-friendly.

> **Note on `opencode-skills`:** not a default, and now actively wrong — the
> adapter is the skill surface, and a second one would re-introduce the
> duplicate-listing problem `permission.skill: "deny"` exists to remove.
> `opencode-gemini-auth` is likewise not a default: it is a Gemini *auth* plugin
> with no value in a pure-local MLX setup.

### Opt-in npm plugins

Add these to your own `plugin:` array (or `OPENCODE_PLUGINS`) if they fit:

| Plugin (real npm name) | What it does | Caveat |
|------------------------|--------------|--------|
| `@nick-vi/opencode-type-inject` | Injects TS/Svelte type signatures into file reads so the model skips whole source files (token saver). | TypeScript/Svelte only. Note the scoped name — bare `opencode-type-inject` is **not** the install string. |
| `opencode-scheduler` | Schedules `opencode run` jobs on the OS-native scheduler (launchd / systemd timers / Task Scheduler, cron as fallback) for overnight maintenance. | Cross-platform — **not** macOS/launchd-only as sometimes claimed. |
| `opencode-vibeguard` | Redacts secrets/PII to placeholders before context reaches the model, restores locally. | Early `v0.1.0`. Mainly valuable when mixing local + an **external** API; low value for a pure-local setup. Alternative: `opencode-secret-redactor`. |
| `@f97/opencode-morph-fast-apply` / `@morphllm/opencode-morph-plugin` | Morph "fast apply": lazy edit markers (`// ... existing code ...`) for ~10× faster code patching. | **Requires an external Morph API key** — this breaks a fully-self-hosted-via-mlx setup. Opt in only if you accept an external apply service. Bare `opencode-morph-fast-apply` is a GitHub repo name, not the npm install string. |

### Already covered — do not double-install

`@tarquinen/opencode-dcp` (dynamic context pruning) is a **baked-in default**
(see the defaults table above). The frequently-suggested
`opencode-dynamic-context-pruning` is the **same package** — that's the GitHub
repo name; `@tarquinen/opencode-dcp` is its npm name. Do not add a second copy to
`OPENCODE_PLUGINS` or a hand-tuned `plugin:` array.

### OCX plugins (third-party CLI/registry)

Three real orchestration plugins by `kdcokenny` are distributed via the
third-party **OCX** CLI + registry (`registry.kdco.dev`), **not** the npm
`plugin:` array — so they're a separate, explicitly opt-in path with a
third-party trust dependency. They write into `.opencode/plugin/`.

```
just install-opencode-ocx        # installs worktree + background-agents via OCX
```

| OCX plugin | Recipe installs it? | Notes |
|------------|---------------------|-------|
| `worktree` | ✅ | Per-session git worktrees so parallel agents avoid branch collisions. Complements our `agent-coworker-detection` discipline. |
| `background-agents` | ✅ | Async task delegation; persists sub-agent results to disk so they survive context compaction. |
| `opencode-workspace` | ❌ **excluded by design** | Bundles its own researcher/coder/scribe/reviewer agents + DCP + worktrees (16 components). **Overlaps and competes with the agents + orchestrator we already export** — prefer ours. Documented here for awareness; `install-opencode-ocx` deliberately skips it. |

`install-opencode-ocx` requires the OCX CLI on `PATH` (it does not install OCX
itself); without it the recipe prints a prerequisite hint and exits cleanly.

### Verified-vs-claimed corrections

So the fabrication-prone forms aren't re-adopted:

| Suggested form | Reality |
|----------------|---------|
| `opencode-dynamic-context-pruning` as a *new* install | Same package as the already-installed `@tarquinen/opencode-dcp` — redundant. |
| bare `opencode-type-inject` | Scoped: `@nick-vi/opencode-type-inject`. |
| bare `opencode-morph-fast-apply` | `@f97/opencode-morph-fast-apply` or `@morphllm/opencode-morph-plugin`; **needs a Morph API key**. |
| `opencode-scheduler` = macOS/launchd-only | Cross-platform (launchd/systemd/cron fallback). |
| `background-agents` / `workspace` / `worktree` via npm `plugin:` array | OCX-distributed (`registry.kdco.dev`), not npm; `workspace` overlaps our exported agents. |

## Gotchas — common-but-wrong config

A plausible-looking config that does **not** work in OpenCode. If you're adapting
a brainstorm or an older snippet, check it against this table:

| Looks right | Actually | Use instead |
|-------------|----------|-------------|
| `"providers": { id: { api_base, api_key }}` | No such keys | `"provider": { id: { "npm", "options": { "baseURL" }, "models" }}` |
| `"attention": { enabled }` in `opencode.json` | Lives in `tui.json` | Omit from `opencode.json` |
| `tools:` as a YAML list in agent frontmatter | `tools:` is a deprecated `name: bool` map | `permission:` map (`allow`/`ask`/`deny`) |
| `"permissions": { "file_edits": ..., "bash": { "allow": [...], "default": ... }}` | No such keys; this is a brainstorm shape | `"permission": { "edit": ..., "bash": { "go test *": "allow", "*": "ask" }}` (singular key, `edit` not `file_edits`, bash is a pattern→verdict map) |
| Config-level `"agents": { ... }` (plural) | The opencode.json key is singular | `"agent": { "build": { ... }}` (directories are plural `agents/`; the JSON key is singular `agent`) |
| `"tools": { "skill": false }` to hide the native listing | Deprecated surface, normalized into `permission` | `"permission": { "skill": "deny" }` |
| Copying `skills/` into the OpenCode config dir | ~34,000 standing tokens/turn, and it merges with the adapter's injection | Register the adapter (`just oc-adapter-register`) |
| `get_symbols_overview` builtin tool | Not a builtin | Builtins: `read, write, edit, glob, grep, list, bash, task, skill` |
| `Leader+Down` / arrow keys to switch subagents | Unverified keybinds | **Tab** or `/agents` |
| Hardcoding *any* model id as if it's universal | The id must match what *your* `mlx_lm.server` exposes | Set your own MLX model id via `opencode_model` (verify with `curl localhost:8080/v1/models`) |

## Limitations

- **Agent orchestration metadata does not survive** — `model`, `tools`, and
  `maxTurns` have no place in OpenCode's agent schema. The generated
  `orchestrator.md` re-establishes a primary agent by hand; exported subagents
  keep only their prompt + description.
- **Hook export is partial by platform design** — `prompt`/`agent` hooks and
  SessionStart / PreCompact command hooks have no OpenCode equivalent and are
  skipped with a per-plugin report; PreToolUse `permissionDecision: "ask"`
  degrades to a non-blocking warning (see [Hooks](#hooks)).
- **The adapter reads this checkout** — skills are not copied, so OpenCode needs
  the checkout present at the registered path, and personal `~/.claude/skills/`
  are hidden while `permission.skill: "deny"` is set.
- **Local-model capability** — a local MLX model is smaller than a frontier
  model; complex orchestration may need a larger quant or a stronger model id.

## Related

- [`adapters/README.md`](../adapters/README.md) — the adapter: bindings, ranker, eval harness
- [`adapters/CUTOVER.md`](../adapters/CUTOVER.md) — the frozen retrieval gate (§1) and the OpenCode token calibration (§8)
- [`docs/adrs/0022-adapter-over-export-for-foreign-harnesses.md`](adrs/0022-adapter-over-export-for-foreign-harnesses.md) — why an adapter rather than an export
- [`scripts/export-opencode.sh`](../scripts/export-opencode.sh) — agent + hook export driver
- [`scripts/export-opencode-agents.py`](../scripts/export-opencode-agents.py) — subagent projection
- [`scripts/generate-opencode-hook-plugins.py`](../scripts/generate-opencode-hook-plugins.py) — hooks.json → OpenCode JS plugin generator
- [`scripts/tests/test-export-opencode-agents.sh`](../scripts/tests/test-export-opencode-agents.sh) — agent-export + no-skills-tree regression guard
- [`scripts/tests/test-export-opencode-hooks.sh`](../scripts/tests/test-export-opencode-hooks.sh) — hooks-export regression guard
- [`scripts/install-opencode.sh`](../scripts/install-opencode.sh) — additive installer
- [`scripts/configure-opencode.sh`](../scripts/configure-opencode.sh) — config + adapter + orchestrator generator
- [`scripts/tests/test-configure-opencode.sh`](../scripts/tests/test-configure-opencode.sh) — schema + adapter-registration regression guard
- [OpenCode docs](https://opencode.ai/docs) — upstream source of truth for the schema
