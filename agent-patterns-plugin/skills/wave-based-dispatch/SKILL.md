---
name: wave-based-dispatch
description: Sequential-wave dispatch for WO chains where output of one feeds the next, shared locks, or shared files prevent fan-out. Use when planning dependent multi-WO landings.
user-invocable: false
allowed-tools: Read, Glob, Grep, TodoWrite
model: opus
created: 2026-04-25
modified: 2026-10-07
compatibility: claude-code
reviewed: 2026-06-06
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

When a downstream WO's scope depends on a tool run (decomp, API trace, format probe, benchmark), that probe is its own first wave. Procedure: [references/first-wave-gates.md](references/first-wave-gates.md).

## The Pilot-Before-Fan-Out Gate

When the same transformation will be applied to N items, wave 1 is one pilot that proves the recipe and its riskiest unknown; wave 2 mirrors it. Procedure: [references/first-wave-gates.md](references/first-wave-gates.md).

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

### Gating on a green PR vs a landed merge

When a human merges each wave and wave N+1 cannot wait for the merge, see [references/stacked-wave-prs.md](references/stacked-wave-prs.md) for how Gate 6 and stacked-PR landing change.

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

Each wave is a `parallel-agent-dispatch`; lock-holding waves use `exclusive-lock-dispatch`. The full layer map is in [references/plan-review.md](references/plan-review.md).

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

See [references/plan-review.md](references/plan-review.md) when reviewing a wave plan.

## Related

- `agent-patterns-plugin:parallel-agent-dispatch` — intra-wave contract; the §Worktree Preflight, §Scope Budget, §Return Contract, and §Shared-File Exclusion List sections apply unchanged inside every wave
- `agent-patterns-plugin:exclusive-lock-dispatch` — pre-dump mechanics for lock-contending waves; this skill cites it as the right shape for the research wave's brief
- `workflow-orchestration-plugin:workflow-wave-dispatch` — workflow-side scheduling view: enumerating waves, gate-failure rollback, scheduling heuristics
- `git-plugin:git-pr` / `git-plugin:git-conflicts` — stacked-PR merge order (retarget children before deleting the base, `--onto` squash cleanup) and pre-merge trial integration for landing a wave's PRs
- `rust-plugin:cargo-worktree-builds` — when the waves are Rust worktrees, share one pre-warmed `CARGO_TARGET_DIR` so deps compile once across all worktrees
- `taskwarrior-plugin:task-coordinate` — where wave candidates come from: surfaces the next N unblocked tasks while excluding lock-contenders
- `.claude/rules/parallel-safe-queries.md` — empty-result exit codes that bite inside automated gate checks

> Evidence: porting the 158-line `wave-based-dispatch` project rule
> (skullcaps-native, 2026-04-24) into a reusable skill. The rule
> earned promotion after a six-wave dependent landing shipped in one
> day with zero merge conflicts, one inline fix, and zero
> exclusion-list drift across waves.
