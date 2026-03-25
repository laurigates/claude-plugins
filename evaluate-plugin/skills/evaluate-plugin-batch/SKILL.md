---
model: opus
name: evaluate-plugin-batch
description: |
  Batch evaluate all skills in a plugin. Runs /evaluate:skill for each skill
  that has eval cases, then produces a plugin-level report. Use when auditing
  an entire plugin's quality or before a release.
args: <plugin-name> [--create-missing-evals] [--parallel N]
allowed-tools: Task, Read, Write, Glob, Grep, Bash(cat *), Bash(jq *), Bash(find *), Bash(ls *), Bash(date *), Bash(mkdir *), SlashCommand, TodoWrite
argument-hint: "git-plugin [--create-missing-evals]"
agent: general-purpose
created: 2026-03-04
modified: 2026-03-04
reviewed: 2026-03-04
---

# /evaluate:plugin

Batch evaluate all skills in a plugin. Runs `/evaluate:skill` for each skill, then produces a plugin-level quality report.

## When to Use This Skill

| Use this skill when... | Use alternative when... |
|------------------------|------------------------|
| Auditing all skills in a plugin before release | Evaluating a single skill -> `/evaluate:skill` |
| Establishing quality baselines across a plugin | Viewing past results -> `/evaluate:report` |
| Checking overall plugin quality after refactoring | Need structural compliance -> `plugin-compliance-check.sh` |

## Context

- Plugin skills: !`find $1/skills -name "SKILL.md" -maxdepth 3`
- Existing evals: !`find $1/skills -name "evals.json" -maxdepth 3`

## Parameters

Parse these from `$ARGUMENTS`:

| Parameter | Default | Description |
|-----------|---------|-------------|
| `<plugin-name>` | required | Name of the plugin to evaluate |
| `--create-missing-evals` | false | Generate evals for skills that lack them |
| `--parallel N` | 1 | Max concurrent skill evaluations |

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

Track progress with TodoWrite — mark each skill as it completes.

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
| List plugin skills | `ls -d <plugin>/skills/*/SKILL.md` |
| Check for evals | `find <plugin>/skills -name evals.json` |
| Count skills | `ls -d <plugin>/skills/*/SKILL.md \| wc -l` |
| Aggregate results | `bash evaluate-plugin/scripts/aggregate_benchmark.sh <plugin>` |

## Quick Reference

| Flag | Description |
|------|-------------|
| `--create-missing-evals` | Generate eval cases for skills without them |
| `--parallel N` | Max concurrent evaluations (default: 1) |
