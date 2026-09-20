---
created: 2026-02-27
modified: 2026-09-20
reviewed: 2026-09-16
paths:
  - "**/skills/**"
  - "**/SKILL.md"
  - "**/agents/**"
---

# Skill Fork Context

When to set `context: fork` and `agent:` in skill frontmatter.

## Current Status: `context: fork` Rollout Complete

**As of July 2026, the hard blocker is resolved and the rollout to single-subagent skills is complete** (tracked in [laurigates/claude-plugins#980](https://github.com/laurigates/claude-plugins/issues/980), [#1667](https://github.com/laurigates/claude-plugins/issues/1667)):

1. **Plugin support fixed** ([anthropics/claude-code#16803](https://github.com/anthropics/claude-code/issues/16803), **CLOSED — COMPLETED 2026-04-18**) — `context: fork` is now honoured for plugin-installed skills. Previously it was silently ignored outside the user's `~/.claude/` folder; that was the real blocker, and it is gone.

2. **The `[1m]` rate-limit concern is narrower than first feared** ([#33154](https://github.com/anthropics/claude-code/issues/33154) **CLOSED — not planned / stale**, [#27053](https://github.com/anthropics/claude-code/issues/27053) stale-closed) — #33154 was a **Claude Cowork (Desktop) product** regression (`area:cowork`), never a CLI-specific tracker, and it was abandoned as stale rather than fixed. The underlying hazard — a `[1m]`-context session spawning **many concurrent** subagents and hitting cascading rate limits — is real but bites **parallel fan-out**, not a single fork. One `context: fork` spawns **one** subagent, which is not the cascade scenario.

**Guidance:** `context: fork` is appropriate for a **single-subagent, verbose-output** skill, and — since 2026-09-20 — for a skill whose parallel fan-out is **statically bounded** (below). Keep avoiding it on skills that fan out subagents at an **unbounded or caller-chosen** width on a 1M-context session — which is every Fable 5.1 session (1M is its default and only window) as well as any other model opened with the `[1m]` suffix (see the `skill-argument-handling.md` sweep caveat). The cascade was measured on `[1m]` sessions of earlier models; re-verify on Fable before relaxing it. The blocking gate in #980 ("revisit when both #16803 and #33154 resolved") expired — #33154 will never resolve cleanly — so the rollout was **empirical**: a canary was verified live, then the remaining single-subagent skills followed.

**The bounded-width carve-out (2026-09-20).** What the cascade bites is *unbounded* concurrency, not concurrency as such. A fan-out whose width is **statically bounded** — a fixed table of agent types, a cap constant the script refuses to exceed, or a set a shell script enumerates before dispatch — is compatible with `context: fork`, because the ceiling is decidable before a single subagent is spawned and cannot grow with the input. What stays **off** `fork` is the width the *caller or the model* picks: a `--parallel N` flag, "one agent per PR the query happens to return", or a count a design invents. A skill relying on this carve-out must say **where its bound lives** — in its `## Workflow harness (template)` framing if it ships one — so the claim is checkable rather than asserted.

This is a **correction as much as an enabling edit**: `testing-plugin:test-analyze` has been CI-pinned to `context: fork` *and* shipping an 8-wide `parallel()` harness since the dynamic-workflow migration, capped at the fixed agent-type set precisely so it would not become a wide fan-out. The rule classified it as single-subagent and offered no carve-out, so it had already fallen out of date with a shipped harness. `evaluate-plugin:evaluate-skill` is the second instance, bounded by its `cellCap` ceiling (which aborts rather than truncating).

> **Canary passed → rolled out**: `code-quality-plugin/skills/code-review` carried `context: fork` as the first restoration (canary PR #1666, merged 2026-06-15). It ran live and un-reverted for ~3 weeks with no rate-limit regression reported — treated as PASSED on that evidence (a true `[1m]`-session verification can't be run from inside a subagent, so "no rollback over weeks of live use" is the standing signal, not a one-off `[1m]` test). Under #1667 the restoration then rolled out to the remaining **single-subagent** skills: `agents-plugin:agents-analyze`, `testing-plugin:test-analyze`, `testing-plugin:test-full`, `documentation-plugin:claude-blog-sources`, `documentation-plugin:docs-generate`, `evaluate-plugin:evaluate-skill`, `code-quality-plugin:dry-consolidation`. Two of those have since gained a **statically bounded** harness and keep `fork` under the carve-out above rather than as single-subagent skills: `test-analyze` (8 agent types) and `evaluate-skill` (`cellCap`).
>
> **Held OFF (UNBOUNDED / caller-chosen fan-out — the `[1m]` cascade hazard):** `git-plugin:git-pr-feedback` fans out one agent per PR its query returns, and `evaluate-plugin:evaluate-plugin-batch` fans out at a width the caller picks with `--parallel N`. Neither width is decidable before dispatch, so both keep `context: fork` **off** — note the reason is the *unbounded* width, not that they fan out at all. `code-quality-plugin:code-antipatterns` was skipped for the same reason — its execution strategy is a **mandatory** parallel agent delegation ("Launch multiple specialized agents simultaneously"), not the optional Agent-Teams escape hatch that `test-full` / `docs-generate` / `code-review` carry. The optional **Agent Teams** path in the forked skills still fans out parallel subagents — use that path cautiously on `[1m]`.

## What These Fields Do

| Field | Value | Effect |
|-------|-------|--------|
| `context: fork` | `fork` | Runs the skill in an isolated forked context — its verbose output never reaches the main window. Works for plugin skills again (#16803 fixed). Safe for single-subagent skills, and for a parallel fan-out whose width is statically bounded; avoid pairing with an **unbounded or caller-chosen** fan-out on `[1m]`. **Runs as a background task by default (2.1.218)** — the invoking session is not blocked; pass `background: false` in the skill's own frontmatter to force synchronous execution. |
| `agent` | subagent type name | Which subagent type to launch. Use `general-purpose` for most skills. Works with or without `context: fork`. |

## Recommended Pattern

For a **verbose, single-subagent** skill whose output should stay out of the main context:

```yaml
---
name: my-skill
model: opus
agent: general-purpose
context: fork
allowed-tools: Agent, Read, Glob, Grep
description: ...
---
```

For a skill that fans out **parallel** subagents at an **unbounded or caller-chosen** width on a 1M-context session (every Fable 5.1 session, or any other model opened with `[1m]`), keep `agent: general-purpose` and **omit** `context: fork` — the rate-limit cascade hazard applies to a concurrency ceiling nobody can name, not to the single fork. If the width *is* statically bounded, keep `context: fork` and name the bound (see the carve-out above).

By default a forked skill now runs in the background (2.1.218) — the caller gets a completion notification rather than a blocking result. Add `background: false` to the frontmatter block above when the skill's result is needed synchronously (e.g. the caller's next step consumes its output immediately). This is a **skill-frontmatter** default, distinct from the `Agent`-tool-level background-by-default behavior for non-teammate spawns (`.claude/rules/agent-development.md` § Background Execution) — don't conflate the two: a `context: fork` skill backgrounds itself regardless of how the `Agent` tool it uses internally would otherwise default.

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
  NO  → ADD agent: general-purpose AND context: fork (verbose output stays isolated)
  YES ↓

Is that fan-out's width STATICALLY BOUNDED before dispatch — a fixed table, a
script-decidable cap constant, or a set a shell script enumerates?
  YES → ADD agent: general-purpose AND context: fork; name the bound in the skill
        (e.g. test-analyze's 8 agent types, evaluate-skill's cellCap)
  NO  → ADD agent: general-purpose; OMIT context: fork (unbounded or caller-chosen
        width — 1M-context cascade hazard, every Fable 5.1 session or any [1m] session)
```

## Checklist for New Skills

- [ ] Does the skill use `AskUserQuestion`? If yes, **omit** `agent:` (runs inline).
- [ ] Does the skill use `Task`, multi-file reads, or web research? If yes, **add** `agent: general-purpose`.
- [ ] Does the skill produce a self-contained verbose artifact **without** parallel fan-out? If yes, **add** `context: fork` (now works for plugins per #16803). Remember it now runs in the background by default (2.1.218) — add `background: false` if the caller needs the result synchronously.
- [ ] Does the skill fan out **parallel** subagents at an **unbounded or caller-chosen** width (`--parallel N`, one agent per query hit, a count the design invents)? If yes, **omit** `context: fork` — the concurrent-subagent rate-limit cascade still applies on a 1M-context session (every Fable 5.1 session, or any `[1m]` session). A **statically bounded** fan-out keeps `fork`; name the bound where a reader can check it.
- [ ] Set `model:` only at the extremes (`opus` for deep reasoning, `sonnet` for mechanical work). Never `haiku`.
- [ ] Update `modified:` date when adding these fields.

## Upstream Issues to Track

| Issue | Status (2026-06-15) | Impact |
|-------|--------|--------|
| [#16803](https://github.com/anthropics/claude-code/issues/16803) | **CLOSED — COMPLETED** | `context: fork` now honoured for plugin skills (was the hard blocker) |
| [#33154](https://github.com/anthropics/claude-code/issues/33154) | **CLOSED — not planned / stale** | Cowork (Desktop) `[1m]` rate-limit regression; abandoned, never a CLI tracker |
| [#27053](https://github.com/anthropics/claude-code/issues/27053) | CLOSED — stale | Subagents return rate limit with 0 tokens (parallel fan-out) |
| [#6594](https://github.com/anthropics/claude-code/issues/6594) | CLOSED — stale | One rate-limited subagent kills all parallel siblings |

The remaining `[1m]` cascade hazard (#33154/#27053/#6594) is empirical platform behaviour that bites **parallel** subagents; it has no clean upstream "resolved" signal and will not get one. Treat it as a constraint on **unbounded** parallel fan-out — not on a single fork, and not on a fan-out with a ceiling decidable before dispatch.

## Related Rules

- `.claude/rules/agent-development.md` — full agent lifecycle and `context: fork` semantics
- `.claude/rules/skill-development.md` — skill creation patterns and optional frontmatter fields
- `.claude/rules/skill-quality.md` — quality checklist for skill PRs
