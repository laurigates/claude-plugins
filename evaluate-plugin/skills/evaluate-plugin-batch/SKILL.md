---
name: evaluate-plugin-batch
description: Batch evaluate every skill in a plugin and produce a plugin-level report. Use when auditing an entire plugin's quality or validating before a release.
args: <plugin-name> [--create-missing-evals] [--parallel N]
allowed-tools: Task, Read, Write, Glob, Grep, Bash(bash *), SlashCommand
argument-hint: "git-plugin [--create-missing-evals]"
agent: general-purpose
created: 2026-03-04
modified: 2026-09-20
compatibility: claude-code
reviewed: 2026-09-02
---

# /evaluate:plugin-batch

Batch evaluate all skills in a plugin. Runs `/evaluate:skill` for each skill, then produces a plugin-level quality report.

## When to Use This Skill

| Use this skill when... | Use alternative when... |
|------------------------|------------------------|
| Auditing all skills in a plugin before release | Evaluating a single skill -> `/evaluate:skill` |
| Establishing quality baselines across a plugin | Viewing past results -> `/evaluate:report` |
| Checking overall plugin quality after refactoring | Need structural compliance -> `plugin-compliance-check.sh` |

## Context

- Available plugins: !`find . -maxdepth 2 -type d -name '*-plugin' -not -name '.claude-plugin'`

## Parameters

Parse these from `$ARGUMENTS`:

| Parameter | Default | Description |
|-----------|---------|-------------|
| `<plugin-name>` | required | Name of the plugin to evaluate |
| `--create-missing-evals` | false | Generate evals for skills that lack them |
| `--parallel N` | 1 | Max concurrent skill evaluations |

## Workflow harness (template)

`workflows/evaluate-plugin-batch.workflow.js` ships beside this skill. **It is a
TEMPLATE to adapt, not a script to run verbatim.** Read it, then rewrite it for
the work in front of you.

**Adapt freely:** the inventory and aggregation agent prompts, the effort tiers,
the `DEFAULT_WAVE` starting width, the `CELL_CAP` handed to each child, the
`skipped[]` reason strings, and the shape of the `rows` your project's report
actually needs.

**Preserve across any adaptation:** (a) the loop bound comes from
`inspect_eval.sh --plugin-dir <plugin>`'s `=== SKILLS ===` / `=== EVALS ===`
listings, never from a prose "for each skill" — and eval-readiness stays the
pure `s.hasEvals || createMissingEvals` filter over a file that exists or does
not, so no agent classifies it; (b) `REPORT_SCHEMA`'s closed
`complete | partial-sweep | aggregate-failed` status enum and its one-value
`denominatorSource` enum, which together make it structurally impossible to
report a plugin pass rate without stating that the denominator came from the
script; (c) the Aggregate stage is a barrier — `aggregate_benchmark.sh` walks
the filesystem for every skill's `eval-results/benchmark.json`, so its
denominators are only correct once the last cell has finished writing, and no
single cell can see the plugin-level numbers.

Three consequences of (a)–(c) that are also non-negotiable:

- **`CAP` (default 25) ABORTS; it never truncates.** A silently-shortened sweep
  publishes a pass rate over a denominator nobody chose — which is precisely the
  number this skill exists to produce correctly. The abort states the count and
  the cap.
- **`--parallel N` is the caller's and is never superseded.** The wave width is
  derived from `args.parallel`; `DEFAULT_WAVE` applies only when the caller
  supplied nothing, and a non-integer value falls back loudly via `log()`. The
  platform separately caps concurrency at `min(16, CPUs-2)`, and a nested child
  shares this run's cap and agent counter.
- **The workflow's own count is only a cross-check.** `crossCheck.agrees`
  compares the cells this run dispatched against the benchmarks the script found
  on disk. A disagreement emits `partial-sweep` — that disagreement is the
  anti-laziness signal, not a rounding error, and must never be smoothed into
  `complete`.

**This harness runs near-empty until a golden set of `evals.json` files exists.**
Per [`.claude/rules/skill-evaluation.md`](../../../.claude/rules/skill-evaluation.md)
eval coverage is deliberately scoped to ~15–25 canary skills, so most plugins
today have zero or one eval-ready skill and the run aborts with
`reason: 'below-floor'`. That is the designed outcome, not a bug — an empty
sweep means the evals have not been written yet, and the fix is to author them
(or pass `--create-missing-evals`), never to widen the harness.

**Skip the harness when:** the plugin has fewer than 2 eval-ready skills — the
modal case today, and `FLOOR = 2` is a hard bound that aborts there rather than
a tunable knob, because a single skill is exactly what `/evaluate:skill` already
does without an inventory agent, a nested workflow and an aggregate agent on
top. The steps below remain the authoritative description of *what* each stage
must produce; the harness only fixes *how* the work is split.

`context: fork` stays **off** for this skill. The fan-out here is a caller-chosen
`--parallel N` width, so the `[1m]` concurrent-subagent cascade hazard in
[`.claude/rules/skill-fork-context.md`](../../../.claude/rules/skill-fork-context.md)
applies; `scripts/plugin-compliance-check.sh` keeps this skill out of its
`context: fork` pin list for that reason, and the harness does not change it.

## Execution

### Step 1: Discover skills

Find all skills in the plugin:
```
<plugin-name>/skills/*/SKILL.md
```

List them and count the total.

### Step 2: Filter and prepare

For each skill, check if `evals.json` exists:
- **Has evals**: include in evaluation
- **No evals + `--create-missing-evals`**: include, will create evals during evaluation
- **No evals, no flag**: skip with a note

Report the breakdown:
```
Found N skills in <plugin-name>:
  - M with eval cases
  - K without eval cases (skipped | will create)
```

### Step 3: Run evaluations

For each included skill, invoke `/evaluate:skill` via the SlashCommand tool:

```
SlashCommand: /evaluate:skill <plugin-name>/<skill-name> [--create-evals]
```

If `--parallel N` is set and N > 1, batch evaluations into groups of N. Otherwise, run sequentially.

Report progress from the results themselves: after each `/evaluate:skill`
returns, state which skill finished and its pass rate from `benchmark.json`.
(Todo/task tools are not available on Opus 4.8+/Sonnet 5/Fable-generation
models unless `CLAUDE_CODE_ENABLE_TODO_TOOLS=1` is set; do not depend on them
— see `.claude/rules/agentic-permissions.md` § Task-tool availability.)

### Step 4: Aggregate plugin report

After all skill evaluations complete, read each skill's `benchmark.json` and aggregate:

```
bash evaluate-plugin/scripts/aggregate_benchmark.sh <plugin-name>
```

Write aggregated results to `<plugin-name>/eval-results/plugin-benchmark.json`.

### Step 5: Report

Print a plugin-level summary table:

```
## Plugin Evaluation: <plugin-name>

| Skill | Evals | Pass Rate | Status |
|-------|-------|-----------|--------|
| skill-a | 4 | 100% | PASS |
| skill-b | 3 | 67% | PARTIAL |
| skill-c | 5 | 80% | PASS |

**Overall**: 82% pass rate across N eval cases
```

Rank skills by pass rate. Flag any below 50% as needing attention.

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Inventory plugin skills + evals | `bash evaluate-plugin/scripts/inspect_eval.sh --plugin-dir <plugin>` |
| Inspect a single skill's evals | `bash evaluate-plugin/scripts/inspect_eval.sh --plugin <plugin> --skill <skill>` |
| Aggregate results | `bash evaluate-plugin/scripts/aggregate_benchmark.sh <plugin>` |

## Quick Reference

| Flag | Description |
|------|-------------|
| `--create-missing-evals` | Generate eval cases for skills without them |
| `--parallel N` | Max concurrent evaluations (default: 1) |
