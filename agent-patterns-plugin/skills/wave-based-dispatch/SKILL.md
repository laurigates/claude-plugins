---
name: wave-based-dispatch
description: |
  Sequential-wave counterpart to parallel-agent-dispatch for work-order chains
  that cannot fan out at once — when one WO's output (a new file, type, or API)
  is the next WO's input, when candidate agents share an exclusive lock (Ghidra
  project, taskwarrior bulk modify, single-writer caches), or when the
  orchestrator itself is the contention point because it edits the same shared
  files between waves. Use when planning a multi-WO landing whose pieces
  depend on each other, when deciding whether a research probe should be its
  own wave before downstream WOs are written, or when a previous parallel
  dispatch surfaced ordering or last-writer-wins problems. Complements
  parallel-agent-dispatch (intra-wave contract), exclusive-lock-dispatch
  (pre-dump mechanics), and workflow-orchestration-plugin:workflow-wave-dispatch
  (the workflow-side scheduling view).
user-invocable: false
allowed-tools: Read, Glob, Grep, TodoWrite
model: opus
created: 2026-04-25
modified: 2026-05-04
reviewed: 2026-04-25
---

# Wave-Based Dispatch

The agent-side dispatch discipline for sequential WO chains. Same pillars as
`parallel-agent-dispatch` — disjoint ownership, return contracts, shared-file
exclusion — but the gates **between** waves are different from the gates
**inside** a wave. This skill is those between-wave gates.

## When to Use This Skill

| Use wave-based dispatch when… | Use `parallel-agent-dispatch` alone when… | Use `exclusive-lock-dispatch` when… |
|-------------------------------|-------------------------------------------|--------------------------------------|
| A later WO needs a file, type, or API the earlier WO defines | All WOs operate on disjoint, lock-free scopes | One tool holds an exclusive lock and N agents need its outputs |
| A research probe (Ghidra decomp, spec experiment, API trace) gates downstream scope | Scope is fully known up front | Lock-holder is slow enough to amortise via pre-dump |
| Two candidate agents would both modify the same shared manifest / tracker / build file | Shared-file exclusion list is small and stable | Pre-computed artefacts can replace re-running the lock holder |
| A bug surfaced during orchestrator-apply needs the same context as the dispatched agent | Issues are recoverable inside a single wave | Lock contention is the only sequencing reason |

The three skills compose: each wave is itself a `parallel-agent-dispatch`,
lock-holding waves use `exclusive-lock-dispatch` for the pre-dump, and
this skill covers the boundary between waves.

## Picking Wave-Based Over Parallel

| Trigger | Why parallel fails | Wave-based response |
|---------|---------------------|---------------------|
| **Dependency chain** — WO-B imports types from WO-A | WO-B's brief is stale before WO-A lands; the agent guesses or stalls | WO-A in wave 1, WO-B in wave 2 referencing WO-A's landed paths |
| **Shared lock** — Ghidra project, taskwarrior bulk modify, single-writer cache | Second concurrent invocation fails with a lock error; orchestrator burns a turn diagnosing | Lock holder runs alone in its wave; downstream waves read pre-dumped artefacts |
| **Orchestrator-edit contention** — multiple agents return verbatim patches against the same `CMakeLists.txt` / `justfile` / manifest | Last-writer-wins silently loses the earlier edit; merge conflicts pile up at apply time | Stage edits to those files between waves so the orchestrator applies them serially |

If any trigger matches, the work belongs in waves. Inside each wave,
`parallel-agent-dispatch` still applies as the per-agent contract.

## The Research-Before-WO Gate

When the scope of a downstream WO depends on information that only a tool
run can produce — Ghidra decomp, a live API trace, the actual structure
of a binary format, a benchmark — run that probe as **its own first wave**
before the implementation WO is written.

The reason is concrete: the implementation WO's *size* collapses once
the probe lands. A WO scoped as "unknown — possibly days, depends on the
binary's actual layout" turns into "plumb a known pointer from offset
0x40 to the existing decoder, hours" once the research wave produces a
spec artefact. Writing the brief before the research lands locks in the
worst-case framing and the agent burns its window re-deriving the
information.

Process:

1. Wave 1 brief asks the probe agent to write findings to gitignored
   scratch (`tmp/research/format-spec.md`, `tmp/decomp/strings.txt`,
   `tmp/api/probe-results.json`).
2. Probe agent returns a Return Contract that lists the artefact paths.
3. Implementation WO is written **after** wave 1 closes, citing those
   paths verbatim and forbidding re-running the probe.
4. If the artefacts are insufficient, the implementation agent returns
   `partial` with the missing question in `Orchestrator action needed`,
   and the orchestrator dispatches a follow-up probe wave rather than
   letting the implementation agent improvise.

See `agent-patterns-plugin:exclusive-lock-dispatch` when the probe tool
holds an exclusive lock — the pre-dump mechanics there are the right
shape for the research wave's brief.

## Six-Gate Verification Table Between Waves

No brief for wave N+1 is written until wave N's gates pass. The gate set
is fixed — drifting the gates between waves is how regressions slip in.

| # | Gate | Signal | Why it matters between waves |
|---|------|--------|------------------------------|
| 1 | Build | Project compile / typecheck recipe succeeds | Wave N+1 will import wave N's symbols; broken build poisons the next brief |
| 2 | Tests | Project test recipe succeeds (with the wave's flag set when applicable) | Hidden regressions compound across waves |
| 3 | Module smoke | Module-level smoke recipes (CLI subcommand smoke, `tools-plugin:cli-smoke-recipes`) pass | Catches integration breaks the unit tests miss |
| 4 | Taskwarrior status | Tasks for the wave drain to `done`; no orphans | Wave N's queue must be empty before wave N+1's tasks are filed |
| 5 | Feature-tracker drain | Tracker entries touched by the wave advance from `in progress` to `done`, with evidence pointers | Sidecar status survives the session; the next wave can cite landed work |
| 6 | Clean tree | `git status --porcelain` empty | Loose ends become invisible work after the next wave lands on top |

A gate failure rolls back to **fix in place, retry the gate** — never to
"dispatch wave N+1 and paper over it." If the wave is unrecoverable,
revert it and re-brief.

## The ~10-Line Inline-Fix Threshold

When a wave returns and a small bug surfaces during the orchestrator's
apply step, the orchestrator has a choice: fix it inline, or file a
follow-up WO for the next wave. The threshold is approximate but
load-bearing:

| Situation | Decision |
|-----------|----------|
| ~10 lines of fix, orchestrator already has the symbolic context | Fix inline |
| Fix spans multiple files or needs the agent's exploration log | Follow-up WO in the next wave |
| Fix is mechanical (rename, reformat, missing import) | Fix inline |
| Fix requires a design judgement | Follow-up WO — judgement is cheaper to revisit than re-inject |

The deciding question is: "Will the orchestrator spend less time fixing
in place than re-writing a brief and re-loading the agent's context?"
Below ~10 lines, usually yes. A concrete signal that the threshold was
right: a bug that was a missing branch in `--no-present` mode landed as
a one-edit orchestrator fix instead of a whole re-dispatch turn.

This is **not** an excuse to skip waves entirely — it is a release
valve for the small issues that always surface at apply time. Use it
sparingly; once the inline fix exceeds ~10 lines, file the WO.

## Stable Shared-File Exclusion List Across Waves

`parallel-agent-dispatch` §Shared-File Exclusion List defines the
orchestrator-only files that no agent may touch (manifest, tracker,
top-level plan, build manifests, justfile, task store). That list is
**derived once in the wave-1 brief** and referenced by name in every
subsequent wave's brief. Do not re-derive it.

Re-deriving the list per wave drifts it — wave 2 forgets the
`Cargo.toml` entry that wave 1 had, wave 3 forgets the tracker, and on
the Nth wave a silent manifest clobber lands. The discipline is:

- **Wave 1 brief** spells out the full exclusion list under
  `### Orchestrator-only files`.
- **Wave N+1 brief** says, verbatim:

  > "Orchestrator-only files: as defined in the wave-1 brief. No
  > additions, no removals. If you believe a new file belongs on the
  > list, return `partial` and surface it in `Orchestrator action
  > needed` — do not edit it."

The same discipline applies to pre-allocated blueprint IDs, ADR
numbers, and any monotonic counters (`parallel-agent-dispatch`
§Pre-Allocated Blueprint IDs). Allocate up front; reference by ID in
later waves.

## Composition

| Layer | Skill | Concern |
|-------|-------|---------|
| Per-agent brief inside a wave | `agent-patterns-plugin:parallel-agent-dispatch` | Worktree preflight, scope budget, Return Contract, shared-file exclusion |
| Lock-holding waves | `agent-patterns-plugin:exclusive-lock-dispatch` | Pre-dump mechanics so downstream waves read artefacts, not the lock |
| Wave scheduling and gate failures | `workflow-orchestration-plugin:workflow-wave-dispatch` | Workflow-side view: which waves exist, what to do when a gate fails |
| Where wave candidates come from | `taskwarrior-plugin:task-coordinate` | Surfaces unblocked tasks while skipping lock-contenders |

This skill is the dispatch-time discipline that ties them together —
the agent-pattern view of why the chain is sequential and what the
between-wave gates buy you.

## Quick Reference

### Orchestrator Checklist

- [ ] Trigger identified (dependency chain / shared lock / orchestrator-edit contention)
- [ ] Research probe scheduled as wave 1 if any downstream scope is unknown
- [ ] Six-gate verification table applied at every wave boundary
- [ ] Shared-file exclusion list cited in wave 1, referenced by name in waves 2..N
- [ ] Return Contract referenced from `parallel-agent-dispatch`, never redefined
- [ ] Inline-fix threshold (~10 lines) honoured at wave-end
- [ ] No brief for wave N+1 written until wave N's gates pass

### Common Mistakes

| Mistake | Correct Approach |
|---------|-----------------|
| Writing the implementation brief before the research probe lands | Research wave first; implementation brief cites the artefact paths |
| Skipping a gate "because nothing changed" | All six gates run at every boundary; cheap gates are cheap on purpose |
| Re-deriving the exclusion list per wave | Cite once in wave 1; reference by name in waves 2..N |
| Filing every small issue as a follow-up WO | Inline-fix when ≤ ~10 lines and the orchestrator has the context |
| Treating a gate failure as "dispatch the next wave to fix it" | Fix in place and retry the gate; revert and re-brief if unrecoverable |

## Related

- `agent-patterns-plugin:parallel-agent-dispatch` — intra-wave contract; the §Worktree Preflight, §Scope Budget, §Return Contract, and §Shared-File Exclusion List sections apply unchanged inside every wave
- `agent-patterns-plugin:exclusive-lock-dispatch` — pre-dump mechanics for lock-contending waves; this skill cites it as the right shape for the research wave's brief
- `workflow-orchestration-plugin:workflow-wave-dispatch` — workflow-side scheduling view: enumerating waves, gate-failure rollback, scheduling heuristics
- `taskwarrior-plugin:task-coordinate` — where wave candidates come from: surfaces the next N unblocked tasks while excluding lock-contenders
- `.claude/rules/parallel-safe-queries.md` — empty-result exit codes that bite inside automated gate checks

> Evidence: porting the 158-line `wave-based-dispatch` project rule
> (skullcaps-native, 2026-04-24) into a reusable skill. The rule
> earned promotion after a six-wave dependent landing shipped in one
> day with zero merge conflicts, one inline fix, and zero
> exclusion-list drift across waves.
