---
created: 2025-12-20
modified: 2026-01-22
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

Skills live in `plugins/<plugin-name>/skills/<skill-name>/skill.md`.

### Required YAML Frontmatter

```yaml
---
model: <opus|haiku>
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
| `opus` | Complex reasoning, architecture, code review, debugging methodology, security analysis, advanced testing theory |
| `haiku` | Simple CLI operations, formatting, configuration, status checks, standard workflows |

**Guidelines:**
- Default to `haiku` for straightforward, mechanical tasks
- Use `opus` when the skill requires planning, analysis, or complex decision-making
- Consider: "Does this need deep reasoning or pattern matching?"

### Date Fields

| Field | Purpose | When to Update |
|-------|---------|----------------|
| `created` | Initial creation date | Set once, never change |
| `modified` | Last substantive change | Content updates, not typo fixes |
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

## Command File Structure

Commands live in `plugins/<plugin-name>/commands/<command-name>.md` or nested in subdirectories.

### Required YAML Frontmatter

```yaml
---
model: <opus|haiku>
description: <What the command does>
args: <argument specification>
allowed-tools: <Comma-separated list>
argument-hint: <Human-readable hint>
created: YYYY-MM-DD
modified: YYYY-MM-DD
reviewed: YYYY-MM-DD
---
```

The `model` field uses the same selection criteria as skills (see Model Selection above).

### Content Structure

```markdown
# /<command-name>

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
