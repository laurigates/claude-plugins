---
name: evaluate-skill
description: Evaluate a skill by running test cases and grading results. Use when testing whether a skill produces correct guidance, validating improvements, or benchmarking before release.
args: <plugin/skill-name> [--create-evals] [--runs N] [--baseline]
allowed-tools: Task, Read, Write, Edit, Glob, Grep, Bash(bash *), TodoWrite
argument-hint: "git-plugin/git-commit [--create-evals] [--runs 3] [--baseline]"
agent: general-purpose
context: fork
created: 2026-03-04
modified: 2026-09-26
compatibility: claude-code
reviewed: 2026-03-04
---

# /evaluate:skill

Evaluate a skill's effectiveness by running behavioral test cases and grading the results against assertions.

## When to Use This Skill

| Use this skill when... | Use alternative when... |
|------------------------|------------------------|
| Want to test if a skill produces correct results | Need structural validation -> `scripts/plugin-compliance-check.sh` |
| Validating skill improvements before merging | Want to file feedback about a session -> `/feedback:session` |
| Benchmarking a skill against a baseline | Need to check skill freshness -> `/health:audit` |
| Creating eval cases for a new skill | Want to review code quality -> `/code-review` |

## Context

- Available skills: !`find . -path '*/skills/*' -name 'SKILL.md' -not -path '*/.claude/worktrees/*'`

## Parameters

Parse these from `$ARGUMENTS`:

| Parameter | Default | Description |
|-----------|---------|-------------|
| `<plugin/skill-name>` | required | Path as `plugin-name/skill-name` |
| `--create-evals` | false | Generate eval cases if none exist |
| `--runs N` | 1 | Number of runs per eval case |
| `--baseline` | false | Also run without skill for comparison |

## Workflow harness (template)

`workflows/evaluate-skill.workflow.js` ships beside this skill. **It is a TEMPLATE to
adapt, not a script to run verbatim.** Read it, then rewrite it for the work in front
of you. It covers Steps 2-7 for a batch-shaped run; a single spot check stays on the
prose path below.

**Adapt freely:** the agent prompts, the config axis (the shipped one is
`with-skill` / `baseline`), the effort tiers, the generation brief behind
`--create-evals`, and the shape of the `rows` the summary table renders.

**Preserve across any adaptation:** (a) the fan-out width is the cartesian product
`evalIds.length x runs x configs.length`, computed in JS from the eval-case list the
Preflight agent read off disk with `inspect_eval.sh --print-evals` - never a prose "for
each eval case, for each run"; (b) `GRADE_SCHEMA`'s closed `PASS|PARTIAL|FAIL|ERROR`
status enum plus the split `deterministic*` / `judge*` counters, so a vague verdict is
structurally impossible and a dead agent becomes an explicit `ERROR` row that stays in
the denominator instead of reading as a pass; (c) Aggregate is a real barrier - the
standard deviation and the baseline delta are cross-cell facts no single cell can
compute, and `benchmark.json` has to be written exactly once. Three further things are
structure, not preference: **the grader is never the agent that produced the
transcript** (`.claude/rules/loop-integrity.md` Pillar 1 - an author asked to judge its
own output optimises for done, not for correct), `grade_deterministic.py` grades first
and its verdicts are never re-judged, and the `cellCap` ceiling **aborts** rather than
truncating.

**Agent budget:** 2 + 2 x cells — preflight and aggregate, plus one rollout and one
independent grader per cell (at most `cellCap` cells). The scale guard asks before
every run, because the cell list is built at runtime.

**Skip the harness when:** the run is fewer than three cells - a one- or two-case spot
check, or a single re-run of one eval id - which is a linear pass where the harness is
pure overhead; the script returns `{mode:'inline'}` at that floor. The floor is
deliberately far lower than `configure-all`'s 15, because this harness's marginal cost
is a constant two agents: Steps 4 and 6 below already spawn one rollout subagent and
one grader subagent per cell, so the harness redistributes those agents rather than
adding to them. The steps below remain the authoritative description of *what* each
stage must produce; the harness only fixes *how* the work is split.

Four consequences worth stating inline:

- **This is the only template in the marketplace that also registers a name.** The
  bundled copy is the source of truth, but `evaluate-plugin:evaluate-plugin-batch`
  resolves it as `workflow('evaluate-skill', ...)`, so a copy must also live in
  `~/.claude/workflows/` and `meta.name` must be exactly `evaluate-skill`. Both
  children have to agree on that literal. Registration, the one-level nesting limit,
  and what to do when the name does not resolve are in
  [`docs/dynamic-workflow-registration.md`](../../../docs/dynamic-workflow-registration.md).
  Register this one and nothing else.

- **No agent in this harness is worktree-isolated, and that is deliberate.** Every
  rollout agent writes its run dir into the shared checkout (`prepare_run.sh`
  stages it under `tmp/eval-runs/`), and Aggregate has to read what all of
  them wrote; a worktree-isolated agent's writes are invisible to its siblings, so
  isolating them would silently empty the benchmark. Nothing here pushes, opens a PR,
  or mutates a forge either - so the two clauses
  `.claude/rules/workflow-vs-skill.md` requires of a worktree-dispatching template
  (the `resumeFromRunId` / #1868 warning and the sequential-finalise rule) do not
  apply, and adding worktree isolation to an adaptation would pull both of them in
  along with the bug.

- **The harness cannot vary the model across cells.** Every `agent()` call pins
  `model: 'opus'` because `scripts/check-workflow-js-model.sh` requires it, so the
  `config` axis here is `with-skill` / `baseline` and nothing else. A genuine
  cross-model or cross-effort sweep is `evaluate-plugin:evaluate-matrix`'s job and
  stays on its own deliberately sequential path.

- **`context: fork` stays, and it is not what justifies the harness.** The pin lives in
  `scripts/plugin-compliance-check.sh` (the `for fork_skill in` loop inside
  `check_skill_body()` - cited by name, because a line number in that file drifts
  every time a regression guard is inserted) and is unchanged by this template. Per
  `.claude/rules/workflow-vs-skill.md` "The `context: fork` corollary", fork already
  bought context isolation for free - so this harness has to earn its tokens by
  **splitting** rollout from grading behind a real barrier, which it does. Keeping
  `fork` beside a `pipeline()` is sanctioned because the width is **statically
  bounded**: `cellCap` (30 by default, and passed explicitly by the batch caller) is a
  script-decidable ceiling that aborts rather than growing, which is exactly the line
  `.claude/rules/skill-fork-context.md` now draws between a bounded fan-out and the
  unbounded, caller-chosen one the `[1m]` cascade hazard is about.

## Execution

### Step 1: Resolve skill path

Parse `$ARGUMENTS` to extract `<plugin-name>` and `<skill-name>`. The skill file lives at:
```
<plugin-name>/skills/<skill-name>/SKILL.md
```

Read the SKILL.md to confirm it exists and understand what the skill does.

### Step 2: Run structural pre-check

Run the compliance check to confirm the skill passes basic structural validation:
```
bash scripts/plugin-compliance-check.sh <plugin-name>
```

If structural issues are found, report them and stop. Behavioral evaluation on a structurally broken skill is wasted effort.

### Step 3: Load or create eval cases

Look for `<plugin-name>/skills/<skill-name>/evals.json`.

**If the file exists**: read and validate it against the evals.json schema (see `evaluate-plugin/references/schemas.md`). Accept the optional, back-compatible `evals[].fixture` block (`dir` / `setup` / `teardown` / `workdir`) — an eval without it is unchanged; an eval with it needs an isolated execution context (Step 4).

**If the file does not exist AND `--create-evals` is set**: Analyze the SKILL.md and generate eval cases:

1. Read the skill thoroughly — understand its purpose, parameters, execution steps, and expected behaviors.
2. Generate 3-5 eval cases covering:
   - **Happy path**: Standard usage that should work correctly
   - **Edge case**: Unusual but valid inputs
   - **Boundary**: Inputs that test the limits of the skill's scope
   - **Abstention control** (at least one, always): an impossible task whose honest answer is a refusal — nothing to act on, a target that does not exist, a request outside the skill's scope. Mark it `"expected_outcome": "abstain"` and give it an `absent_regex` that fails a fabricated deliverable. Without it, a skill that invents output under pressure grades the same as one that refuses honestly. Shape and worked example: `evaluate-plugin/references/schemas.md` § Abstention Controls.
3. For each eval case, write:
   - `id`: Unique identifier (e.g., `eval-001`)
   - `description`: What this test validates
   - `prompt`: The user prompt to simulate
   - `expected_outcome`: `abstain` on the abstention control; omit it (defaults to `comply`) elsewhere
   - `expectations`: List of assertion strings the output should satisfy
   - `tags`: Categorization tags
4. Write the generated cases to `<plugin-name>/skills/<skill-name>/evals.json`.

**If the file does not exist AND `--create-evals` is NOT set**: Report that no eval cases exist and suggest running with `--create-evals`.

### Step 4: Run evaluations

For each eval case, for each run (up to `--runs N`):

1. Scaffold the run directory and record the start time by running:
   ```
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/prepare_run.sh \
     --skill-dir <plugin-name>/skills/<skill-name> \
     --eval-id <eval-id> --run <N>
   ```
   Parse `RUN_DIR=`, `MANIFEST=`, and `STARTED_AT=` from output.
2. If the eval carries a `fixture` block, apply it to get an isolated workdir:
   ```
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/apply_fixture.sh \
     --fixture '<eval.fixture JSON>' --repo-root "$(pwd)"
   ```
   Parse `WORKDIR=` (the subagent then operates there). Skip this for evals
   without a `fixture` — they run in the repo as before.
3. Spawn a Task subagent (`subagent_type: general-purpose`) that:
   - Receives the skill content as context
   - Executes the eval prompt
   - Works in `$WORKDIR` if a fixture was applied, else in the repository
4. Capture the subagent output.
5. Record timing data (duration) and write to `$RUN_DIR/timing.json`.
6. Write the transcript to `$RUN_DIR/transcript.md`.
7. If a fixture was applied, tear it down after the transcript is copied out:
   `bash ${CLAUDE_PLUGIN_ROOT}/scripts/apply_fixture.sh --teardown "$WORKDIR" --fixture '<eval.fixture JSON>'`.

### Step 5: Run baseline (if --baseline)

If `--baseline` is set, repeat Step 4 but **without** loading the skill content. Pass `--baseline` to `prepare_run.sh` so results are written into a parallel `baseline/` subdirectory. This creates a comparison point to measure skill effectiveness.

Use the same eval prompts and record results in the `baseline/` subdirectory.

### Step 6: Grade results

For each run, delegate grading to the `eval-grader` agent via Task:

```
Task subagent_type: evaluate-plugin:eval-grader
Prompt: Grade this eval run against the assertions.
  Eval case: <eval case from evals.json>
  Transcript: <path to transcript.md>
  Output artifacts: <list of created/modified files>
```

The grader produces `grading.json` for each run.

### Step 7: Aggregate and report

Compute aggregate statistics across all runs:
- Mean pass rate (assertions passed / total assertions)
- Standard deviation of pass rate
- Mean duration

If `--baseline` was used, also compute:
- Baseline mean pass rate
- Delta (improvement from skill)

Write aggregated results to `<plugin-name>/skills/<skill-name>/eval-results/benchmark.json`.

Print a summary table:

```
## Evaluation Results: <plugin/skill-name>

| Metric | With Skill | Baseline | Delta |
|--------|-----------|----------|-------|
| Pass Rate | 85% | 42% | +43% |
| Duration | 14s | 12s | +2s |
| Runs | 3 | 3 | — |

### Per-Eval Breakdown

| Eval | Description | Pass Rate | Status |
|------|-------------|-----------|--------|
| eval-001 | Basic usage | 100% | PASS |
| eval-002 | Edge case | 67% | PARTIAL |
| eval-003 | Boundary | 100% | PASS |
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Inspect skill eval setup | `bash evaluate-plugin/scripts/inspect_eval.sh --plugin <plugin> --skill <skill>` |
| Print evals JSON | `bash evaluate-plugin/scripts/inspect_eval.sh --plugin <plugin> --skill <skill> --print-evals` |
| Prepare a run directory | `bash evaluate-plugin/scripts/prepare_run.sh --skill-dir <plugin>/skills/<skill> --eval-id <id> --run <N>` |
| Aggregate results | `bash evaluate-plugin/scripts/aggregate_benchmark.sh <plugin>` |

## Quick Reference

| Flag | Description |
|------|-------------|
| `--create-evals` | Generate eval cases from SKILL.md analysis |
| `--runs N` | Number of runs per eval case (default: 1) |
| `--baseline` | Run without skill for comparison |
