# Loop Integrity

Long-running and self-continuing loops — TDD `test → fix` cycles, multi-phase
checkpoint refactors, "treadmill" plans that rewrite their own goal file to roll
into the next phase — share two failure modes that have nothing to do with the
work itself and everything to do with how the loop *governs* itself:

| Failure | What happens | Symptom |
|---------|--------------|---------|
| **Self-judged stop** | The same agent doing the work also decides it's done | The loop optimises for *completion*, not *correctness* — it declares victory the moment the surface symptom clears, rationalising away the residual fault (the bias an agent told to finish always has) |
| **Drift on self-mutation** | A loop edits its own goal/plan file for the next iteration but leaves no resumable state behind | A fresh session re-enters with no idea what was verified, what changed, or what "done" means — *you are not automating work, you are automating context drift* |

This rule names the two guards that close those gaps. It is the governance
layer under the looping skills — it does **not** reimplement Claude Code's
native `/goal` (stop-hook + neutral verifier) or `/loop` (scheduled re-run); it
distils *why those work* into a bar our own loops can meet.

## Pillar 1 — the stop condition is judged independently

The exit criterion of a loop must be evaluated by an actor **other than** the
one that produced the work — a fresh, isolated agent reading only the acceptance
criteria and the artefact, with no memory of the effort that went in. This is
the same isolation `cold-read-gate` and `adversarial-review` rely on: a reviewer
that shares the worker's context inherits the worker's motivation to be done.

| | Self-judged (avoid) | Independently judged (prefer) |
|---|---|---|
| Who decides "done"? | The worker | A fresh `Agent` / sub-agent that did not do the work |
| What it reads | Its own reasoning trace | Acceptance criteria + the artefact only |
| Bias | Toward declaring completion | Toward the criterion as written |

Cheap mechanical exit conditions (a green test suite, a clean `tsc`, exit code
0) are *already* independent — a failing test does not care how hard you worked.
The independent-verifier requirement bites when "done" is a judgement
("the class is now single-purpose", "the docs are accurate"): that judgement
must come from outside the worker.

## Pillar 2 — every iteration leaves a compact state packet

A loop that re-enters across context limits or session boundaries must, *before
it mutates its plan toward the next iteration*, write a packet that lets a
context-free successor pick up cleanly:

| Field | Why a successor needs it |
|-------|--------------------------|
| **Objective** | What "done" means for the whole loop, not just this iteration |
| **Repo / ref** | The exact base the work assumes (branch, base commit) |
| **Files in scope** | Where the next iteration is allowed to touch |
| **Exit condition** | The literal criterion that ends the loop |
| **Verifier result** | What the independent check last returned (pass / fail + why) |
| **Changed since last run** | What the previous iteration actually did, so the successor doesn't redo or undo it |

The dangerous shape the community flagged: a treadmill that overwrites its goal
file with the next phase but carries none of the above forward. It keeps moving;
it stops being *resumable*.

## Bounding runaway

Both pillars assume the loop terminates. Independent verifiers reduce false
"done"s but can produce false "not done"s, so every loop also needs a hard
ceiling — `--max-cycles` / `--max-iterations`, "same failure N times in a row =
stuck", or a phase cap. A loop with no ceiling and a strict verifier can churn
forever; bound it and surface the stuck state for a human.

## Where this applies

| Skill | How it should meet the bar |
|-------|----------------------------|
| `project-plugin:project-test-loop` | Mechanical stop (green suite) is already independent; the ceiling is `--max-cycles` and the "same test fails 3×" stop |
| `workflow-orchestration-plugin:workflow-checkpoint-refactor` | Phase acceptance gets an independent verifier before `done`; the plan file *is* the state packet (carries verifier result + changed-since fields) |
| `project-plugin:project-continue` | Reads the state packet to re-enter; never assumes the prior session's reasoning |
| Any self-mutating "treadmill" plan | Write the packet before rewriting the goal toward the next phase |

## Origin

Distilled from the r/ClaudeCode "Goal and Loop — kinda the same?" discussion,
where the load-bearing observations were that native `/goal` *"spawns a
fresh/neutral agent that checks if the conditions are met"* (Pillar 1), that
self-review is *"fundamentally flawed because the review is not independent —
agents optimise for completion not correctness"* (Pillar 1), and that a loop
which *"mutates its own goal file without leaving that packet behind"* is
*"automating context drift"* (Pillar 2). The packet field list is that comment's
verbatim shape.

## Related

- `agent-patterns-plugin:adversarial-review` — the isolated second-pass reviewer that a judgement-based stop condition delegates to
- `agent-patterns-plugin:cold-read-gate` — the isolation pattern both pillars reuse
- `agent-patterns-plugin:verify-before-plan` — independent review of the loop's *premises* before it starts
- `.claude/rules/agent-coworker-detection.md` — baseline-drift snapshots, the local-state sibling of the state packet
- `.claude/rules/pr-branch-sync.md` — the remote sibling: confirm the branch a loop builds on is still live
- `.claude/rules/regression-testing.md` — `scripts/check-loop-integrity.sh` is this rule's semantic guard
