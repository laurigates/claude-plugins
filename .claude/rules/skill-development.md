---
created: 2025-12-20
modified: 2026-03-09
reviewed: 2026-03-09
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
| `${CLAUDE_PLUGIN_ROOT}` | Root of the loaded plugin (hooks only) |

**Examples:**

```markdown
## Execution

Fix GitHub issue $ARGUMENTS.

Migrate the $ARGUMENTS[0] component from $ARGUMENTS[1] to $ARGUMENTS[2].

Log to logs/${CLAUDE_SESSION_ID}.log.

Run helper: !`bash ${CLAUDE_SKILL_DIR}/scripts/helper.sh`
```

### Model Selection

Skills inherit the user's active model by default. Do not set `model:` in skill frontmatter — this avoids forcing a specific model variant that may differ from the user's preferred model or require a tier they don't have access to.

> **Note**: The `model:` field is still supported in agent definitions (see `.claude/rules/agent-development.md`) where explicit model selection may be appropriate.

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
