---
name: workflow-wave-dispatch
description: |
  Sequential-wave dispatch contract for multi-agent work where tasks have
  internal dependencies — when a later work-order needs a file, type, or
  API defined by an earlier one; when a research question gates downstream
  scope; or when lock-contenders force serialisation. Companion to
  parallel-agent-dispatch (which assumes disjoint scopes). Use when
  planning a multi-step implementation, when a previous parallel dispatch
  hit ordering problems, or when deciding whether to re-dispatch a wave
  after a verification gate fails.
user-invocable: false
allowed-tools: Read, Glob, Grep, TodoWrite
created: 2026-04-24
modified: 2026-04-24
reviewed: 2026-04-24
---

# Workflow Wave Dispatch

Sequential waves, not parallel fan-out, when the work has real
dependencies. Each wave runs to completion and passes a verification
gate before the next wave is briefed.

## When to Use This Skill

| Use wave-based dispatch when… | Use `parallel-agent-dispatch` alone when… |
|-------------------------------|-------------------------------------------|
| A later WO needs a file/type/API that an earlier WO defines | All WOs operate on disjoint file scopes with no shared definitions |
| Research (decompile, spec probe, API experiment) gates downstream scope | Scope is fully known before dispatch |
| Two candidates contend on an exclusive lock | No candidate touches a locked resource |
| Shared-file edits would pile up if many agents ran in one batch | Orchestrator-only files are small, few, and well-understood |
| Gate failure must block downstream work | Failure in one slab does not imply re-work in siblings |

`parallel-agent-dispatch` is the right call inside a wave. Waves are the
layer above it — they answer "which agents run together" before
`parallel-agent-dispatch` answers "how each agent is briefed."

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
do when a gate fails.

## Research-Before-WO Gate

If the scope of a later work-order depends on information only a tool run
can produce — decompilation output, a live API's actual behaviour, the
real structure of a binary format, a spec experiment — run the research
as its **own wave first**.

- Research wave writes findings to gitignored scratch (`tmp/research/…`,
  `tmp/decomp/…`).
- Implementation wave is briefed **after** research returns, citing the
  artefacts that now exist.
- Do **not** bundle "decompile X, then implement Y" into one brief — the
  implementation brief is stale before the research lands, and the agent
  will either waste its window re-deriving the research or ship against
  incorrect assumptions.

Briefs for the implementation wave reference artefact paths:

> "Inputs: `tmp/research/format-spec.md`, `tmp/decomp/strings.txt`. Do not
> re-run the decompiler. If the artefacts are insufficient, return a
> `partial` status with the missing question in `Orchestrator action
> needed`."

See `agent-patterns-plugin:exclusive-lock-dispatch` for the pre-dump
mechanics when the research tool holds an exclusive lock.

## Verification Gates Between Waves

Every wave ends with a gate. No brief for wave N+1 is written before
wave N's gate passes. Typical gates, in rough order of cost:

| Gate | Signal |
|------|--------|
| Clean tree | `git status --porcelain` empty |
| Build green | Project's compile / typecheck recipe succeeds |
| Tests green | Project's test recipe succeeds |
| Smoke recipes | Bulk-smoke recipes (see `tools-plugin:cli-smoke-recipes`) pass |
| Task-queue state | Pending tasks for the wave drain to `done` |
| Tracker drain | Feature tracker entries touched by the wave advance from `in progress` to `done` |
| Docs currency | Same-commit docs updates present for any API / format / spec change |

A gate failure **rolls back to "fix in place, retry the gate"** — never
to "dispatch wave N+1 and paper over the failure." If the wave as a whole
is un-recoverable, revert it and re-brief.

## Inline Fix vs Re-Dispatch

When a wave returns with small issues, the orchestrator has a choice:

| Situation | Decision |
|-----------|----------|
| ~10 lines of fix, orchestrator has the symbolic context in its head | Fix inline |
| Fix spans multiple files or needs the same exploration the agent did | File a follow-up WO, dispatch in the next wave |
| Fix is mechanical (rename, move, format) | Fix inline |
| Fix requires judgement about a design trade-off | Follow-up WO — judgement is cheaper to revisit than re-inject |

The threshold is approximate. The deciding question is "will the
orchestrator spend less time fixing in place than re-writing a brief and
re-loading the agent's context?" Below ~10 lines, usually yes.

## Return Contract Reuse

Do **not** redefine the Return Contract per wave. Every agent in every
wave uses the schema from
`agent-patterns-plugin:parallel-agent-dispatch` §Return Contract verbatim.
Redefining it per wave drifts the schema and breaks the orchestrator's
parse step.

Reference in the brief:

> "Return contract: follow
> `agent-patterns-plugin:parallel-agent-dispatch` §Return Contract
> verbatim. Do not paraphrase."

## Stable Exclusion List Across Waves

The shared-file exclusion list (see
`parallel-agent-dispatch` §Shared-File Exclusion List) is **cited once in
the first wave's brief** and referenced by name in every subsequent
wave's brief. Re-deriving the list per wave drifts it and produces
silent manifest clobbers on the Nth wave.

Example wave-N brief fragment:

> "Orchestrator-only files: as in the wave-1 brief. No changes."

## Scheduling Heuristics

- Put the **lock-holder** (Ghidra, migration, bulk taskwarrior) alone in
  its wave. See `exclusive-lock-dispatch`.
- Put the **research wave** before any implementation wave that depends
  on its artefacts.
- Put **foundation** (new types, new APIs, new files that others will
  import) in the earliest implementation wave.
- Put **extensions** (new call sites, new tests, new docs) in later
  waves.
- Inside a single wave, fan out to the widest safe parallelism that
  `parallel-agent-dispatch` allows.

## Quick Reference

### Orchestrator Checklist

- [ ] Waves enumerated with explicit dependencies identified
- [ ] Research wave scheduled first if any scope depends on tool output
- [ ] Gate defined for every wave boundary
- [ ] Shared-file exclusion list cited in wave-1 brief, referenced later
- [ ] Return Contract referenced from `parallel-agent-dispatch`, never redefined
- [ ] Inline-fix threshold decided at wave-end, not mid-wave
- [ ] No brief for wave N+1 written until wave N's gate passes

### Common Mistakes

| Mistake | Correct Approach |
|---------|-----------------|
| Bundling "decompile X, then implement Y" in one brief | Split into research wave + implementation wave |
| Dispatching wave N+1 after a gate failure to "patch over it" | Fix in place, retry the gate |
| Redefining the Return Contract per wave | Reference `parallel-agent-dispatch` §Return Contract verbatim |
| Re-deriving the exclusion list per wave | Cite once in wave 1, reference by name in later waves |
| Treating every small issue as a follow-up WO | Inline fixes under ~10 lines when the orchestrator has context |

## Related

- `agent-patterns-plugin:parallel-agent-dispatch` — intra-wave dispatch contract
- `agent-patterns-plugin:exclusive-lock-dispatch` — pre-dump pattern for lock-contending waves
- `agent-patterns-plugin:agent-teams` — TeamCreate mechanics that waves sit on top of
- `tools-plugin:cli-smoke-recipes` — smoke-gate mechanics between waves
- `.claude/rules/parallel-safe-queries.md` — empty-result exit codes inside gates

> Evidence: a six-wave landing shipped six dependent work-orders in one
> day with zero merge conflicts and exactly one inline fix. Earlier
> attempts without wave discipline produced two-day cycles dominated by
> re-work when later WOs broke earlier interfaces.
