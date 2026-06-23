---
created: 2025-12-20
modified: 2026-06-08
reviewed: 2026-06-08
paths:
  - "**/skills/**"
  - "**/SKILL.md"
---

# Skill Development

## Skills and Commands Unified (Claude Code 2.1.7+)

As of Claude Code 2.1.7, skills and slash commands have been merged into a unified system:

| Feature | Behavior |
|---------|----------|
| **Unified invocation** | Both skills and commands use `/name` syntax |
| **Auto-discovery** | Claude Code automatically discovers skills/commands |
| **Hot-reload** | Changes to skill/command files take effect immediately |
| **SlashCommand tool** | Commands can invoke other commands via the SlashCommand tool |

### Hot-Reload

Skills and commands are reloaded automatically when modified:
- No need to restart Claude Code
- Changes take effect on the next invocation
- Useful for iterative development

### Re-scanning Skill Directories (2.1.152+)

Editing an existing skill hot-reloads, but **adding** a new skill directory needs a re-scan:

| Trigger | Effect |
|---------|--------|
| `/reload-skills` command | Re-scans skill directories without restarting the session |
| `SessionStart` hook returning `reloadSkills: true` | Makes newly installed skills available in the same session |

Use `/reload-skills` after scaffolding a new skill so it becomes invocable immediately. The `SessionStart` hook form is the way an installer hook (e.g. one that drops skills into place on session start) surfaces those skills without a restart.

### Nested `.claude/skills` Directories (2.1.178+)

Skills in **nested** `.claude/skills` directories (not just the project root) now load. When two skills collide on name across scopes, the skill is surfaced in disambiguated `plugin:name` form so both remain addressable. Combine with the project-root auto-load behavior in `.claude/rules/plugin-structure.md` (§ Local `.claude/skills` Plugins).

### Hiding Bundled Skills (2.1.169+)

The `disableBundledSkills` setting and the `CLAUDE_CODE_DISABLE_BUNDLED_SKILLS` environment variable hide **bundled** skills, workflows, and built-in slash commands from the model. Use it to slim the model's tool surface to only project/plugin/user skills — e.g. when a curated plugin set should fully replace the built-ins, or to cut per-turn context cost. It hides the built-ins only; your own skills are unaffected.

### SlashCommand Tool Invocation

Commands can invoke other commands programmatically:

```markdown
## Execution

First, run the setup command:
Use SlashCommand tool to invoke `/configure:pre-commit`

Then proceed with...
```

This enables composable command workflows.

## Skill File Structure

Skills live in `<plugin-name>/skills/<skill-name>/SKILL.md` (or `skill.md`).

### Root-Level `SKILL.md` Layout (2.1.142+)

A plugin with a root-level `SKILL.md` and **no** `skills/` subdirectory is surfaced as a single skill. The plugin itself **is** the skill — useful for tiny single-purpose plugins where the directory overhead is noise:

```
my-singleton-plugin/
├── .claude-plugin/
│   └── plugin.json
├── SKILL.md          # The plugin's one skill
└── README.md
```

Prefer the standard `skills/<skill-name>/SKILL.md` layout when the plugin will grow to multiple skills, or when scripts/assets need to live next to a specific skill. The root-level layout has no advantage once a `skills/` subdirectory exists.

### Required YAML Frontmatter

```yaml
---
name: <Skill Name>        # Optional: uses directory name if omitted
description: <1-2 sentence description of capability>
allowed-tools: <Comma-separated list of tools>
created: YYYY-MM-DD
modified: YYYY-MM-DD
reviewed: YYYY-MM-DD
---
```

> **Note**: `name` is optional — if omitted, the directory name is used. `description` is strongly recommended so Claude knows when to load the skill.

### Optional Frontmatter Fields

```yaml
---
# ... required fields above ...
language: <python|typescript|go|rust|etc>  # Specify primary language (optional)
agent: <agent-name>                         # Specify custom agent to execute skill (optional)
disallowed-tools: <Comma-separated list>    # Remove tools while skill is active (optional, 2.1.152+)
disable-model-invocation: true              # Skill content is the complete prompt (optional)
hooks:                                       # Skill-scoped hooks (optional)
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: "bash ${CLAUDE_PLUGIN_ROOT}/hooks/validate.sh"
          timeout: 10
---
```

- **`language`**: Specify the primary programming language for the skill. Helps Claude Code select appropriate models/tools.
- **`agent`**: Specify a custom agent for executing this skill. Overrides default model selection.
- **`disallowed-tools`** (2.1.152+): Comma-separated list of tools to remove from the model while this skill is active. Complements `allowed-tools` (which grants tools) by subtracting tools — useful for keeping a focused skill from reaching for capabilities it shouldn't use. Also supported on slash commands.
- **`disable-model-invocation`**: When `true`, the skill content is used as the complete prompt without additional model reasoning. The skill body is passed directly to the model as instructions.
- **`hooks`**: Define hooks that are only active when this skill is loaded. Uses the same schema as settings.json hooks. Agent `Stop` hooks are converted to `SubagentStop` when the agent runs as a subagent.

> **Note**: The `description` field must be a string type. Multi-line YAML strings using `|` or `>` are supported. Non-string values cause a crash (fixed in 2.1.51).

### String Substitutions

Skills support these dynamic variables in content:

| Variable | Description |
|----------|-------------|
| `$ARGUMENTS` | All arguments passed at invocation; appended as `ARGUMENTS: <value>` if not in content |
| `$ARGUMENTS[N]` | 0-based indexed argument (e.g., `$ARGUMENTS[0]` for first arg) |
| `$N` | Shorthand for `$ARGUMENTS[N]` (e.g., `$0` first, `$1` second) |
| `${CLAUDE_SESSION_ID}` | Current session ID — useful for logging and session-specific files |
| `${CLAUDE_SKILL_DIR}` | Directory containing the skill's `SKILL.md` file — use for bundled scripts |
| `${CLAUDE_EFFORT}` | Current effort level (`low`, `medium`, `high`, `max`) — use for effort-aware behavior |
| `${CLAUDE_PLUGIN_ROOT}` | Root of the loaded plugin (hooks only) |

**Examples:**

```markdown
## Execution

Fix GitHub issue $ARGUMENTS.

Migrate the $ARGUMENTS[0] component from $ARGUMENTS[1] to $ARGUMENTS[2].

Log to logs/${CLAUDE_SESSION_ID}.log.

Run helper: !`bash ${CLAUDE_SKILL_DIR}/scripts/helper.sh`
```

> **Escaping a literal `$` (2.1.163+)**: a `$` immediately before a digit is treated as a positional substitution (`$0`, `$1`, …). To emit a **literal** `$` before a digit in a skill/command body, escape it as `\$` — e.g. write `\$5.00` to render `$5.00` instead of substituting argument 5. Only `$` followed by a digit needs escaping; a `$` before a letter or space is left alone.

### Model Selection

Skills inherit the user's active model by default. Tag a skill with `model:` only at the **extremes** where the case for overriding inheritance is clear:

| Tag | Use for | Examples |
|-----|---------|----------|
| `model: opus` | Deep reasoning, multi-file orchestration, security review, architecture, long agentic chains | Skills that spawn many subagents, security audits, complex refactors, ADR/PRD synthesis |
| `model: sonnet` | Mechanical / high-volume work that **Sonnet at low effort** can genuinely complete | CLI tool wrappers (fd, rg, jq), formatters, status checks, single-file lookups |
| _(unset)_ | Everything in the middle | Default — inherits the user's active model |

**Why both extremes?** A user defaulting to Opus saves cost when a *genuinely* mechanical skill self-selects Sonnet. A user defaulting to Sonnet (or Haiku) gets reliable results when a complex skill self-selects Opus.

**Opus is often the cheaper default — `effort`, not `model`, is the main cost lever.** The per-token premium (Opus 4.8 output ≈ 1.7× Sonnet 4.6) is frequently outweighed by token *volume*: Opus at low effort tends to spend far fewer thinking + output tokens than Sonnet at high effort, so for reasoning-shaped work Opus-low can be both better *and* cheaper. The catch for this repo: that win rides on `effort`, which is a session/harness setting (e.g. Claude Code's default), **not** something a skill can express in frontmatter. So the practical translation is narrow — **don't reflexively reach for `model: sonnet`.** Tag it only when Sonnet at low effort genuinely suffices; when the task leans on reasoning, leave `model:` unset (or tag `opus`) and let the user's effort setting do the cost tuning. Treat the "Opus-low beats Sonnet-high" heuristic as workload-dependent, not dogma — confirm per-skill with the cross-model delta harness in [`.claude/rules/skill-evaluation.md`](skill-evaluation.md).

**Hard constraints:**

- **Do NOT use `model: haiku`.** Haiku 4.5 does not reliably format `AskUserQuestion` tool calls (fixed-forward in the lint check `check_skill_frontmatter()`), and the cost savings vs Sonnet are modest for the quality risk. Treat Sonnet as the floor.
- **Do NOT tag the middle.** If you can't articulate why the skill needs Opus or why Sonnet is enough, leave `model:` unset and let inheritance decide.
- The `model:` field is also supported in agent definitions (see `.claude/rules/agent-development.md`).

### Date Fields

| Field | Purpose | When to Update |
|-------|---------|----------------|
| `created` | Initial creation date | Set once at creation |
| `modified` | Last substantive change | Content updates (not typo fixes) |
| `reviewed` | Last verified current | After checking against latest docs |

**Review triggers**: Tool major version releases, Claude Code updates, quarterly audits.

### Common Tool Sets

| Skill Type | Typical Tools |
|------------|---------------|
| CLI tool | `Bash, Read, Grep, Glob, TodoWrite` |
| Development | `Bash, BashOutput, Read, Write, Edit, Grep, Glob, TodoWrite` |
| Research | `Read, WebFetch, WebSearch, Grep, Glob` |

### Permission Patterns

When listing `Bash` in `allowed-tools`, prefer narrow `Bash(<command> *)` permission rules in the project's `.claude/settings.json` over broad wildcards:

- Narrow rules survive the transition into auto mode and skip the auto-classifier round-trip on each call.
- Broad rules (`Bash(*)`, `Bash(python*)`) are dropped at runtime when auto mode is active.

`Skill(<name> *)` permission rules also work as a **prefix match** (2.1.139+) — fixed to match `Bash(ls *)` behavior. `Skill(git-*)` matches `git-commit`, `git-rebase`, etc.; `Skill(*)` matches every skill. Before 2.1.139, wildcards in `Skill(...)` were treated as literals and silently failed to match.

As of 2.1.147, auto mode no longer suppresses `AskUserQuestion` when a user or skill explicitly relies on it — a skill built around an `AskUserQuestion` prompt keeps working under auto mode.

See `.claude/rules/agentic-permissions.md` for canonical patterns and `.claude/rules/auto-mode.md` for the full auto-mode model.

## Content Structure

Follow this structure for consistency:

```markdown
# <Skill Name>

## Core Expertise
- Why this tool matters
- Key advantages over alternatives
- Performance characteristics

## Essential Commands
- Most common operations with examples
- Group by workflow (install, run, test, build)

## Advanced Features
- Lesser-known but useful flags
- Complex patterns

## Common Patterns
- Real-world usage examples
- Integration with other tools

## Agentic Optimizations
| Context | Command |
|---------|---------|
- Table of optimized commands for AI workflows

## Quick Reference
| Flag | Description |
|------|-------------|
- Compact reference table of key flags

## Error Handling (optional)
- Common issues and solutions
```

## Naming Conventions

| Pattern | Example |
|---------|---------|
| Tool-focused | `fd-file-finding`, `rg-code-search` |
| Workflow-focused | `bun-development`, `bun-package-manager` |
| Framework-focused | `biome-tooling`, `typescript-strict` |

## Skill Granularity

Choose granularity based on:

| Factor | Single Skill | Multiple Skills |
|--------|--------------|-----------------|
| Related operations | Yes | No |
| Shared context | Yes | No |
| Independent workflows | No | Yes |
| Different user intents | No | Yes |

**Rule of thumb**: If operations are typically used together, keep them in one skill.

## User-Invocable Skills

Skills that accept arguments use the same frontmatter as other skills, with additional fields:

```yaml
---
name: <skill-name>
description: <What it does, with trigger phrases>
args: <argument specification>
allowed-tools: <Comma-separated list>
argument-hint: <Human-readable hint>
created: YYYY-MM-DD
modified: YYYY-MM-DD
reviewed: YYYY-MM-DD
language: <optional-language>     # Specify primary language (optional)
agent: <optional-agent>           # Specify custom agent (optional)
---
```

User-invocable skills typically follow this content structure:

```markdown
# /<skill-name>

<Brief description>

## Context
- Environment detection commands (backticks for execution)

## Parameters
- Detailed parameter descriptions

## Execution
- Command templates with conditional logic

## Post-actions
- Follow-up steps after execution
```

## Plugin Metadata

Update `.claude-plugin/plugin.json` when adding skills:
- Add relevant keywords
- Update description if scope changes

Update `README.md`:
- Add skill to skills table
- Add usage examples for new commands

## Related Rules

For creating agents (rather than skills), see `.claude/rules/agent-development.md`.

## Git Workflow

All commits and PR titles **must** follow conventional commit format. See `.claude/rules/conventional-commits.md` for the full standard.

Use the plugin name as the scope:

```bash
git commit -m "feat(git-plugin): add commit workflow skill"
git commit -m "fix(configure-plugin): correct frontmatter extraction"
git commit -m "docs(blueprint-plugin): update skill README"
```

| Type | When to Use |
|------|-------------|
| `feat` | New skill or meaningful new capability |
| `fix` | Correcting broken skill behaviour |
| `docs` | README, CHANGELOG, or inline documentation only |
| `refactor` | Restructuring a skill without behaviour change |
| `chore` | Metadata updates (plugin.json, marketplace.json) |

PR titles must also follow this format — they become the squash-merge commit message that drives release-please version bumps.


