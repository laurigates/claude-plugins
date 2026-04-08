---
name: evaluate-improve
description: |
  Analyze evaluation results and suggest concrete skill improvements. Use after
  running evaluations to get actionable recommendations for improving skill
  quality, descriptions, or instructions.
args: <plugin/skill-name> [--apply] [--description-only]
allowed-tools: Task, Read, Write, Edit, Glob, Grep, Bash(cat *), Bash(jq *), Bash(find *), Bash(diff *), AskUserQuestion, TodoWrite
argument-hint: "git-plugin/git-commit [--apply]"
created: 2026-03-04
modified: 2026-03-04
reviewed: 2026-03-04
---

# /evaluate:improve

Analyze evaluation results and suggest concrete improvements to a skill.

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

## Execution

### Step 1: Load eval results

Read the most recent benchmark from:
```
<plugin-name>/skills/<skill-name>/eval-results/benchmark.json
```

If no results exist, suggest running `/evaluate:skill` first and stop.

Also read the current SKILL.md to understand the skill.

### Step 2: Analyze results

Delegate analysis to the `eval-analyzer` agent via Task:

```
Task subagent_type: eval-analyzer
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

### Step 5: Apply changes (if --apply)

Use AskUserQuestion to let the user select which suggestions to apply:

```
Which improvements should I apply?
[x] Add error handling for missing git config
[x] Add trigger phrases to description
[ ] Add breaking change example
[ ] Restructure flag reference
```

For each approved suggestion:
1. Read the current SKILL.md
2. Apply the change using Edit
3. Update the `modified` date in frontmatter

After applying changes, update (or create) the history file at:
```
<plugin-name>/skills/<skill-name>/eval-results/history.json
```

Add a new iteration entry recording:
- Version number (increment from previous)
- Timestamp
- Pass rate from current benchmark
- Summary of changes made

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

## Quick Reference

| Flag | Description |
|------|-------------|
| `--apply` | Apply approved changes to SKILL.md |
| `--description-only` | Focus on description improvements only |
