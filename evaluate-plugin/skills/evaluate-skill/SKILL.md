---
name: evaluate-skill
description: Evaluate a skill by running test cases and grading results. Use when testing whether a skill produces correct guidance, validating improvements, or benchmarking before release.
args: <plugin/skill-name> [--create-evals] [--runs N] [--baseline] [--harness subagent|headless] [--triggers|--triggers-only]
allowed-tools: Task, Read, Write, Edit, Glob, Grep, Bash(bash *), Bash(python3 *), TodoWrite
argument-hint: "git-plugin/git-commit [--runs 3] [--baseline] [--harness headless] [--triggers]"
agent: general-purpose
context: fork
created: 2026-03-04
modified: 2026-10-05
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
| `--harness subagent\|headless` | `subagent` | How each cell is rolled out. `subagent`: an in-session Task subagent with the SKILL.md as context. `headless` (opt-in): a real `claude -p` child with the plugin loaded via `rollout_headless.sh`, so plugin loading, description routing, `allowed-tools` and hooks are exercised and trace/workspace checks can be graded. Needs `claude`, `jq`, `python3` |
| `--triggers` | false | After the eval cases, also run the skill's trigger evals (Step 4b) |
| `--triggers-only` | false | Run only the trigger evals (Step 4b); skip Step 4 and Steps 5-7 |

## Workflow harness (template)

`workflows/evaluate-skill.workflow.js` ships beside this skill. **It is a TEMPLATE to
adapt, not a script to run verbatim.** Read it, then rewrite it for the work in front
of you. It covers Steps 2-7 for a batch-shaped run **except Step 4b**: it has no
trigger stage, so with `--triggers` run Step 4b yourself after the workflow returns,
and with `--triggers-only` run Step 4b instead of the workflow. A single spot check
stays on the prose path below.

**Before rewriting the template**, read [references/harness-adaptation.md](references/harness-adaptation.md): what may change, the invariants to preserve, and the registered name `evaluate-skill`.

**Agent budget:** 2 + 2 x cells — preflight and aggregate, plus one rollout and one
independent grader per cell (at most `cellCap` cells). The scale guard asks before
every run, because the cell list is built at runtime. `args.harness: 'headless'`
does not change it: the rollout agent becomes a thin runner that calls
`rollout_headless.sh` (and never performs the task itself), still one per cell.

**Skip the harness when:** the run is fewer than three cells - a one- or two-case spot
check, or a single re-run of one eval id - which is a linear pass where the harness is
pure overhead; the script returns `{mode:'inline'}` at that floor. The floor is
deliberately far lower than `configure-all`'s 15, because this harness's marginal cost
is a constant two agents: Steps 4 and 6 below already spawn one rollout subagent and
one grader subagent per cell, so the harness redistributes those agents rather than
adding to them. The steps below remain the authoritative description of *what* each
stage must produce; the harness only fixes *how* the work is split.

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

Skip Step 4 and Steps 5-7 when `--triggers-only` is set (Step 4b still runs). Use the branch matching
`--harness`; the subagent branch is the default.

**Headless branch (`--harness headless`).** Follow [references/headless-rollout.md](references/headless-rollout.md); missing `claude`/`jq`/`python3` means `headless-unavailable` and stop, never fall back.

**Subagent branch (default).** For each eval case, for each run (up to `--runs N`):

1. Scaffold the run directory and record the start time by running:
   ```
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/prepare_run.sh \
     --skill-dir <plugin-name>/skills/<skill-name> \
     --eval-id <eval-id> --run <N>
   ```
   Parse `RUN_DIR=`, `MANIFEST=`, and `STARTED_AT=` from output.
2. If the eval has a `fixture` block, apply it ([references/fixtures.md](references/fixtures.md)) and use its `WORKDIR=`.
3. Spawn a Task subagent (`subagent_type: general-purpose`) that:
   - Receives the skill content as context
   - Executes the eval prompt
   - Works in `$WORKDIR` if a fixture was applied, else in the repository
4. Capture the subagent output.
5. Record timing data (duration) and write to `$RUN_DIR/timing.json`.
6. Write the transcript to `$RUN_DIR/transcript.md`.
7. Tear down any applied fixture after copying the transcript out (same file).

### Step 4b: Trigger evals (if --triggers or --triggers-only)

Run the `triggers` block per [references/trigger-evals.md](references/trigger-evals.md); none: say so and continue.

### Step 5: Run baseline (if --baseline)

If `--baseline` is set, repeat Step 4 but **without** loading the skill content. Pass `--baseline` to `prepare_run.sh` so results are written into a parallel `baseline/` subdirectory. This creates a comparison point to measure skill effectiveness.

Use the same eval prompts and record results in the `baseline/` subdirectory.

### Step 6: Grade results

For each run, grade the typed checks first, for zero model tokens. Pass `--trace` and
`--workspace --allow-exec` only when the rollout produced them (headless runs):
```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/grade_deterministic.py --evals <evals.json> \
  --eval-id <id> --output "$RUN_DIR/transcript.md" \
  [--trace "$RUN_DIR/trace.json"] [--workspace "$RUN_DIR/workspace" --allow-exec] --json
```
Its verdicts are final. Items under `harness_deferred` (trace/workspace checks on a
subagent run) are excluded from every total and never judged. Then delegate only the
`DEFERRED` (judge) expectations to the `eval-grader` agent via Task:

`subagent_type: evaluate-plugin:eval-grader`, prompt in [references/report-format.md](references/report-format.md#grader-prompt-step-6).

The grader produces `grading.json` for each run.

### Step 7: Aggregate and report

Compute the statistics in [references/report-format.md](references/report-format.md#aggregate-statistics-step-7) (pass rate, its std dev, duration; plus baseline and delta).

Write aggregated results to `<plugin-name>/skills/<skill-name>/eval-results/benchmark.json`,
recording the harness in `metadata.harness`.

Print a summary table laid out as in [references/report-format.md](references/report-format.md).

## Agentic Optimizations

Script commands and the flag quick reference: [references/command-reference.md](references/command-reference.md).

