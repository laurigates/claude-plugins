---
created: 2025-12-20
modified: 2026-02-20
reviewed: 2026-01-22
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
model: <opus|sonnet|haiku>
name: <Skill Name>
description: <1-2 sentence description of capability>
allowed-tools: <Comma-separated list of tools>
created: YYYY-MM-DD
modified: YYYY-MM-DD
reviewed: YYYY-MM-DD
---
```

### Model Selection

Choose the appropriate model based on task complexity:

| Model | Use For |
|-------|---------|
| `opus` | Deep reasoning, architecture decisions, debugging methodology, security analysis, complex code review |
| `sonnet` | Development workflows requiring judgment, code generation with analysis, framework expertise, multi-step pattern-based reasoning |
| `haiku` | Simple CLI operations, formatting, configuration, status checks, standard mechanical workflows |

**Guidelines:**
- Default to `sonnet` for tasks requiring moderate reasoning or development expertise
- Use `haiku` for straightforward, mechanical tasks (CLI tools, formatting, status checks)
- Use `opus` only when the skill requires deep reasoning, security analysis, or complex decision-making
- Consider: "Does this need deep reasoning (opus), moderate judgment (sonnet), or mechanical execution (haiku)?"

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
model: <opus|sonnet|haiku>
name: <skill-name>
description: <What it does, with trigger phrases>
args: <argument specification>
allowed-tools: <Comma-separated list>
argument-hint: <Human-readable hint>
created: YYYY-MM-DD
modified: YYYY-MM-DD
reviewed: YYYY-MM-DD
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
