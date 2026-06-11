---
name: evaluate-improve
description: Suggest improvements to SKILL.md content, descriptions, or tool config from eval results. Use when raising pass rates, fixing triggering, or iterating on a skill after evaluation.
args: <plugin/skill-name> [--apply] [--description-only] [--best-of N]
allowed-tools: Task, Read, Write, Edit, Glob, Grep, Bash(bash *), Bash(python3 *), Bash(cat *), Bash(jq *), Bash(find *), Bash(diff *), AskUserQuestion, TodoWrite
argument-hint: "git-plugin/git-commit [--apply] [--best-of 3]"
created: 2026-03-04
modified: 2026-06-11
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
| `--best-of N` | 1 | Generate N candidate revisions and apply the eval-ranked winner (requires `--apply`) |

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

If `--best-of N` with N > 1, follow Step 5a to pick the winning revision
first, then continue with the apply flow below using the winner's content.

For each approved suggestion:
1. Read the current SKILL.md
2. Apply the change using Edit
3. Update the `modified` date in frontmatter

### Step 5a: Generate and rank candidates (if --best-of N > 1)

Instead of drafting the approved edits once, generate N alternative drafts and
let evaluation pick the winner.

1. **Generate candidates.** Write N complete candidate revisions of the
   SKILL.md to `<plugin>/skills/<skill>/eval-results/candidates/candidate-<i>.md`
   (the `eval-results/` tree is gitignored). Each candidate implements the
   approved suggestions with a genuinely different strategy — different
   instruction placement, phrasing, or example choice — not paraphrases of one
   draft.

2. **Rank with real grading when evals exist.** If the skill has `evals.json`:
   - For each candidate, run one pass per eval case: spawn a Task subagent
     (`subagent_type: general-purpose`) that receives the **candidate**
     content as the skill context and executes the eval prompt (mirrors
     `/evaluate:skill` Step 4; use `prepare_run.sh` for the run directories).
   - Grade each transcript with
     `python3 evaluate-plugin/scripts/grade_deterministic.py` — typed checks
     grade for zero judge tokens; defer fuzzy assertions to the `eval-grader`
     agent.
   - Rank candidates by mean pass rate. Break ties with the `eval-comparator`
     agent: blind pairwise comparison of the tied candidates' transcripts.

3. **Fall back to blind self-preference when no evals exist.** Without
   `evals.json` there are no prompts to roll out. Rank via the
   `eval-comparator` agent — pairwise, candidates presented as Output A/B,
   the analyzer's weakness list passed as the assertions. Flag this in the
   report as a weaker signal and suggest re-running `/evaluate:skill` with
   `--create-evals` first.

4. **Apply the winner** through the Step 5 apply flow, and record the ranking
   in the history entry (Step 5b below): a `candidates` array with each
   candidate's id, pass rate (or comparison score), and a `selected` flag.

Token cost is bounded at N × eval cases × 1 run plus grading; treat `--best-of`
without a number as N=3. Prefer this mode for skills that have `evals.json` —
deterministic ranking of real rollouts is the point; text-only self-preference
is the fallback.

### Step 5b: Record history

After applying changes, update (or create) the history file at:
```
<plugin-name>/skills/<skill-name>/eval-results/history.json
```

Add a new iteration entry recording:
- Version number (increment from previous)
- Timestamp
- Pass rate from current benchmark
- Summary of changes made
- Candidate ranking when `--best-of` was used: a `candidates` array of `{id, pass_rate, selected}` (use `comparison_score` instead of `pass_rate` for the no-evals fallback)

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
| `--best-of N` | Generate N candidate revisions, rank by eval pass rate, apply winner |
