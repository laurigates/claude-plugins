---
created: 2026-03-02
modified: 2026-05-03
reviewed: 2026-05-03
paths:
  - "**/skills/**"
  - "**/SKILL.md"
---

# Skill Quality Standards

Quality standards for maintaining effective, discoverable skills.

## Size Limits

| File | Max Lines | Action if Exceeded |
|------|-----------|-------------------|
| `SKILL.md` | 500 | Extract to `REFERENCE.md` |
| `REFERENCE.md` | No limit | Supporting file, loaded on demand |

**Official guideline**: Keep `SKILL.md` under 500 lines. Move detailed reference material to separate supporting files.

## Required Sections

Every skill MUST have:

### 1. "When to Use" Decision Table

Place immediately after the title. Helps Claude decide when to load the skill vs alternatives.

```markdown
## When to Use This Skill

| Use this skill when... | Use X instead when... |
|------------------------|----------------------|
| Specific scenario A | Alternative scenario |
| Specific scenario B | Alternative scenario |
```

### 2. Agentic Optimizations Table

Place near the end. Provides compact commands optimized for AI workflows.

```markdown
## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick check | `tool --compact-flag` |
| CI mode | `tool --reporter=json` |
| Errors only | `tool --errors-only` |
```

### 3. Supporting File Link (if REFERENCE.md exists)

Use proper markdown link format so Claude knows what the file contains:

```markdown
For detailed X, Y, and Z patterns, see [REFERENCE.md](REFERENCE.md).
```

## Writing Style

Use **positive guidance** - describe what to do, not what to avoid. This reinforces correct patterns instead of drawing attention to incorrect ones.

| Instead of | Write |
|------------|-------|
| "Do not use broad permissions" | "Use granular permissions" |
| "Avoid ls with globs" | "Use find for file discovery" |
| "Never edit CHANGELOG manually" | "Use conventional commits to update changelog" |

## Description Quality

Descriptions must match real user intents. They are loaded into Claude's context for skill selection.

**Tool-centric** (less effective):
```yaml
description: AST-based code search using ast-grep for structural pattern matching
```

**Intent-matching** (effective):
```yaml
description: |
  Find and replace code patterns structurally using ast-grep. Use when you need
  to match code by its AST structure, such as finding all functions with specific
  signatures, replacing API patterns across files, or detecting code anti-patterns.
```

### Description Checklist
- [ ] Describes what the user can accomplish (not just the tool name)
- [ ] Includes "Use when..." clause with specific scenarios
- [ ] Mentions common trigger phrases users would say
- [ ] Distinguishes from related skills
- [ ] Is a string type (non-string values cause a crash)

### `disable-model-invocation` Field

Set `disable-model-invocation: true` when the skill body is a complete, self-contained prompt that should be passed directly without additional model reasoning. Useful for skills that are fully deterministic templates.

## Model Selection

Skills inherit the user's active model by default. Set `model:` only at the **extremes** — see `.claude/rules/skill-development.md` for the full rationale.

| Model | Use For |
|-------|---------|
| `opus` | Deep reasoning, architecture decisions, debugging methodology, security analysis, complex code review, long agentic orchestration |
| `sonnet` | Mechanical / high-volume tasks where Opus is overkill — CLI tool wrappers, formatters, status checks, single-file lookups |
| _(unset)_ | Everything in the middle — let the user's active model decide |

**Sonnet is the floor.** `model: haiku` is disallowed: Haiku 4.5 does not reliably format `AskUserQuestion` tool calls and the cost savings vs Sonnet are modest for the quality risk. The lint check in `plugin-compliance-check.sh` errors on `model: haiku`.

## Supporting Files Pattern

```
my-skill/
├── SKILL.md           # Core instructions (<500 lines)
├── REFERENCE.md       # Detailed reference (loaded on demand)
├── examples.md        # Usage examples (optional)
└── scripts/           # Helper scripts (optional)
```

### What Goes Where

| In SKILL.md (always loaded) | In REFERENCE.md (on demand) |
|-----------------------------|----------------------------|
| Installation / setup | Full configuration options |
| 5-10 most common commands | All flags and options |
| "When to Use" decision guide | Migration guides |
| Quick reference table | Advanced patterns |
| Agentic Optimizations | Editor integrations (non-primary) |
| CI integration basics | Build system integrations |

## Quality Checklist for PRs

When reviewing skill/command changes:

- [ ] SKILL.md is under 500 lines
- [ ] Has "When to Use" decision table
- [ ] Has "Agentic Optimizations" table (for CLI/tool skills)
- [ ] Description matches user intents (not just tool jargon)
- [ ] Model selection follows extremes-only rule (`opus` for deep reasoning, `sonnet` for mechanical tasks, unset otherwise; never `haiku`)
- [ ] Reference material extracted to REFERENCE.md if needed
- [ ] Supporting files referenced with markdown links
- [ ] No duplicate content with sibling skills
- [ ] Frontmatter has all required fields (name, description, allowed-tools)
- [ ] Date fields updated (modified, reviewed)
- [ ] User-invocable skills follow execution structure (see `.claude/rules/skill-execution-structure.md`)
- [ ] PR title follows conventional commit format: `type(scope): subject` (see `.claude/rules/conventional-commits.md`)
- [ ] Commit messages follow conventional commit format with plugin name as scope (e.g., `feat(git-plugin): ...`)
