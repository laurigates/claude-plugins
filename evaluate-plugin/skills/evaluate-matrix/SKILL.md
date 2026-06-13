---
name: evaluate-matrix
description: Cross-model skill evals with real execution and grading — the executability gate. Use when checking whether a weak model can actually do a skill, not just comprehend it.
args: <plugin/skill-name> [--models opus,haiku] [--with-skill-only] [--runs N]
allowed-tools: Task, Read, Write, Edit, Glob, Bash(bash *), Bash(python3 *), TodoWrite
argument-hint: "git-plugin/git-commit --models opus,haiku --with-skill-only"
model: opus
agent: general-purpose
created: 2026-06-13
modified: 2026-06-13
reviewed: 2026-06-13
---

# /evaluate:matrix

The **executability** gate. Where `/evaluate:legibility` asks "can a fresh
agent *comprehend* this skill," this skill asks "can a *weak model* actually
*do* it" — run the skill's evals on haiku (and opus/sonnet) with real tool
execution, grade the produced artifact, and surface the per-skill verdict
`executable_on_haiku`. A skill that opus passes and haiku fails leans on
reasoning the cheap model lacks.

This builds the orchestration the cross-model design
([`docs/cross-model-evaluation.md`](../../docs/cross-model-evaluation.md))
calls a follow-up. It reuses, without duplicating: `prepare_run.sh`,
`grade_deterministic.py` (zero-token first pass), the `eval-grader` agent
(deferred fuzzy checks only), `model-matrix.json`, and `render_matrix_report.py`.

## When to Use This Skill

| Use this skill when... | Use alternative when... |
|------------------------|------------------------|
| Checking whether a weak model can *execute* a skill | Checking whether the SKILL.md *reads* clearly -> `/evaluate:legibility` |
| Running the Tier-2 cross-model sweep on a golden-set skill | Single-skill, single-model effectiveness -> `/evaluate:skill` |
| Diagnosing a skill that opus passes but haiku fails | Structural/lint validation -> `scripts/plugin-compliance-check.sh` |
| Re-checking canaries after a new model ships | Improving a skill from results -> `/evaluate:improve` |

## Context

- Skill eval setup: !`bash ${CLAUDE_PLUGIN_ROOT}/scripts/inspect_eval.sh --plugin-dir $1`

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `<plugin/skill-name>` | required | Target skill as `plugin-name/skill-name` |
| `--models <list>` | `opus,haiku` | Comma-separated pinned aliases to run |
| `--with-skill-only` | false | Skip the cached baseline side (with-skill runs only) |
| `--runs N` | 1 | Runs per (model × eval × config) |

Pinned model ids: `opus`=`claude-opus-4-8`, `sonnet`=`claude-sonnet-4-6`,
`haiku`=`claude-haiku-4-5`. Record the exact ids in `model-matrix.json` for
reproducibility (`.claude/rules/skill-evaluation.md`).

## Execution

Execute this cross-model matrix:

### Step 1: Resolve skill and evals

Read `<plugin-name>/skills/<skill-name>/evals.json`. If absent, report that
the matrix needs eval cases (point at `/evaluate:skill --create-evals`) and
stop. Validate it against the evals.json schema
([`references/schemas.md`](../../references/schemas.md)).

### Step 2: Run the matrix (serialized)

Loop over (model ∈ `--models`) × eval × config ∈ {`with_skill`,
`cached_baseline`} — skip `cached_baseline` if `--with-skill-only`, and reuse a
baseline cached for the same model-version rather than re-running it. For each
combination:

1. Scaffold the run dir:
   ```
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/prepare_run.sh \
     --skill-dir <plugin-name>/skills/<skill-name> \
     --eval-id <eval-id> --run <N>
   ```
2. Dispatch **one `Task` subagent with the `model` field set to the loop
   model** (full `Bash`/`Edit` — it does real tool execution, not just reading):
   ```
   Task subagent_type: general-purpose
   model: <loop model alias>
   prompt: <eval prompt; with_skill runs also receive the SKILL.md content>
   ```
   **Serialize** the dispatches — one at a time, never a parallel batch.
   `[1m]` models hit cascading rate limits with concurrent subagents
   (`.claude/rules/skill-fork-context.md`).
3. Write the subagent's produced artifact to `$RUN_DIR/transcript.md`.

### Step 3: Grade — deterministic first, judge only on deferral

For each run, grade the produced output:

1. Run the zero-token deterministic grader first:
   ```
   python3 ${CLAUDE_PLUGIN_ROOT}/scripts/grade_deterministic.py \
     --evals <evals.json> --eval-id <eval-id> --output $RUN_DIR/transcript.md --json
   ```
2. Only if it reports `JUDGE_PENDING > 0`, dispatch the `eval-grader` agent for
   the deferred fuzzy expectations:
   ```
   Task subagent_type: eval-grader
   Prompt: Grade ONLY the deferred (judge) expectations for <eval-id> ...
   ```
   Most expectations grade deterministically — the judge fires on a fraction.

### Step 4: Aggregate to model-matrix.json

Combine per-run pass rates into `<skill-dir>/eval-results/model-matrix.json`
following the schema. Compute, per model alias, the mean `with_skill` and
`baseline`, the `delta`, and `prev_delta` from any stored prior run.

### Step 5: Render the report

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/render_matrix_report.py \
  <skill-dir>/eval-results/model-matrix.json
```

The renderer emits the delta table, per-model verdicts, the **portability
flag** (opus−haiku spread ≥20 pts), and the **executability flag**
(`executable_on_haiku=false` when haiku's absolute with-skill rate is below the
0.5 floor while opus clears it). Print the report and call out whether the
executability flag fired.

## Minimal Provable Increment

Run the matrix for **`git-plugin/git-commit` only** (it already has typed-check
evals), `--models opus,haiku --with-skill-only`: grade deterministically,
render, and confirm the executability callout lights up or stays dark
correctly. This exercises every reused piece end-to-end before scaling to the
golden set.

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Inspect eval setup | `bash evaluate-plugin/scripts/inspect_eval.sh --plugin-dir <plugin>/skills/<skill>` |
| Prepare a run dir | `bash evaluate-plugin/scripts/prepare_run.sh --skill-dir <dir> --eval-id <id> --run <N>` |
| Deterministic grade | `python3 evaluate-plugin/scripts/grade_deterministic.py --evals <f> --eval-id <id> --output <out> --json` |
| Render the matrix | `python3 evaluate-plugin/scripts/render_matrix_report.py <dir>/eval-results/model-matrix.json` |

## Quick Reference

| Flag | Meaning |
|------|---------|
| `--models opus,haiku` | Which pinned aliases to run (default opus,haiku) |
| `--with-skill-only` | Skip the cached baseline side |
| `--runs N` | Runs per (model × eval × config) |

## Related

- `/evaluate:legibility` — the comprehension gate (cold-read, no execution)
- `/evaluate:skill` — single-model effectiveness with a baseline
- [`docs/cross-model-evaluation.md`](../../docs/cross-model-evaluation.md) — the design this implements
- `.claude/rules/skill-evaluation.md` — tiered methodology, golden set, cadence
- `.claude/rules/skill-fork-context.md` — why subagent dispatch is serialized
