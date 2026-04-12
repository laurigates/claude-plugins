---
name: evaluate-skill
description: |
  Evaluate a skill's effectiveness by running test cases and grading results.
  Use when you want to test whether a skill produces correct guidance, validate
  skill improvements, or benchmark a skill before release.
args: <plugin/skill-name> [--create-evals] [--runs N] [--baseline]
allowed-tools: Task, Read, Write, Edit, Glob, Grep, Bash(bash *), TodoWrite
argument-hint: "git-plugin/git-commit [--create-evals] [--runs 3] [--baseline]"
agent: general-purpose
created: 2026-03-04
modified: 2026-04-12
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

- Skill files: !`bash ${CLAUDE_PLUGIN_ROOT}/scripts/inspect_eval.sh --plugin-dir $1`

## Parameters

Parse these from `$ARGUMENTS`:

| Parameter | Default | Description |
|-----------|---------|-------------|
| `<plugin/skill-name>` | required | Path as `plugin-name/skill-name` |
| `--create-evals` | false | Generate eval cases if none exist |
| `--runs N` | 1 | Number of runs per eval case |
| `--baseline` | false | Also run without skill for comparison |

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

**If the file exists**: read and validate it against the evals.json schema (see `evaluate-plugin/references/schemas.md`).

**If the file does not exist AND `--create-evals` is set**: Analyze the SKILL.md and generate eval cases:

1. Read the skill thoroughly — understand its purpose, parameters, execution steps, and expected behaviors.
2. Generate 3-5 eval cases covering:
   - **Happy path**: Standard usage that should work correctly
   - **Edge case**: Unusual but valid inputs
   - **Boundary**: Inputs that test the limits of the skill's scope
3. For each eval case, write:
   - `id`: Unique identifier (e.g., `eval-001`)
   - `description`: What this test validates
   - `prompt`: The user prompt to simulate
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
2. Spawn a Task subagent (`subagent_type: general-purpose`) that:
   - Receives the skill content as context
   - Executes the eval prompt
   - Works in the repository as if it were a real user request
3. Capture the subagent output.
4. Record timing data (duration) and write to `$RUN_DIR/timing.json`.
5. Write the transcript to `$RUN_DIR/transcript.md`.

### Step 5: Run baseline (if --baseline)

If `--baseline` is set, repeat Step 4 but **without** loading the skill content. Pass `--baseline` to `prepare_run.sh` so results are written into a parallel `baseline/` subdirectory. This creates a comparison point to measure skill effectiveness.

Use the same eval prompts and record results in the `baseline/` subdirectory.

### Step 6: Grade results

For each run, delegate grading to the `eval-grader` agent via Task:

```
Task subagent_type: eval-grader
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
