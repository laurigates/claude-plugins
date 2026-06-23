---
name: workflow-wave-dispatch
description: Sequential-wave dispatch for multi-agent work with cross-task dependencies. Use when planning multi-step work, fixing parallel-dispatch order, or gating waves on verification.
user-invocable: false
allowed-tools: Read, Glob, Grep, TodoWrite
created: 2026-04-24
modified: 2026-06-23
reviewed: 2026-06-23
---

# Workflow Wave Dispatch

Sequential waves, not parallel fan-out, when the work has real
dependencies. This skill is the **workflow-side scheduling view**: which
waves exist, what order they run in, and what to do when a gate fails.

The **dispatch discipline** — the per-wave gate set, the research-before-WO
gate, the ~10-line inline-fix threshold, the stable shared-file exclusion
list, and Return Contract reuse — lives in
`agent-patterns-plugin:wave-based-dispatch`. This skill does not restate it;
it schedules around it.

## When to Use This Skill

| Use this skill when… | Use the alternative when… |
|----------------------|---------------------------|
| Enumerating the waves and their ordering for a dependent landing | You need the per-wave gate set / dispatch discipline — use `agent-patterns-plugin:wave-based-dispatch` |
| Deciding what to do when a wave's gate fails | Briefing the agents *inside* a wave — use `agent-patterns-plugin:parallel-agent-dispatch` |
| Scheduling a research probe ahead of the implementation waves it unblocks | A tool holds an exclusive lock and the wave must pre-dump it — use `agent-patterns-plugin:exclusive-lock-dispatch` |

`parallel-agent-dispatch` is the right call inside a wave. Waves are the
layer above it — they answer "which agents run together, in what order"
before `parallel-agent-dispatch` answers "how each agent is briefed."

## Wave Structure

```
Wave 1 (research)
  └── Single agent or small fan-out → artefacts in tmp/
      └── Gate: artefacts exist, agent returned a clean contract

Wave 2 (foundation)
  └── Parallel fan-out against wave-1 artefacts
      └── Gate: build green, tests green, tracker advanced

Wave 3 (extension)
  └── Parallel fan-out referencing wave-2 types/APIs
      └── Gate: smoke recipes pass, clean tree

Wave N …
```

Each wave is itself a `parallel-agent-dispatch` call. This skill covers
wave **scheduling**: which waves exist, what gates between them, what to
do when a gate fails. The gate *set* itself is the six-gate table in
`agent-patterns-plugin:wave-based-dispatch` § Six-Gate Verification Table.

## Scheduling Heuristics

- Put the **lock-holder** (Ghidra, migration, bulk taskwarrior) alone in
  its wave. See `agent-patterns-plugin:exclusive-lock-dispatch`.
- Put the **research wave** before any implementation wave that depends
  on its artefacts (the research-before-WO gate in
  `agent-patterns-plugin:wave-based-dispatch` explains why the downstream
  WO's *size* collapses once the probe lands).
- Put **foundation** (new types, new APIs, new files that others will
  import) in the earliest implementation wave.
- Put **extensions** (new call sites, new tests, new docs) in later
  waves.
- Inside a single wave, fan out to the widest safe parallelism that
  `parallel-agent-dispatch` allows.

## Schema-Constrained Agents Under Rate-Limit Storms

Schema-constrained `agent()` calls — agents bound to a `StructuredOutput`
schema — are **fragile under rate-limit storms** (issue
[#1463](https://github.com/laurigates/claude-plugins/issues/1463)). A
rate-limit hit that occurs *before* the agent emits its `StructuredOutput`
is reported as a hard parse failure: the caller receives no partial output
and the agent's work is unrecoverable from the schema path, even when
substantial work was done inside the agent's context window.

**Why this matters at the wave layer.** A wide wave of schema-bound agents
(e.g. 8–10 concurrent structured-output extractors) creates a rate-limit
storm risk. If the storm wipes half the wave, the gate fails and the
orchestrator has no partial results to salvage — unlike a plain `agent()`
call where the worktree holds the work.

**Blast-radius containment** — apply at wave-scheduling time:

| Heuristic | Guidance |
|-----------|----------|
| Wave size | Cap schema-bound waves at **≤ 5 concurrent agents** (same cap as `parallel-agent-dispatch` for Opus 4.7 parents) |
| Stagger | Add **~30 s between launches** in the same wave to spread the token-request window |
| Wave splits | If the fan-out genuinely needs >5 schema-bound calls, dispatch in sequential sub-waves of ≤ 5 — gate each sub-wave before launching the next |
| Retry shape | On a rate-limit partial failure, recovery-dispatch only the failed agents (not the whole wave) — the successful siblings' outputs are valid |

For concurrency caps, wave-splitting mechanics, and the recovery-dispatch
routine for rate-limited agents, see
`agent-patterns-plugin:parallel-agent-dispatch` § Concurrent rate-limit
risk and
[REFERENCE.md → Concurrent rate-limit recovery](../../agent-patterns-plugin/skills/parallel-agent-dispatch/REFERENCE.md).
Do not duplicate that guidance here.

## Gate Failure: Roll Back, Don't Paper Over

Every wave ends with a gate (the six-gate set lives in
`agent-patterns-plugin:wave-based-dispatch`). No brief for wave N+1 is
written before wave N's gate passes.

A gate failure **rolls back to "fix in place, retry the gate"** — never
to "dispatch wave N+1 and paper over the failure." If the wave as a whole
is un-recoverable, revert it and re-brief.

Whether a returned issue is fixed inline or filed as a follow-up WO for
the next wave is the ~10-line inline-fix threshold — see
`agent-patterns-plugin:wave-based-dispatch` § The ~10-Line Inline-Fix
Threshold.

## Shared Mechanics (owned by `wave-based-dispatch`)

These are defined once in `agent-patterns-plugin:wave-based-dispatch` and
referenced — never restated — when scheduling waves:

| Mechanic | Where |
|----------|-------|
| Per-wave gate set | § Six-Gate Verification Table |
| Research-before-WO gate | § The Research-Before-WO Gate |
| Inline-fix vs follow-up WO | § The ~10-Line Inline-Fix Threshold |
| Stable shared-file exclusion list across waves | § Stable Shared-File Exclusion List |
| Return Contract reuse | `parallel-agent-dispatch` § Return Contract |

## Quick Reference

### Orchestrator Checklist (scheduling)

- [ ] Waves enumerated with explicit dependencies identified
- [ ] Research wave scheduled first if any scope depends on tool output
- [ ] Lock-holder isolated in its own wave
- [ ] Foundation scheduled before extensions
- [ ] A gate defined for every wave boundary (set per `wave-based-dispatch`)
- [ ] No brief for wave N+1 written until wave N's gate passes
- [ ] Gate failure → fix in place and retry, never dispatch-over

### Common Scheduling Mistakes

| Mistake | Correct Approach |
|---------|-----------------|
| Bundling "decompile X, then implement Y" in one wave | Split into a research wave + an implementation wave |
| Dispatching wave N+1 after a gate failure to "patch over it" | Fix in place, retry the gate; revert and re-brief if unrecoverable |
| Scheduling extensions before the foundation they import | Foundation in the earliest implementation wave, extensions later |
| Running the lock-holder concurrently with its consumers | Lock-holder alone in its wave; downstream reads pre-dumped artefacts |

## Related

- `agent-patterns-plugin:wave-based-dispatch` — the dispatch discipline and the shared between-wave gate set this skill schedules around
- `agent-patterns-plugin:parallel-agent-dispatch` — intra-wave dispatch contract
- `agent-patterns-plugin:exclusive-lock-dispatch` — pre-dump pattern for lock-contending waves
- `agent-patterns-plugin:agent-teams` — implicit-team / SendMessage mechanics that waves sit on top of
- `tools-plugin:cli-smoke-recipes` — smoke-gate mechanics between waves
- `.claude/rules/parallel-safe-queries.md` — empty-result exit codes inside gates

> Evidence: a six-wave landing shipped six dependent work-orders in one
> day with zero merge conflicts and exactly one inline fix. Earlier
> attempts without wave discipline produced two-day cycles dominated by
> re-work when later WOs broke earlier interfaces.
