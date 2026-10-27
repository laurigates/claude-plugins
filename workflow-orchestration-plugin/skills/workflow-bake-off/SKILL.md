---
name: workflow-bake-off
description: Workflow template for a bake-off — 2–5 independent attempts, lens judges, a winner computed by Borda or a metric rule, then refine. Use when comparing competing designs or running A/B arms.
user-invocable: false
allowed-tools: Bash, Read, TodoWrite
model: opus
created: 2026-10-27
modified: 2026-10-27
reviewed: 2026-10-27
---

# Bake-off: Compete, Judge, Refine

One `Workflow` template, `compete-and-judge`, for work where the right answer is
not known in advance: several independent attempts at the same target, judged
side by side, with the winner taken forward. A protocol for measured A/B
experiments follows in [Measured arms](#measured-arms); it is prose, not a
second template.

The template's one hard rule: **the winner is computed in JavaScript** from the
judges' rankings or measured numbers. No agent reads the verdicts and picks.
A model that picks from verdicts can only turn near-ties into a confident
answer: the coin-flip laundering that `.claude/rules/workflow-vs-skill.md`
§ The two shapes with no fit here warns about.

## Where this came from

It was distilled from 4 ad-hoc tournament runs across 4 projects, judged on
taste (a logo, game meshes, a UI design) or on a shared metric (a schematic
layout). They used 7–10 agents and 1.2–2.9 M tokens each.

- Three of the four let a model pick. Two had a synthesizer agent "start from
  the design the judges favour overall"; the third had its single metric judge
  apply the rule and name the winner itself.
- The fourth aggregated in JS (Borda, mean score as tiebreak) but had no quorum
  check: had every judge died, the all-zero tally would have sorted stably and
  the first entry would have been refined as "the winner". Here a panel short of quorum crowns nobody.
- Its Borda points also came from the length of each judge's list, so a judge
  who ranked only two entries gave less to its first place than a full ranker
  did. Here points come from the number of surviving entries, and each key
  counts once.

## When to Use This Skill

| Use this skill when… | Use instead… |
|---|---|
| 2–5 genuinely different approaches to one target, and judging needs the artefacts side by side | One approach: build it and review it (`agent-patterns-plugin:adversarial-review`) |
| The ranking is a judgement (taste, fitness) or a number a script measures | The ranking is already a deterministic score: sort it, no judges needed |
| Several units of known scope, each needing a fix and a check | `workflow-implement-verify` |
| Arms × seeds against a shared metric, with a human verdict at the end | [Measured arms](#measured-arms) |
| Comparing skills or prompts in this repo | `evaluate-plugin:evaluate-skill` |

## Inputs

| Field | Meaning | Default |
|---|---|---|
| `context` | the brief every entrant and judge sees, including hard requirements | — |
| `out` | absolute output directory; entry `k` writes only `${out}/${k}`, the refine writes `${out}/final` | — |
| `entries` | 2–5 `{ key, angle }`; order is the final tiebreak | — |
| `judges` | 1–3 `{ key, lens }` | — |
| `setup` | 0–2 `{ key, brief }` for what everyone must share (render harness, measurement script) | `[]` |
| `metric_defs`, `acceptance` | shared definitions and acceptance bullets | — |
| `aggregation` | `borda` or `metric` | `borda` |
| `metric` | `metric` mode: `{ command, keys: [{ name, better: lower\|higher }] }` | — |
| `self_iterate` | `{ min, max }` rounds per entrant | `{ 2, 6 }` |
| `finish` | `refine` or `none` | `refine` |
| `skills`, `decisions` | skills to name, user decisions to relay verbatim | — |

Keys must match `[A-Za-z0-9][A-Za-z0-9_-]*` (they become directory names), be
unique across setup, entries and judges, and not be `final`.

## How the winner is computed

| Mode | Order |
|---|---|
| `borda` | Borda points (K−1−position over the K surviving entries, summed over judges), then mean score, then caller order |
| `metric` | meets acceptance per **every** measuring judge, then each `metric.keys` entry in turn (median across judges, missing values last), then caller order |

- Judges re-measure. An entrant's self-reported metrics and self-assessment are
  never used in the aggregation.
- A judge counts toward the quorum (2, or 1 when `judges` has one row) only if
  it returned something the aggregation can use. Short of quorum, the run returns
  `reason: no-quorum` and runs no refine agent.
- A tie that reaches caller order is reported as `tie: true` with `tied_with`.
  List an incumbent first if it should keep ties.

The result carries `winner`, `standings`, `ranking_gaps` (the entries each judge
left unranked or unmeasured), every verdict and entry, and `refined`.

## Workflow harness (template)

`workflows/compete-and-judge.workflow.js` ships beside this skill. **It is a TEMPLATE to adapt,
not a script to run verbatim.** Read it, then rewrite it for the work in front of you.

**Adapt freely:** the agent prompts, the entrant angles and judge lenses, `MAX_ENTRIES`,
`MAX_JUDGES` and `QUORUM`, the refine step (a decision document or a contract instead of a
polished artefact), and the setup briefs.

**Agent budget:** 11 — at most 2 setup agents, 5 entrants, 3 judges and 1 refine agent. A run without setup, with 3 entries, 3 judges and a refine, spawns 7.

**Preserve across any adaptation:** (a) entries and judges come from the caller's `args`, cut
by `.slice(0, N)` literals in the fan-out after an explicit over-cap abort, never truncated
silently; (b) the winner is `standings[0]` of the JS aggregation, ties break on mean score and
then caller order, a tie is reported, and short of quorum there is no winner; no agent runs
between Judge and Refine; (c) metric mode ranks on judge-measured numbers only; (d) the two
barriers: setup completes before any entrant starts, because entries must be comparable, and
every judge sees every surviving entry, because a ranking needs all of them;
(e) `scripts/tests/test-compete-and-judge.sh` passes.

If an adaptation makes entrants commit (`isolation: 'worktree'`, one branch per entry), two
clauses apply. Never `Workflow({resumeFromRunId})` to retry a few failed worktree agents — a
resume re-runs agents that already succeeded and opens duplicate PRs (#1868). Re-dispatch the
failed units fresh and sequentially after checking
`gh pr list --head <branch> --state all --json number,state`. Push, PR creation, and GitHub
mutations happen **only** in the single sequential finalise stage, never inside a fanned-out
agent; that stage also deletes the losing branches and worktrees by name.

**Skip the harness when:** there is one plausible approach, or one reviewer's opinion is the
whole question. That is a linear pass, and the harness is pure overhead.

## Measured arms

A/B experiments (arms × seeds, a shared metric, a human verdict) share a
protocol but not a skeleton: 2 ad-hoc runs in 2 projects had different phase
structures, too few to fix one. Write the run as its own script and keep these
clauses:

1. **Fix the design before running.** Name the arms, the one variable each
   changes, the seeds (at least 3, the same seeds for every arm), the metric,
   and the rule that will decide the outcome.
2. **One variable per arm.** Diff each arm's emitted inputs against the
   baseline's; any difference beyond the intended variable is a defect that
   invalidates the comparison.
3. **Gate the instrument on a known-good case** before any verdict. A scorer
   that cannot separate a known-good from a known-bad case must refuse to
   report.
4. **Build in parallel, land in sequence.** The arm harness and the scorer can
   be built side by side and each checked by a fresh verifier, but merging and
   PR creation happen in one sequential stage.
5. **Claim an effect only above the seed-to-seed spread**, and analyse per
   group (subject, shot, character) before pooling. A pooled trend can reverse
   within every group.
6. **Blind judging** when a model judges outputs: it reads anonymised packets
   only, and the arm key is stored outside the repo where the judge cannot
   read it.
7. **A human watch list.** For each output, list where the instrument's claim
   is most fragile (the frames, items or regions to look at) with an empty
   verdict line per item. Agents never fill the verdicts.
8. **An independent checker re-derives every headline number** from the
   committed raw data, not from the write-up, and audits the arm-vs-baseline
   input diff itself.

With few arms and one cheap run each, `compete-and-judge` in `metric` mode can
carry the experiment: each arm is an entry and each judge runs the scorer.

## Related

- `.claude/rules/workflow-vs-skill.md` — the three gating axes; § The two shapes with no fit here scopes where this template fits (Tournament)
- `workflow-implement-verify` — the sibling template for known units that each need a fix and a check
- `workflow-scale-budget` — sizing a run before it starts
- `agent-patterns-plugin:adversarial-review` — one reviewer per lens, when there is one artefact rather than several
- `agent-patterns-plugin:multi-model-delegation` — the inverse of a judge: the disagreement is the output
