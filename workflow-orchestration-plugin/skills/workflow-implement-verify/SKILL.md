---
name: workflow-implement-verify
description: Workflow templates that implement 2–5 units in worktrees with a fresh verifier and one repair round, or close findings on existing branches. Use when fanning out implementers or repairs.
user-invocable: false
allowed-tools: Bash(git *), Bash(gh *), Read, TodoWrite
model: opus
created: 2026-10-26
modified: 2026-10-26
reviewed: 2026-10-26
---

# Implement, Verify, Repair

Two `Workflow` templates for the most common multi-agent job: change code on
several branches at once, and do not trust any of it until an agent that did not
write it has checked it.

| Template | Input | Output |
|---|---|---|
| `implement-verify` | units of work (issues, tasks, work packages) | verified branches, opened as PRs |
| `repair-round` | existing branches plus the findings to close on each | verified repair commits, pushed to those branches |

Both share one Verify/Repair stage, byte-identical between the two files. A
`FIX_NEEDED` row from `implement-verify` is a valid `repair-round` unit
(`{ id, branch, findings: verdict.new_defects }`), so a second round is a second
run, not a bigger loop.

## Where these came from

They were distilled from 51 ad-hoc implement runs and 12 ad-hoc repair runs
written on the fly across 14 projects. Measured from the run records:

- 44 of the 51 implement runs added a fresh verifier per unit, and 11 ran a
  repair round in the same run. The existing `git-plugin:git-issue`
  `issue-group-wave` template has neither.
- 20 runs opened PRs from inside the parallel agents, against the
  push-only-in-finalise rule in `.claude/rules/workflow-vs-skill.md`.
- Three repair runs gated with `if (!v || v.approved)`. When the verifier died,
  that check skipped the repair and reported the unit as approved. Here a null
  verdict is `UNVERIFIED` and is never landed.
- Only 1 of the 51 used a grouping stage. Callers almost always knew their units,
  so `units` is the primary input.

## When to Use This Skill

| Use this skill when… | Use instead… |
|---|---|
| 2–5 units with known scope, each needing an independent check | One unit: implement it and dispatch one verifier by hand |
| Branches already exist and a verifier or review listed what to fix | Nobody has looked for the defects yet: `agent-patterns-plugin:adversarial-review` |
| Issues that may overlap and need partitioning first | `git-plugin:git-issue --parallel` (`issue-group-wave`), then this template per group set |
| Several waves that depend on each other's merged results | `workflow-wave-dispatch` schedules the waves; run this template once per wave with `base` set |
| Merging the resulting PRs | `git-plugin:git-merge-hazards` — neither template merges |

## Inputs

Shared `args` (both templates):

| Field | Meaning | Default |
|---|---|---|
| `repo` | `owner/name` | — |
| `root` | absolute path of the main checkout; agents never edit it | — |
| `base` | diff and branch base | `origin/main` |
| `gates` | commands every unit must pass | `[]` |
| `setup` | worktree bootstrap commands (`bun install --frozen-lockfile`, …) | `[]` |
| `skills`, `decisions`, `contract` | skills to name, user decisions to relay verbatim, a binding design doc path | — |
| `trailer` | lines every commit message must end with (session-specific, so the caller supplies it) | none |
| `repairRounds` | `1` or `0`. A second round is a separate `repair-round` run | `1` |
| `land` | `implement-verify`: `pr` or `local`; `repair-round`: `push` or `local` | `pr` / `push` |

`implement-verify` units: `{ id, issues: [n], branch, brief, owns: [globs], gates, tier: opus|sonnet|haiku, labels }`,
or `issues: [n, …]` as shorthand for one unit per issue. `pr: { assignee, labels, footer }` sets PR metadata.
A `sonnet` or `haiku` implementer is acceptable only because an opus verifier follows it.

`repair-round` units: `{ id, branch, base?, findings: [{ id?, severity, where?, text | problem, fix? }], brief?, gates? }`.

## Result rows

| Status | Meaning | Landed |
|---|---|---|
| `PASS` | verifier passed it first time | yes |
| `REPAIRED_PASS` | one repair, then a fresh re-verify passed it | yes |
| `FIX_NEEDED` | still failing after the allowed rounds; feed it to `repair-round` | no |
| `REJECTED` | verifier judged the approach wrong; a human decides | no |
| `UNVERIFIED` | the verifier returned nothing | no |
| `NO_CHANGE` | already correct at `base`, with evidence | no |
| `BLOCKED` / `FAILED` | the author could not proceed, or returned nothing | no |

Each row carries the author's report (`fix`, including `followups` and
`decisions_for_user`) and every verdict, so a re-dispatch starts from the state
packet rather than from memory (`.claude/rules/loop-integrity.md` Pillar 2).

## Workflow harness (template)

`workflows/implement-verify.workflow.js` and `workflows/repair-round.workflow.js` ship beside
this skill. **Each is a TEMPLATE to adapt, not a script to run verbatim.** Read it, then rewrite
it for the work in front of you.

**Adapt freely:** the agent prompts, the per-project gates and bootstrap, the implementer tier,
`MAX_UNITS` and `FLOOR`, and the PR metadata.

**Agent budget:** 1 + 4 x units — the finalise agent is counted; per unit, an author, a verifier, and on `fix-needed` a repairer and a re-verifier. At the cap of 5 units the worst case is 21.

**Preserve across any adaptation:** (a) the loop bound is the caller's `units`, cut by
`UNITS.slice(0, 5)` in the fan-out after an explicit over-cap abort, never a prose "for each" and
never a silent truncation; (b) the closed `pass | fix-needed | reject` verdict, with a null
verdict mapped to `UNVERIFIED` and never landed, and `reject` never auto-repaired; (c) the
verifier is a fresh agent working from refs, never the author; (d) the Verify/Repair region is
byte-identical in both files (`scripts/tests/test-templates.sh`); (e) Finalise is the only
barrier, because push order on one remote needs every unit's final verdict.

Never `Workflow({resumeFromRunId})` to retry a few failed worktree agents — a resume re-runs
agents that already succeeded and opens duplicate PRs (#1868). Re-dispatch the failed units fresh
and sequentially after checking `gh pr list --head <branch> --state all --json number,state`.

Push, PR creation, and GitHub mutations happen **only** in the single sequential finalise stage,
never inside a fanned-out agent.

**Skip the harness when:** there is one unit, or the work is a docs-only edit with no gate to
re-run. That is a linear pass, and the harness is pure overhead.

## Related

- `git-plugin:git-issue` — `issue-group-wave` partitions overlapping issues before this runs
- `workflow-wave-dispatch` — ordering several runs whose bases depend on earlier merges
- `agent-patterns-plugin:execution-grounded-review`, `agent-patterns-plugin:adversarial-review` — what the verifier prompt asks for
- `agent-patterns-plugin:parallel-agent-dispatch` — worktree hazards and the resume rule
- `workflow-scale-budget` — sizing a run before it starts
