---
model: opus
name: project-distill
description: |
  Distill session insights into reusable knowledge: Claude rules, skill improvements,
  and justfile recipes. Use at the end of a session to capture learnings, update existing
  artifacts, and avoid reinventing solutions. Prioritizes updating over adding. Use when
  the user says "any insights", "distill session", "what did we learn", "update recipes",
  or wants to capture session knowledge.
allowed-tools: Bash(git diff *), Bash(git log *), Bash(git status *), Bash(just *), Read, Grep, Glob, Edit, Write, AskUserQuestion, TodoWrite
argument-hint: "Scope analysis to specific categories or use --dry-run to preview"
args: "[--rules] [--skills] [--recipes] [--all] [--dry-run]"
created: 2026-02-11
modified: 2026-02-13
reviewed: 2026-02-11
---

# /project:distill

Distill session insights into reusable project knowledge. Reviews what was done during a session and proposes targeted updates to Claude rules, skills, and justfile recipes.

## When to Use This Skill

| Use this skill when... | Use alternative when... |
|------------------------|------------------------|
| End of session, want to capture learnings | Need to write a blog post about work done -> `/blog:post` |
| Discovered a pattern worth reusing | Need to analyze git history for docs gaps -> `/git:log-documentation` |
| Found a CLI workflow worth saving as a recipe | Need to configure a justfile from scratch -> `/configure:justfile` |
| Want to update rules based on session experience | Need to check project infrastructure -> `/configure:status` |
| Avoiding reinventing solutions next session | Need to resume work where you left off -> `/project:continue` |

## Core Principle: Update Over Add

**Adding is not always better.** Before proposing any new artifact, evaluate:

| Question | If yes... |
|----------|-----------|
| Does this replace an existing rule/recipe/skill? | Remove the old one, add the new |
| Does this improve an existing one? | Update in place |
| Does an existing one already cover this? | Skip it |
| Is this genuinely new and reusable? | Add it |
| Is this a one-off that won't be needed again? | Skip it |

## Context

Gather session context to analyze:

- Session diff: !`git diff --stat HEAD~10..HEAD 2>/dev/null || echo "recent history unavailable"`
- Recent commits: !`git log --oneline -20 2>/dev/null`
- Current branch: !`git branch --show-current 2>/dev/null`
- Justfile: !`find . -maxdepth 1 \( -name 'justfile' -o -name 'Justfile' \) -print -quit 2>/dev/null`
- Rules directory: !`find .claude/rules -name '*.md' -type f 2>/dev/null`
- Changed files: !`git diff --name-only HEAD~10..HEAD 2>/dev/null || echo "none"`

## Parameters

| Parameter | Description |
|-----------|-------------|
| `--rules` | Only analyze potential rule updates |
| `--skills` | Only analyze potential skill updates |
| `--recipes` | Only analyze potential justfile recipe updates |
| `--all` | Analyze all three categories (default) |
| `--dry-run` | Show proposals without applying changes |

## Execution

### Phase 1: Session Analysis

Understand what happened this session:

1. **Review git history** - Read recent commits and diffs to understand what was done
2. **Identify patterns** - Look for repeated operations, workarounds, or discoveries
3. **Catalog tools used** - Note CLI commands, flags, and workflows that were effective
4. **Note pain points** - Identify where time was spent figuring things out

```bash
# Recent session activity
git log --oneline -20
git diff --stat HEAD~10..HEAD
```

### Phase 2: Evaluate Against Existing Knowledge

For each potential insight, check existing artifacts:

**Rules** (`.claude/rules/*.md`):
- Read existing rules in the project's `.claude/rules/` directory
- Check if insight updates, contradicts, or is already covered by an existing rule
- Prefer updating existing rules over creating new files

**Skills** (scan relevant plugin skills):
- Check if a pattern learned improves an existing skill's commands or examples
- Check if a workaround suggests a skill is missing guidance

**Justfile recipes** (`justfile` or `Justfile`):
- Read existing recipes
- Check if a command used repeatedly should become a recipe
- Check if an existing recipe should be updated with better flags or patterns
- Check if an existing recipe was made redundant by a new approach

### Phase 3: Redundancy Check

For each proposed change, explicitly answer:

1. **Does this make an existing artifact redundant?** If so, propose removing it
2. **Does this overlap with an existing artifact?** If so, propose merging
3. **Is the existing version still better?** If so, skip the proposal
4. **Will this be used more than once?** If not, skip it

### Phase 4: Present Proposals

Present findings as a categorized list with clear rationale:

```
## Session Insights

### Rules
- [UPDATE] `.claude/rules/X.md` - Reason for update
  Change: description of what changes
- [SKIP] Considered adding Y rule, but Z already covers it

### Skills
- [UPDATE] `plugin/skills/skill-name/SKILL.md` - Add pattern discovered
  Change: description of what changes
- [NEW] Reason this is genuinely new and reusable

### Justfile Recipes
- [UPDATE] `recipe-name` - Better flags discovered
  Before: `old command`
  After: `new command`
- [NEW] `recipe-name` - Reusable workflow not yet captured
  Recipe: `just recipe-name`
- [REDUNDANT] `old-recipe` - Superseded by new approach
  Recommendation: remove or replace
```

### Phase 5: Apply Changes

If not `--dry-run`, use AskUserQuestion to confirm each category of changes before applying.

Apply approved changes:
- Edit existing files for updates
- Create new files only for genuinely new artifacts
- Remove redundant artifacts

### Phase 6: Summary

Output a concise summary of what was changed:

```
Distilled 3 insights:
- Updated .claude/rules/testing.md (added playwright pattern)
- Updated justfile recipe `test` (added --bail flag)
- Skipped 2 insights (already covered)
```

## Evaluation Criteria for Each Category

### Rules Worth Capturing

| Capture when... | Skip when... |
|-----------------|--------------|
| Pattern applies across sessions | One-time fix |
| Convention that prevents mistakes | Obvious best practice |
| Project-specific constraint discovered | Generic advice |
| Tool behavior that's non-obvious | Well-documented behavior |

### Recipes Worth Capturing

| Capture when... | Skip when... |
|-----------------|--------------|
| Command was run 3+ times with same flags | One-off command |
| Multi-step workflow that should be atomic | Single simple command |
| Flags that are hard to remember | Common well-known flags |
| Project-specific pipeline step | Standard `just` template recipe |

### Skill Improvements Worth Proposing

| Propose when... | Skip when... |
|-----------------|--------------|
| Discovered better command flags | Minor style preference |
| Found a pattern the skill doesn't cover | Edge case unlikely to recur |
| Existing guidance was misleading | Niche use case |
| New tool version changed behavior | Temporary workaround |

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Session diff summary | `git diff --stat HEAD~10..HEAD` |
| Recent commits | `git log --oneline -20` |
| Files changed | `git diff --name-only HEAD~10..HEAD` |
| List justfile recipes | `just --list` |
| Dump justfile as JSON | `just --dump --dump-format json` |
| Dry run recipe | `just --dry-run recipe-name` |
| Find rules | `find .claude/rules -name '*.md' -type f` |

## Quick Reference

| Flag | Description |
|------|-------------|
| `--rules` | Scope to rules only |
| `--skills` | Scope to skills only |
| `--recipes` | Scope to justfile recipes only |
| `--all` | All categories (default) |
| `--dry-run` | Propose without applying |
