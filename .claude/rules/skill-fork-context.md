---
paths:
  - "**/skills/**"
  - "**/SKILL.md"
  - "**/agents/**"
---

# Skill Fork Context

When to set `context: fork` and `agent:` in skill frontmatter.

## Current Status: Do NOT Use `context: fork` in Plugin Skills

**As of March 2026, `context: fork` has two blocking issues for plugin-based skills:**

1. **Broken for plugins** ([anthropics/claude-code#16803](https://github.com/anthropics/claude-code/issues/16803), OPEN) — `context: fork` is silently ignored for plugin-installed skills. It only works for skills in the user's `~/.claude/` folder.

2. **Triggers rate limits with 1M context models** ([#27053](https://github.com/anthropics/claude-code/issues/27053), [#33154](https://github.com/anthropics/claude-code/issues/33154)) — Forking from an Opus 4.6 (1M) session spawns a second concurrent `[1m]` request, immediately hitting rate limits (`total_tokens: 0` rejection). This affects the default recommended model.

**Use `agent: general-purpose` without `context: fork`** to get subagent isolation without triggering these issues.

> **Follow-up issue**: Track upstream fixes at [#PENDING](https://github.com/laurigates/claude-plugins/issues) — revisit when #16803 and #33154 are resolved.

## What These Fields Do

| Field | Value | Effect |
|-------|-------|--------|
| `context: fork` | `fork` | **BROKEN for plugins.** Intended to run the skill in an isolated subagent context. |
| `agent` | subagent type name | Which subagent type to launch. Use `general-purpose` for most skills. Works without `context: fork`. |

## Recommended Pattern

```yaml
---
name: my-skill
model: opus
agent: general-purpose
allowed-tools: Task, Read, Glob, Grep, TodoWrite
description: ...
---
```

Use `agent: general-purpose` for skills that need subagent isolation. Omit `context: fork` until upstream issues are resolved.

## Model Constraint for Interactive Skills

Skills that use `AskUserQuestion` **must not** set `model: haiku`. The haiku model does not reliably format `AskUserQuestion` tool calls, causing prompts to return empty responses without displaying to the user. Use `model: sonnet` or `model: opus`.

## Decision Table

```
Does the skill use AskUserQuestion?
  YES → Do NOT set agent: (runs inline), do NOT use model: haiku
  NO ↓

Does the skill spawn Task subagents OR read many files OR do multiple web fetches?
  NO  → No agent needed (runs inline)
  YES ↓

Is the final output a self-contained artifact (report, analysis, generated files)?
  NO  → No agent needed (user needs to follow along)
  YES → ADD agent: general-purpose (do NOT add context: fork)
```

## Checklist for New Skills

- [ ] Does the skill use `AskUserQuestion`? If yes, **omit** `agent:` and **do not** set `model: haiku`.
- [ ] Does the skill use `Task`, multi-file reads, or web research? If yes, **add** `agent: general-purpose`.
- [ ] **Do NOT** add `context: fork` — it is broken for plugin skills and triggers rate limits.
- [ ] Update `modified:` date when adding these fields.

## Upstream Issues to Track

| Issue | Status | Impact |
|-------|--------|--------|
| [#16803](https://github.com/anthropics/claude-code/issues/16803) | OPEN | `context: fork` silently ignored for plugin skills |
| [#33154](https://github.com/anthropics/claude-code/issues/33154) | OPEN | `[1m]` models hit cascading rate limits with concurrent subagents |
| [#27053](https://github.com/anthropics/claude-code/issues/27053) | NOT_PLANNED | Subagents return rate limit with 0 tokens |
| [#6594](https://github.com/anthropics/claude-code/issues/6594) | NOT_PLANNED | One rate-limited subagent kills all parallel siblings |

## Related Rules

- `.claude/rules/agent-development.md` — full agent lifecycle and `context: fork` semantics
- `.claude/rules/skill-development.md` — skill creation patterns and optional frontmatter fields
- `.claude/rules/skill-quality.md` — quality checklist for skill PRs
