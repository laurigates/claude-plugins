---
paths:
  - "**/skills/**"
  - "**/SKILL.md"
  - "**/agents/**"
reviewed: 2026-07-04
modified: 2026-07-04
---

# Skill Fork Context

When to set `context: fork` and `agent:` in skill frontmatter.

## Current Status: `context: fork` Rollout Complete

**As of July 2026, the hard blocker is resolved and the rollout to single-subagent skills is complete** (tracked in [laurigates/claude-plugins#980](https://github.com/laurigates/claude-plugins/issues/980), [#1667](https://github.com/laurigates/claude-plugins/issues/1667)):

1. **Plugin support fixed** ([anthropics/claude-code#16803](https://github.com/anthropics/claude-code/issues/16803), **CLOSED — COMPLETED 2026-04-18**) — `context: fork` is now honoured for plugin-installed skills. Previously it was silently ignored outside the user's `~/.claude/` folder; that was the real blocker, and it is gone.

2. **The `[1m]` rate-limit concern is narrower than first feared** ([#33154](https://github.com/anthropics/claude-code/issues/33154) **CLOSED — not planned / stale**, [#27053](https://github.com/anthropics/claude-code/issues/27053) stale-closed) — #33154 was a **Claude Cowork (Desktop) product** regression (`area:cowork`), never a CLI-specific tracker, and it was abandoned as stale rather than fixed. The underlying hazard — a `[1m]`-context session spawning **many concurrent** subagents and hitting cascading rate limits — is real but bites **parallel fan-out**, not a single fork. One `context: fork` spawns **one** subagent, which is not the cascade scenario.

**Guidance:** `context: fork` is appropriate for a **single-subagent, verbose-output** skill. Keep avoiding it on skills that fan out **parallel** subagents while on a `[1m]` model (see the `skill-argument-handling.md` sweep caveat). The blocking gate in #980 ("revisit when both #16803 and #33154 resolved") expired — #33154 will never resolve cleanly — so the rollout was **empirical**: a canary was verified live, then the remaining single-subagent skills followed.

> **Canary passed → rolled out**: `code-quality-plugin/skills/code-review` carried `context: fork` as the first restoration (canary PR #1666, merged 2026-06-15). It ran live and un-reverted for ~3 weeks with no rate-limit regression reported — treated as PASSED on that evidence (a true `[1m]`-session verification can't be run from inside a subagent, so "no rollback over weeks of live use" is the standing signal, not a one-off `[1m]` test). Under #1667 the restoration then rolled out to the remaining **single-subagent** skills: `agents-plugin:agents-analyze`, `testing-plugin:test-analyze`, `testing-plugin:test-full`, `documentation-plugin:claude-blog-sources`, `documentation-plugin:docs-generate`, `evaluate-plugin:evaluate-skill`, `code-quality-plugin:dry-consolidation`.
>
> **Held OFF (parallel fan-out — the `[1m]` cascade hazard):** `git-plugin:git-pr-feedback` and `evaluate-plugin:evaluate-plugin-batch` fan out parallel subagents and keep `context: fork` **off**. `code-quality-plugin:code-antipatterns` was skipped for the same reason — its execution strategy is a **mandatory** parallel agent delegation ("Launch multiple specialized agents simultaneously"), not the optional Agent-Teams escape hatch that `test-full` / `docs-generate` / `code-review` carry. The optional **Agent Teams** path in the forked skills still fans out parallel subagents — use that path cautiously on `[1m]`.

## What These Fields Do

| Field | Value | Effect |
|-------|-------|--------|
| `context: fork` | `fork` | Runs the skill in an isolated forked context — its verbose output never reaches the main window. Works for plugin skills again (#16803 fixed). Safe for single-subagent skills; avoid pairing with parallel fan-out on `[1m]`. |
| `agent` | subagent type name | Which subagent type to launch. Use `general-purpose` for most skills. Works with or without `context: fork`. |

## Recommended Pattern

For a **verbose, single-subagent** skill whose output should stay out of the main context:

```yaml
---
name: my-skill
model: opus
agent: general-purpose
context: fork
allowed-tools: Task, Read, Glob, Grep, TodoWrite
description: ...
---
```

For a skill that fans out **parallel** subagents while a `[1m]` model is active, keep `agent: general-purpose` and **omit** `context: fork` — the rate-limit cascade hazard applies to concurrent subagents, not to the single fork.

## Model Constraint

`model: haiku` is disallowed for any skill — see `.claude/rules/skill-development.md` ("Model Selection"). Sonnet is the floor; set `model: opus` or `model: sonnet` only at the extremes, otherwise leave `model:` unset to inherit.

## Decision Table

```
Does the skill use AskUserQuestion?
  YES → Do NOT set agent: (runs inline)
  NO ↓

Does the skill spawn Task subagents OR read many files OR do multiple web fetches?
  NO  → No agent needed (runs inline)
  YES ↓

Is the final output a self-contained artifact (report, analysis, generated files)?
  NO  → No agent needed (user needs to follow along)
  YES ↓

Does the skill fan out PARALLEL subagents (batch/per-PR/per-file waves)?
  YES → ADD agent: general-purpose; OMIT context: fork ([1m] cascade hazard)
  NO  → ADD agent: general-purpose AND context: fork (verbose output stays isolated)
```

## Checklist for New Skills

- [ ] Does the skill use `AskUserQuestion`? If yes, **omit** `agent:` (runs inline).
- [ ] Does the skill use `Task`, multi-file reads, or web research? If yes, **add** `agent: general-purpose`.
- [ ] Does the skill produce a self-contained verbose artifact **without** parallel fan-out? If yes, **add** `context: fork` (now works for plugins per #16803).
- [ ] Does the skill fan out **parallel** subagents? If yes, **omit** `context: fork` — the `[1m]` concurrent-subagent rate-limit cascade still applies.
- [ ] Set `model:` only at the extremes (`opus` for deep reasoning, `sonnet` for mechanical work). Never `haiku`.
- [ ] Update `modified:` date when adding these fields.

## Upstream Issues to Track

| Issue | Status (2026-06-15) | Impact |
|-------|--------|--------|
| [#16803](https://github.com/anthropics/claude-code/issues/16803) | **CLOSED — COMPLETED** | `context: fork` now honoured for plugin skills (was the hard blocker) |
| [#33154](https://github.com/anthropics/claude-code/issues/33154) | **CLOSED — not planned / stale** | Cowork (Desktop) `[1m]` rate-limit regression; abandoned, never a CLI tracker |
| [#27053](https://github.com/anthropics/claude-code/issues/27053) | CLOSED — stale | Subagents return rate limit with 0 tokens (parallel fan-out) |
| [#6594](https://github.com/anthropics/claude-code/issues/6594) | CLOSED — stale | One rate-limited subagent kills all parallel siblings |

The remaining `[1m]` cascade hazard (#33154/#27053/#6594) is empirical platform behaviour that bites **parallel** subagents; it has no clean upstream "resolved" signal and will not get one. Treat it as a constraint on parallel fan-out, not on a single fork.

## Related Rules

- `.claude/rules/agent-development.md` — full agent lifecycle and `context: fork` semantics
- `.claude/rules/skill-development.md` — skill creation patterns and optional frontmatter fields
- `.claude/rules/skill-quality.md` — quality checklist for skill PRs
