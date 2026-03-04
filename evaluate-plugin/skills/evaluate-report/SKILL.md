---
model: haiku
name: evaluate-report
description: |
  View evaluation results and benchmark reports. Use when you want to see
  past eval results, compare benchmark runs, or review quality trends for
  a skill or plugin.
args: <plugin/skill-name | plugin-name> [--latest] [--history] [--compare]
allowed-tools: Read, Glob, Grep, Bash(cat *), Bash(jq *), Bash(find *), Bash(ls *), TodoWrite
argument-hint: "git-plugin/git-commit [--latest] | git-plugin [--history]"
created: 2026-03-04
modified: 2026-03-04
reviewed: 2026-03-04
---

# /evaluate:report

View evaluation results and benchmark reports for a skill or plugin.

## When to Use This Skill

| Use this skill when... | Use alternative when... |
|------------------------|------------------------|
| Want to see results from a past evaluation | Need to run new evaluations -> `/evaluate:skill` |
| Comparing benchmark runs over time | Want improvement suggestions -> `/evaluate:improve` |
| Reviewing quality trends for a plugin | Need structural compliance -> `plugin-compliance-check.sh` |

## Parameters

Parse these from `$ARGUMENTS`:

| Parameter | Default | Description |
|-----------|---------|-------------|
| `<target>` | required | `plugin/skill-name` for skill or `plugin-name` for plugin |
| `--latest` | true | Show most recent benchmark only |
| `--history` | false | Show all benchmark iterations |
| `--compare` | false | Compare current vs previous benchmark |

## Execution

### Step 1: Resolve target

Determine if `$ARGUMENTS` refers to a skill or plugin:
- Contains `/`: treat as `plugin-name/skill-name`, look for `<plugin>/skills/<skill>/eval-results/benchmark.json`
- No `/`: treat as `plugin-name`, look for `<plugin>/eval-results/plugin-benchmark.json`

If the target file does not exist, report that no evaluation results are available and suggest running `/evaluate:skill` or `/evaluate:plugin`.

### Step 2: Load results

**Skill-level report** (`--latest` or default):
Read `benchmark.json` and display:

```
## Evaluation Report: <plugin/skill-name>

**Last run**: <timestamp>
**Runs per eval**: N

| Metric | With Skill | Baseline | Delta |
|--------|-----------|----------|-------|
| Pass Rate | 85% | 42% | +43% |
| Duration | 14s | 12s | +2s |

### Per-Eval Results

| Eval ID | Description | Pass Rate | Failures |
|---------|-------------|-----------|----------|
| eval-001 | Basic usage | 100% | — |
| eval-002 | Edge case | 67% | assertion X |
```

**Skill-level history** (`--history`):
Read `history.json` and display improvement iterations:

```
## Evaluation History: <plugin/skill-name>

| Version | Date | Pass Rate | Changes |
|---------|------|-----------|---------|
| v3 (current) | 2026-03-04 | 85% | Improved step 3 instructions |
| v2 | 2026-03-01 | 72% | Added error handling |
| v1 | 2026-02-28 | 55% | Initial evaluation |
```

**Skill-level comparison** (`--compare`):
Read current and previous benchmarks, show delta:

```
## Comparison: <plugin/skill-name>

| Metric | Previous | Current | Delta |
|--------|----------|---------|-------|
| Pass Rate | 72% | 85% | +13% |
| Duration | 16s | 14s | -2s |

Improved evals: eval-002, eval-004
Regressed evals: none
```

**Plugin-level report**:
Read `plugin-benchmark.json` and display:

```
## Plugin Report: <plugin-name>

| Skill | Evals | Pass Rate | Status |
|-------|-------|-----------|--------|
| skill-a | 4 | 100% | PASS |
| skill-b | 3 | 67% | NEEDS WORK |

**Overall**: 82% pass rate
**Skills evaluated**: N / M total
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Find skill benchmark | `cat <plugin>/skills/<skill>/eval-results/benchmark.json \| jq .summary` |
| Find plugin benchmark | `cat <plugin>/eval-results/plugin-benchmark.json \| jq .summary` |
| Check for history | `cat <plugin>/skills/<skill>/eval-results/history.json \| jq '.iterations \| length'` |
| List available results | `find <plugin> -name benchmark.json -o -name plugin-benchmark.json` |

## Quick Reference

| Flag | Description |
|------|-------------|
| `--latest` | Most recent benchmark (default) |
| `--history` | Show all iterations |
| `--compare` | Compare current vs previous |
