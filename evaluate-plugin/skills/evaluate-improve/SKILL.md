---
name: evaluate-improve
description: Suggest improvements to SKILL.md content, descriptions, or tool config from eval results. Use when raising pass rates, fixing triggering, or iterating on a skill after evaluation.
args: <plugin/skill-name> [--apply] [--description-only] [--best-of N]
allowed-tools: Task, Read, Write, Edit, Glob, Grep, Bash(bash *), Bash(python3 *), Bash(cat *), Bash(jq *), Bash(find *), Bash(diff *), AskUserQuestion, TodoWrite
argument-hint: "git-plugin/git-commit [--apply] [--best-of 3]"
created: 2026-03-04
modified: 2026-08-31
compatibility: claude-code
reviewed: 2026-03-04
---

# /evaluate:improve

Analyze evaluation results and suggest concrete improvements to a skill.

The apply-path machinery is split into `references/` by the flag that needs
it — the delta-verify gate and `--best-of` ranking are read only when you are
actually applying an edit.

## When to Use This Skill

| Use this skill when... | Use alternative when... |
|------------------------|------------------------|
| Have eval results and want to improve the skill | Need to run evals first -> `/evaluate:skill` |
| Want to improve skill description for better triggering | Want to view raw results -> `/evaluate:report` |
| Iterating on a skill to increase pass rate | Want to file a bug -> `/feedback:session` |
| Optimizing skill instructions after benchmarking | Need structural fixes -> `plugin-compliance-check.sh` |

## Parameters

Parse these from `$ARGUMENTS`:

| Parameter | Default | Description |
|-----------|---------|-------------|
| `<plugin/skill-name>` | required | Path as `plugin-name/skill-name` |
| `--apply` | false | Apply approved changes to SKILL.md |
| `--description-only` | false | Focus on description improvements only |
| `--best-of N` | 1 | Generate N candidate revisions and apply the eval-ranked winner (requires `--apply`) |
| `--force-apply` | false | Apply even when the delta-verify gate shows the edit does not shrink the source-failure set (override; requires `--apply`) |

## Execution

### Step 1: Load eval results

Read the most recent benchmark from:
```
<plugin-name>/skills/<skill-name>/eval-results/benchmark.json
```

If no results exist, suggest running `/evaluate:skill` first and stop.

Also read the current SKILL.md to understand the skill.

**Capture the source-failure set.** From the benchmark, record the set of
eval-case IDs that *failed* with the skill active — these are the cases the
forthcoming edit is meant to fix, and they are the input to the delta-verify
gate below:

```
cat <plugin>/skills/<skill>/eval-results/benchmark.json \
  | jq -r '[.cases[] | select(.with_skill.passed == false) | .id]'
```

This set is distinct from the golden `evals.json` suite as a whole: the golden
set measures overall pass rate, the source-failure set measures whether the
edit fixed *the specific failures that motivated it* (AEGIS delta-verify). If
the set is empty (a clean benchmark, or no per-case data), there is nothing for
the gate to verify — skip it and proceed.

### Step 2: Analyze results

Delegate analysis to the `eval-analyzer` agent via Task:

```
Task subagent_type: evaluate-plugin:eval-analyzer
Prompt: Analyze these evaluation results and identify improvement opportunities.
  Skill: <path to SKILL.md>
  Benchmark: <benchmark.json contents>
  Mode: comparison (if baseline data exists) or benchmark (otherwise)
```

The analyzer produces categorized suggestions:
- **instructions**: Execution flow improvements
- **description**: Better intent-matching text
- **examples**: Missing or insufficient examples
- **error_handling**: Missing edge cases
- **tools**: Better tool configurations
- **structure**: Organizational improvements

### Step 3: Filter suggestions

If `--description-only`, filter to only `description` category suggestions.

Sort remaining suggestions by priority (high > medium > low).

### Step 4: Present suggestions

Present the categorized suggestions to the user:

```
## Improvement Suggestions: <plugin/skill-name>

Current pass rate: 72%

### High Priority

1. **[instructions]** Add explicit error handling for missing git config
   Evidence: eval-003 fails because the skill doesn't check for git user.name

2. **[description]** Add "conventional commit" as trigger phrase
   Evidence: Skill not selected when user says "make a conventional commit"

### Medium Priority

3. **[examples]** Add breaking change example to execution steps
   Evidence: eval-004 inconsistently handles breaking changes

### Low Priority

4. **[structure]** Move flag reference to Quick Reference table
   Evidence: Flags scattered across multiple sections
```

If `--apply` is NOT set, stop here.

### Delta-verify gate (required before any apply)

**Never write an edit to the live SKILL.md until the drafted candidate has
shrunk the source-failure set** captured in Step 1 — a higher aggregate pass
rate is not sufficient, because a candidate can lift the golden set while
leaving every motivating failure broken. Apply only when
`delta = (source failures before) − (source failures after)` is `> 0`;
`--force-apply` overrides and records the override.

Run the gate against the drafted candidate under `eval-results/candidates/`,
never against the live SKILL.md. Full procedure:
[references/delta-verify-gate.md](references/delta-verify-gate.md).

### Step 5: Apply changes (if --apply)

Use AskUserQuestion to let the user select which suggestions to apply:

```
Which improvements should I apply?
[x] Add error handling for missing git config
[x] Add trigger phrases to description
[ ] Add breaking change example
[ ] Restructure flag reference
```

If `--best-of N` with N > 1, follow Step 5a to pick the winning revision
first, then continue with the apply flow below using the winner's content.

Draft the approved edits into a candidate file and run them through the
**Delta-verify gate** above. Only proceed to write the live SKILL.md when the
gate passes (or `--force-apply` is set). For each approved suggestion:
1. Read the current SKILL.md
2. Apply the change using Edit
3. Update the `modified` date in frontmatter

### Step 5a: Generate and rank candidates (if --best-of N > 1)

Generate N alternative drafts and let evaluation pick the winner, ranking by
**source-failure delta first** and mean golden-set pass rate second, so a
candidate that lifts the aggregate while leaving the motivating failures
broken never wins. Treat `--best-of` without a number as N=3. Candidate
generation, the ranking and no-evals fallback, and the Step 5b history entry
that records it: [references/best-of-ranking.md](references/best-of-ranking.md).

### Step 6: Suggest re-evaluation

After applying changes, suggest:

```
Changes applied. Run `/evaluate:skill <plugin/skill-name>` to measure improvement.
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Read benchmark | `cat <plugin>/skills/<skill>/eval-results/benchmark.json \| jq .summary` |
| Read skill | `cat <plugin>/skills/<skill>/SKILL.md` |
| Read history | `cat <plugin>/skills/<skill>/eval-results/history.json \| jq '.iterations[-1]'` |
| Check pass rate | `cat <plugin>/skills/<skill>/eval-results/benchmark.json \| jq '.summary.with_skill.mean_pass_rate'` |
| Source-failure set | `cat <plugin>/skills/<skill>/eval-results/benchmark.json \| jq -r '[.cases[] \| select(.with_skill.passed == false) \| .id]'` |

## Quick Reference

| Flag | Description |
|------|-------------|
| `--apply` | Apply approved changes to SKILL.md |
| `--description-only` | Focus on description improvements only |
| `--best-of N` | Generate N candidate revisions, rank by source-failure delta then pass rate, apply winner |
| `--force-apply` | Apply even when the delta-verify gate shows the edit does not shrink the source-failure set |
