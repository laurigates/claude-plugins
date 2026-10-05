---
created: 2026-02-25
modified: 2026-10-04
reviewed: 2026-09-23
paths:
  - "**/agents/**"
---

# Agent Development (Claude Code 2.1.76+)

Patterns and standards for creating and configuring custom agents in Claude Code plugins.

> **Note (2.1.63)**: The `Task` tool was renamed to `Agent` tool. Existing `Task(...)` references in settings and agent definitions still work as aliases, but new code should use `Agent`.

> **Note (2.1.140)**: The `Agent` tool's `subagent_type` parameter accepts case- and separator-insensitive values. `"Code Reviewer"`, `"code_reviewer"`, and `"code-reviewer"` all resolve to the same agent. Prefer the canonical kebab-case form (`code-reviewer`) in plugin code so grep stays predictable.

> **Note (2.1.143)**: `claude --agent <name>` finds plugin-contributed agents without the `plugin:` prefix. Previously, `claude --agent code-reviewer` only matched user/project agents and silently missed `my-plugin:code-reviewer` even when the plugin was enabled.

> **Note (2.1.139)**: Subagent HTTP requests carry two correlation headers — `x-claude-code-agent-id` identifies the subagent, and `x-claude-code-parent-agent-id` identifies the spawning agent. Use these for tracing in HTTP hooks, MCP servers, and any proxy that wants to attribute traffic to specific agent chains.

> **Note (2.1.157)**: An `agent` field in `settings.json` is honored for dispatched sessions, selecting the named agent definition by default. A `--agent <name>` flag at the call site overrides the settings value.

## Agent vs Skill

| Use Agent When... | Use Skill When... |
|-------------------|-------------------|
| Task requires autonomous multi-step work | Task is a guided workflow with human oversight |
| Context isolation is needed | Context sharing is fine |
| Parallel execution with other agents | Sequential single-session work |
| Task produces self-contained output | Task collaborates with the main session |
| You want to protect the main context window | Main context can absorb the work |

## Agent File Structure

Agents live in `<plugin-name>/agents/<agent-name>.md`.

> **Note (2.1.198)**: The `/agents` wizard was removed; its menu entry followed in 2.1.281. Write `<plugin>/agents/<name>.md` directly (below).

### Required Frontmatter

```yaml
---
name: agent-name
description: What this agent does and when to use it.
model: opus
tools: Glob, Grep, Read, Edit, Write, Bash(npm *)
created: YYYY-MM-DD
modified: YYYY-MM-DD
reviewed: YYYY-MM-DD
---
```

> **Todo/task tools (2.1.233+)**: on current models a subagent has `TaskCreate`/`TaskUpdate`/`TaskList`/`TodoWrite` only when the parent session opted in; listing them in `tools:` does not opt in. An agent body that *depends* on the task list must say what to do without it. Mechanics: `.claude/rules/agentic-permissions.md` § Task-tool availability.

### Optional Frontmatter Fields

```yaml
---
# ... required fields above ...
color: "#E53E3E"       # Hex color for UI display
isolation: worktree    # Filesystem isolation: give agent its own git worktree
permissionMode: default  # Permission mode: default, acceptEdits, dontAsk, bypassPermissions, plan
maxTurns: 20           # Maximum agentic turns before agent stops
effort: low            # Per-agent effort override (2.1.251+); default inherits session
background: false      # Set true to always run as a background task
memory: user           # Persistent memory scope: user, project, or local
skills:                # Preload skill content into agent context at startup
  - api-conventions
  - error-handling-patterns
mcpServers:            # MCP servers available to this agent
  - slack
hooks:                 # Agent-scoped hooks (active only when agent is running)
  Stop:
    - matcher: ""
      hooks:
        - type: command
          command: 'bash "${CLAUDE_PLUGIN_ROOT}/hooks/verify.sh"'
          timeout: 30
---
```

> **Note**: Agent hooks defined with `Stop` are automatically converted to `SubagentStop` when the agent runs as a subagent, since subagents fire `SubagentStop` instead of `Stop`.

> **Note (2.1.218)**: Agent-frontmatter `hooks:` fire only once the agent file's own containing folder has accepted the workspace-trust dialog.

### Complete Field Reference

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | Yes | Agent identifier (kebab-case); `:` is rejected (2.1.218) — reserved for plugin namespacing (`plugin:agent-name`) |
| `description` | string | Yes | Purpose and use cases for agent selection |
| `model` | string | Yes | `opus`, `sonnet`, `haiku`, `fable` (2.1.255+), `inherit`, or a full model ID (e.g. `claude-fable-5-1`). Aliases resolve to the current generation (`opus` → Opus 5.5, `sonnet` → Sonnet 5, `haiku` → Haiku 4.5, `fable` → Fable 5.1). Full IDs honoured since 2.1.74 |
| `effort` | string | No | `low`, `medium`, `high`, `xhigh`, or `max` (2.1.251+) — overrides the session effort while this agent runs; default inherits. This is the per-agent cost lever the Model Selection section refers to |
| `tools` | comma-list | Yes | Tools the agent can use; use `Agent(name)` to restrict spawnable subagents |
| `isolation` | string | No | `worktree` to run agent in an isolated git worktree |
| `color` | string | No | Hex color for UI display |
| `permissionMode` | string | No | `default`, `acceptEdits`, `dontAsk`, `bypassPermissions`, or `plan` |
| `maxTurns` | number | No | Maximum agentic turns before agent stops |
| `background` | bool | No | Set `true` to always run as a background task |
| `memory` | string | No | Persistent memory scope: `user`, `project`, or `local` |
| `skills` | list | No | Skill names to preload into agent context at startup |
| `mcpServers` | list | No | MCP server names or inline configs available to this agent |
| `hooks` | object | No | Agent-scoped hooks (same schema as settings.json hooks) |
| `disallowedTools` | comma-list | No | Tools to deny even if in the inherited list |
| `experimental.cacheTtl` | string | No | `5m` or `1h` (2.1.248+), written as a nested map (`experimental:` → `cacheTtl: 1h`) — prompt-cache TTL for the agent's own requests when no subagent TTL setting is configured; ignored on usage credits. Cache reads on Fable 5.1 are $0.25/MTok, so `1h` is cheap for agents re-spawned across a session |
| `omitClaudeMd` | bool | No | Run the subagent without user/project/local CLAUDE.md files (2.1.271+); managed policy files still load |
| `created` | date | Recommended | Initial creation date |
| `modified` | date | Recommended | Last substantive change |
| `reviewed` | date | Recommended | Last verified against current docs |

Claude Code ignores an agent frontmatter key it does not recognize, without an error ([sub-agents.md § Supported frontmatter fields](https://code.claude.com/docs/en/sub-agents#supported-frontmatter-fields)). That includes the skill-only fields `context`, `agent`, and `allowed-tools`, which read as if they configure the agent and do nothing on one. `scripts/check-agent-frontmatter-keys.sh` fails on any key outside the documented set plus the three lifecycle dates above.

### `tools` vs `allowed-tools`

| Field | Used In | Supports |
|-------|---------|----------|
| `tools` | Agent `.md` files in `agents/` | Tool names, `Bash(command *)` patterns, `Agent(name)` to restrict subagent spawning |
| `allowed-tools` | Skill `SKILL.md` files | Tool names, `Bash(command *)` patterns |

Both support granular Bash permission patterns like `Bash(git status *)`.

To restrict which subagents an agent can spawn (when running as main thread with `claude --agent`):

```yaml
tools: Agent(worker, researcher), Read, Bash
```

This is an allowlist — only `worker` and `researcher` can be spawned. To allow any subagent without restriction, use `Agent` without parentheses. If `Agent` is omitted, the agent cannot spawn any subagents. Every entry of a multi-entry `Agent(a, b)` list is honored as of 2.1.147; earlier releases kept only the last.

#### Pin a deliberate roster with the allowlist, not prose

When you have designed a fixed set of domain agents (frontend, database, security, …) and want the orchestrator to delegate **only** to them, encode that intent as the `Agent(name1, name2, …)` allowlist above — not as a prose instruction like "please only use my agents." The allowlist is harness-enforced and non-negotiable; a prose preference is a wish the model can override the moment it decides an ad-hoc agent fits the task better. This is the difference between an **invariant** (a boundary stated as a rule) and a **heuristic** (a suggestion the model weighs): models adhere to the former far more reliably, so the roster you actually depend on belongs in frontmatter.

| You want… | Express it as | Why |
|-----------|---------------|-----|
| Delegation pinned to a known roster | `tools: Agent(frontend, database, security)` | Harness-enforced; ad-hoc agents outside the set cannot be spawned |
| Roster plus a deterministic fan-out | The allowlist **and** an orchestration skill that spawns one declared agent per domain | Removes roster choice from the model entirely (see `agent-patterns-plugin:parallel-agent-dispatch`) |
| Truly open-ended delegation | `Agent` without parentheses | Intentional — only when no fixed roster exists |

The failure this prevents: an orchestrator that "used to respect my agents" starts inventing its own the moment the roster lives only in prose. If the model is spawning agents you didn't intend, the fix is to move the roster from instruction into the `Agent(...)` allowlist.

### Subagent Nesting Depth (2.1.219+)

Sub-agents can spawn their own sub-agents **up to 3 levels deep by default**, governed by `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`. Set it to `1` to disable nesting entirely, or higher to allow deeper chains. Design delegation chains against 3, not against the old 5 — a chain built for five levels is refused at four, and the refusal surfaces as a failed spawn partway through a wave rather than as a configuration error.

The ceiling moved twice in quick succession, so a rule or skill citing 5 is reading a superseded changelog:

| Version | Default nesting depth |
|---------|----------------------|
| 2.1.172 | 5 (background subagents) |
| 2.1.181 | 5 (extended to foreground subagents) |
| 2.1.217 | **none** — nesting off by default, `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` introduced to re-enable |
| 2.1.219 | **3** (current, verified against the changelog through 2.1.258) |

> **Why this went stale:** 2.1.217 and 2.1.219 fall inside 2.1.186–2.1.231, a band that no changelog review ever covered. The automated review filed its last issue on 2026-06-21 (#1733, 2.1.138 → 2.1.185) and then ran green for 13 weeks filing nothing, while `.claude-code-version-check.json` was advanced by hand to 2.1.257. `scripts/check-audit-liveness.sh` now watches for the silent-green half of that.

> **Note (2.1.178)**: Under auto mode, subagent spawns are now evaluated by the classifier **before launch** — an `Agent(...)` call that auto mode would not permit is blocked up front rather than after the subagent starts. Pair with the `Agent(model:opus)`-style parameter rules in `.claude/rules/agentic-permissions.md` to constrain which subagents may be spawned.

> **Note (2.1.116+)**: Agent frontmatter `hooks:` and `mcpServers:` are active when the agent runs as a main-thread session via `claude --agent`, not just as subagents.

### Concurrency Cap (2.1.217+)

Distinct from nesting depth above, Claude Code also caps how many subagents may run **concurrently** in one session — default **20**, override with `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS`. A `Workflow`/parallel fan-out beyond 20 waves queues rather than fails, but design large fan-outs (`agent-patterns-plugin:parallel-agent-dispatch`) with this ceiling in mind. `--max-budget-usd`, once hit, halts running background subagents and denies further spawns (2.1.217) — a budget-capped session's fan-out can die mid-wave for a reason unrelated to depth or concurrency.

## Model Selection for Agents

**Default to `model: opus` for every plugin agent.** A subagent's output feeds back into the main loop as a tool result, so a weaker delegate quietly degrades everything downstream. Measured on the Opus 4.8 / Sonnet 4.6 generation, Opus at *low* effort beat Sonnet at *high* effort on both quality and token efficiency, so **`effort`, not `model`, is the cost lever** for delegated work. The `opus` / `sonnet` aliases resolve to Opus 5.5 (2.1.280) / Sonnet 5, and effort level names do not map across model generations — re-run the `skill-evaluation.md` Tier 2 sweep before changing an agent's effort on the strength of the old figure. This matches the user-global standard in `~/.claude/rules/agent-and-tool-selection.md` ("Opus Is the Floor for Subagents and Agent Teams").

| Model | Use For |
|-------|---------|
| `opus` | **Default for all subagents** — reasoning, review, debugging, refactoring, *and* mechanical/high-volume work (dial `effort` down for the latter rather than downgrading the model) |
| `fable` | Sanctioned for the hardest delegated reasoning (long-horizon, multi-file, adversarial verification). Accepted by `scripts/check-agent-model.sh`. Not the default: no plan defaults to Fable and it costs 2.5x Opus 5.5 per token |
| `sonnet` / `haiku` | Avoid for subagents. The one sanctioned exception is the `agent-patterns-plugin:cold-read-gate` haiku reader, where a low-capability model is the *measurement instrument*, not a delegate. |

`model: opus` remains the committed floor for plugin agents (portable: every plan has Opus). `inherit` is not used for plugin agents because it would also inherit Sonnet/Haiku sessions below the floor. `effort:` frontmatter is the cost lever; use `effort: low` for mechanical/high-volume agents.

**Resolution order (2.1.251+):** per-spawn `Agent(model: …)` > agent frontmatter `model:` > `CLAUDE_CODE_SUBAGENT_MODEL` > the main session model. `CLAUDE_CODE_SUBAGENT_MODEL_FORCE` (2.1.257) overrides all of these, so a frontmatter `model: opus` is a default, not a guarantee, when a user or CI environment sets the force variable; `scripts/check-agent-model.sh` checks the frontmatter only. The model actually used is reported in the `SubagentStart` hook's `subagent_model` field (`.claude/rules/hooks-reference.md`).

On an org account that restricts model choice, an agent's `model: opus` frontmatter steps down to the newest org-allowed model in the Opus family rather than falling back to the parent session's model (2.1.222); a hard-restricted request instead warns and runs the parent's model (2.1.223).

> **Note (fast mode)**: Fast mode is available only on Opus 5.5, Opus 5 and Opus 4.8; Fable 5.1 has no fast mode. The legacy fast-mode override env var has been a no-op since 2.1.160 — delete it from agent launch scripts.

## Context Isolation

Every named agent is context-isolated by default: it starts in a fresh context window with its own system prompt, the brief the parent writes, the CLAUDE.md hierarchy, a git status snapshot, and any preloaded `skills:` ([sub-agents.md § What loads at startup](https://code.claude.com/docs/en/sub-agents#what-loads-at-startup)). A named agent does not see the parent's conversation history, and no agent frontmatter field changes that. Its tool calls stay out of the parent's context, and only its final result comes back.

### `context: fork` is a skill field, not an agent field

Three mechanisms share the word "fork", and only the last one hands a subagent the parent's conversation:

| Mechanism | Where it is set | What the subagent sees |
|-----------|-----------------|------------------------|
| `context: fork` in **skill** frontmatter | a `SKILL.md` | Only the skill body, run in a new subagent of the `agent:` type — it does not see the conversation history ([skills.md § Run skills in a subagent](https://code.claude.com/docs/en/skills#run-skills-in-a-subagent)). Isolation, despite the name. See `.claude/rules/skill-fork-context.md` |
| `context:` in **agent** frontmatter | an `agents/*.md` | Nothing changes. It is absent from the subagent frontmatter table, and Claude Code ignores unrecognized fields without an error. Measured inert in #2646: agents with and without it returned bit-identical `subagent_tokens` (2549), both blind to the parent turn |
| The runtime `fork` subagent type | the `Agent` call, `subagent_type: "fork"` | The parent's whole conversation, system prompt, tools, and model ([sub-agents.md § Fork the current conversation](https://code.claude.com/docs/en/sub-agents#fork-the-current-conversation)) |

A research agent that should keep verbose output out of the main window needs no field: a named agent already does. For work that needs the conversation so far, dispatch a fork instead of a named agent.

> **Runtime behaviour lives in [`agent-runtime.md`](agent-runtime.md):** runtime fork vs named agent, the subagent context budget, worktree isolation and `worktree.baseRef` (gitignored inputs such as `.env` reach a worktree only via `.worktreeinclude` — see `/configure:worktreeinclude`), background execution, dynamic-workflow caveats, `worktree.bgIsolation`, MCP policy for frontmatter servers, and the `claude agents` CLI.

## Preloading Skills into Agents

Use the `skills` field to inject full skill content into an agent's context at startup. Unlike the main session where skill descriptions are loaded and full content loads on invocation, preloaded skills are fully injected immediately.

```yaml
---
name: api-developer
description: Implement API endpoints following team conventions
skills:
  - api-conventions
  - error-handling-patterns
---
Implement API endpoints. Follow the conventions and patterns from the preloaded skills.
```

Agents do **not** inherit skills from the parent session — they must be listed explicitly.
> **Note (2.1.133+)**: Subagents can discover project, user, and plugin skills via the `Skill` tool. Skills listed in `skills:` frontmatter are preloaded; the `Skill` tool discovers others on demand.

## Persistent Agent Memory

> **This repo deliberately does not use agent `memory:` (and keeps Claude's auto
> memory disabled).** Durable knowledge lives in **curated rules and skills** —
> version-controlled, reviewable, and deliberately steerable — not in an opaque
> per-agent `MEMORY.md` that accretes without a gate. This is `docs/PRINCIPLES.md`
> §5 ("Codify the fix; don't promise to remember"): the substrate remembers so
> the agent doesn't have to. The section below documents the Claude Code feature
> for completeness; treat it as reference, not a recommendation. No agent in this
> repo sets `memory:`, and no `MEMORY.md` is tracked.

When `memory` is set (scope `user` → `~/.claude/agent-memory/<name>/`, `project` → `.claude/agent-memory/<name>/`, `local` → `.claude/agent-memory-local/<name>/`, not committed), Read/Write/Edit are auto-enabled for that directory and the first 200 lines of its `MEMORY.md` are injected into the agent's system prompt.

## Agent Memory (Session Hierarchy)

Agents participate in Claude Code's memory hierarchy (CLAUDE.md files, rules, auto memory).

**For agents:**
- Agents inherit the full memory hierarchy of their parent session in principle, but **in practice user-level rules under `~/.claude/rules/*.md` do not reliably hold across agent threads** (issue #1109 measured 200+ weekly hook-block reminders even though the rules existed at the user scope).
- A named (non-fork) agent loads the parent's CLAUDE.md hierarchy but not its conversation or its auto memory; `omitClaudeMd: true` drops the CLAUDE.md files, and the `memory:` field gives the agent persistent memory of its own ([sub-agents.md § What loads at startup](https://code.claude.com/docs/en/sub-agents#what-loads-at-startup))
- Auto memory in `~/.claude/projects/<project>/memory/` persists across all sessions

### Bake Tool-Selection Rules into Agent Bodies

For rules an agent **must not forget** between threads — the friction-mining ones, like "use Glob, not find" — embed them directly in the agent's body so they live in the system prompt rather than depending on inherited memory. Every plugin agent in this repo carries a `## Tool Selection` section that lists the bash idioms the harness blocks and the dedicated tool to use instead. New plugin agents must include the same section; `scripts/check-agent-tool-selection.sh` enforces it.

## Agent Teams (Multi-Agent Collaboration)

Team mechanics — the implicit team (2.1.178), `SendMessage` / `ListAgents` and cross-session messaging, team roles, and when to choose teams over subagents — live in the `agent-patterns-plugin:agent-teams` skill. What stays here is the per-agent body convention:

### Team Configuration

Each agent's `## Team Configuration` section should document its optimal team role:

```markdown
## Team Configuration

**Recommended role**: Teammate (preferred) or Subagent

| Mode | When to Use |
|------|-------------|
| Teammate | Multi-aspect tasks: spawn parallel specialists |
| Subagent | Single focused task producing one result |
```

## Tool Restrictions

### `disallowedTools` Field

Explicitly block specific tools while allowing everything else:

```yaml
---
name: read-only-explorer
description: Explore codebase without modifications
model: opus
tools: Bash, Read, Grep, Glob
disallowedTools: Write, Edit, NotebookEdit
---
```

### Restriction Patterns

| Pattern | Configuration | Use Case |
|---------|---------------|----------|
| Read-only research | `tools: Read, Grep, Glob, WebSearch` | Analysis without side effects |
| Safe code executor | `tools: Bash, Read` + `disallowedTools: Write, Edit` | Run but not modify |
| Documentation writer | `tools: Read, Write, Edit, Grep, Glob` + `disallowedTools: Bash` | Write docs safely |
| Full-power developer | `tools: Bash, Read, Write, Edit, Grep, Glob` | Complete implementation |

## Agent Directory Layout

```
my-plugin/
├── .claude-plugin/
│   └── plugin.json
├── agents/
│   ├── specialist-agent.md    # Custom agent definition
│   └── another-agent.md
├── skills/
│   └── ...
└── README.md
```

Plugin agents are auto-discovered by Claude Code from the `agents/` directory.

User-level custom agents can be placed in `~/.claude/agents/`.

### Scope Priority

When multiple agents share the same name, higher-priority location wins:

| Location | Scope | Priority |
|----------|-------|----------|
| `--agents` CLI flag (JSON) | Current session only | 1 (highest) |
| `.claude/agents/` | Current project | 2 |
| `~/.claude/agents/` | All projects | 3 |
| Plugin `agents/` directory | Where plugin is enabled | 4 (lowest) |

> **Note (2.1.178)**: With **nested** `.claude/` directories, the agent (and workflow / output-style) **closest to the working directory wins** on a name collision. A repo-root `.claude/agents/reviewer.md` is shadowed by a `subdir/.claude/agents/reviewer.md` when working inside `subdir/`. Project-scope workflow saves now target the closest existing `.claude/workflows/`.

CLI-defined agents use `--agents` flag with JSON (same frontmatter fields, use `prompt` for body). With `-p` it also takes a JSON file path (2.1.281):
```bash
claude --agents '{"my-agent": {"description": "...", "prompt": "...", "tools": ["Read"]}}'
```

## Checklist for New Agents

- [ ] Agent name is kebab-case
- [ ] `description` matches real user intents (not just tool jargon)
- [ ] `model: opus` (the default for all subagents — `effort` is the cost lever, not the model; see Model Selection for Agents). The only sanctioned non-Opus subagent is the cold-read-gate haiku reader.
- [ ] `tools` uses principle of least privilege
- [ ] Granular `Bash(command *)` patterns used instead of bare `Bash`
- [ ] Frontmatter uses only documented subagent fields — no skill fields such as `context:` or `allowed-tools:` (`scripts/check-agent-frontmatter-keys.sh`)
- [ ] `isolation: worktree` added if agent needs filesystem-level git isolation
- [ ] `permissionMode` set if non-default permission behavior is needed
- [ ] `maxTurns` set if agent should be bounded
- [ ] `memory` scope set if agent needs cross-session persistence
- [ ] `skills` list populated if agent needs specific domain knowledge preloaded
- [ ] `## Team Configuration` section documents teammate vs subagent recommendation
- [ ] `## Scope` section defines input/output/step count
- [ ] Date fields set (`created`, `modified`, `reviewed`)
- [ ] Agent added to plugin `README.md` agents table
- [ ] If relevant, `color` field set for UI display

---

## Claude Agent SDK (Python)

For Python apps built on `claude-agent-sdk` — `query()` vs `ClaudeSDKClient`, the two-phase interaction pattern that replaces `AskUserQuestion` in subprocess mode, and running the agent in a worktree without losing uncommitted work — see the `agent-patterns-plugin:agent-cli-worktree-safety` skill.

## Related Rules

- `.claude/rules/agentic-permissions.md` — Granular tool permission patterns
- `.claude/rules/skill-development.md` — Skill creation (use when agent is not needed)
- `.claude/rules/agentic-optimization.md` — CLI output optimization for agent consumption
- `.claude/rules/agent-runtime.md` — runtime behaviour of dispatched agents: fork vs briefed agent, worktree isolation, background execution, dynamic-workflow caveats, `claude agents` CLI
- `.claude/rules/agent-coworker-detection.md` — Detecting in-flight coworker changes before destructive git ops

