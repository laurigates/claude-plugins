---
paths:
  - "**/skills/**"
  - "**/SKILL.md"
  - "**/agents/**"
---

# Skill Fork Context

When to set `context: fork` and `agent:` in skill frontmatter so verbose, autonomous skills protect the main context window.

## What These Fields Do

| Field | Value | Effect |
|-------|-------|--------|
| `context: fork` | `fork` | Runs the skill in an isolated subagent context. The subagent sees parent history but its intermediate output does not accumulate in the parent session. |
| `agent` | subagent type name | Which subagent type to launch when `context: fork` is set. Use `general-purpose` for most skills. |

## When to Use `context: fork`

A skill benefits from forked context when **all three** of the following are true:

1. **Verbose intermediate output** — the skill reads many files, makes multiple web requests, spawns subagents via `Task`, or otherwise generates large amounts of intermediate context that would pollute the parent session.
2. **Self-contained result** — the skill produces a final artifact (report, file, analysis) and hands it back cleanly; it does not need to leave its intermediate steps visible in the conversation.
3. **No interactive prompts** — the skill does not use `AskUserQuestion`. Forked subagents run autonomously and cannot relay interactive prompts back to the user.

## When NOT to Use `context: fork`

| Signal | Reason to skip fork |
|--------|---------------------|
| Skill uses `AskUserQuestion` | Interactive prompts cannot reach the user through a forked subagent |
| Skill is a quick diagnostic or status check | Overhead exceeds benefit; user wants to see output inline |
| User needs to review intermediate steps | Fork hides the working — use main context instead |
| Skill is already invoked inside a Task | Already isolated; double-forking adds no value |

## Decision Table

```
Does the skill use AskUserQuestion?
  YES → Do NOT fork
  NO ↓

Does the skill spawn Task subagents OR read many files OR do multiple web fetches?
  NO  → Do NOT fork (not verbose enough to matter)
  YES ↓

Is the final output a self-contained artifact (report, analysis, generated files)?
  NO  → Do NOT fork (user needs to follow along)
  YES → ADD context: fork + agent: general-purpose
```

## Frontmatter Pattern

```yaml
---
name: my-skill
model: sonnet
context: fork
agent: general-purpose
allowed-tools: Task, Read, Glob, Grep, TodoWrite
description: ...
---
```

## Canonical Examples

### Fork — appropriate

```yaml
# Orchestrates multiple Task subagents, produces verbose review report
context: fork
agent: general-purpose
allowed-tools: Task, TodoWrite, Glob, Read
```

```yaml
# Reads hundreds of files, produces analysis artifact
context: fork
agent: general-purpose
allowed-tools: Glob, Grep, Read, Bash(ls *), Bash(wc *), TodoWrite
```

```yaml
# Web research pipeline, compiles curated output
context: fork
agent: general-purpose
allowed-tools: WebFetch, WebSearch, Task
```

### Fork — not appropriate

```yaml
# Asks the user questions mid-workflow — cannot fork
allowed-tools: Read, Write, Glob, AskUserQuestion
# context: fork omitted
```

```yaml
# Quick test run — user wants live output
allowed-tools: Bash(bun test *), TodoWrite
# context: fork omitted
```

## Checklist for New Skills

- [ ] Does the skill use `AskUserQuestion`? If yes, **omit** `context: fork`.
- [ ] Does the skill use `Task`, multi-file reads, or web research? If yes, **add** `context: fork`.
- [ ] Is the output a self-contained artifact? If yes, confirm `context: fork` is appropriate.
- [ ] Set `agent: general-purpose` whenever `context: fork` is set (unless a specialised agent exists).
- [ ] Update `modified:` date when adding these fields.

## Related Rules

- `.claude/rules/agent-development.md` — full agent lifecycle and `context: fork` semantics
- `.claude/rules/skill-development.md` — skill creation patterns and optional frontmatter fields
- `.claude/rules/skill-quality.md` — quality checklist for skill PRs
