---
model: opus
name: project-distill
description: |
  Distill session insights into reusable knowledge: Claude rules, skill improvements,
  and justfile recipes. Use at the end of a session to capture learnings, update existing
  artifacts, and avoid reinventing solutions. Prioritizes updating over adding.
allowed-tools: Bash(git diff *), Bash(git log *), Bash(git status *), Bash(just *), Read, Grep, Glob, Edit, Write, AskUserQuestion, TodoWrite
argument-hint: "--rules | --skills | --recipes | --all | --dry-run"
args: "[--rules] [--skills] [--recipes] [--all] [--dry-run]"
created: 2026-02-11
modified: 2026-02-14
reviewed: 2026-02-14
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

Execute this session distillation workflow:

### Step 1: Analyze session activity

Understand what happened:

1. Review recent commits: `git log --oneline -20`
2. Review recent diffs: `git diff --stat HEAD~10..HEAD`
3. Identify patterns: repeated operations, workarounds, discoveries
4. Catalog tools used: effective commands, flags, workflows
5. Note pain points: where time was spent figuring things out

### Step 2: Evaluate against existing knowledge

For each potential insight, check existing artifacts:

**Rules** (`.claude/rules/*.md`):
- Does it update, contradict, or duplicate an existing rule?
- Prefer updating existing rules over creating new files

**Skills** (relevant plugin skills):
- Does this improve existing skill commands/examples?
- Does this suggest missing guidance?

**Justfile recipes**:
- Is there a repeated command that should become a recipe?
- Should an existing recipe be updated with better flags?
- Is an existing recipe now redundant?

### Step 3: Check redundancy

For each proposed change, answer:

1. Does this make an existing artifact redundant? → Propose removal
2. Does this overlap with existing artifacts? → Propose merging
3. Is the existing version still better? → Skip the proposal
4. Will this be used more than once? → Skip if one-off

### Step 4: Present proposals

Categorize findings as:

- [UPDATE] `.claude/rules/X.md` - Reason for update (description of change)
- [SKIP] Considered rule Y, but Z already covers it
- [UPDATE] `plugin/skills/skill-name/SKILL.md` - Pattern discovered
- [NEW] Genuinely new and reusable artifact (only if justified)
- [UPDATE] `recipe-name` - Better flags discovered (before/after)
- [REDUNDANT] `old-recipe` - Superseded by new approach

### Step 5: Apply changes

If not `--dry-run`:

1. Use AskUserQuestion to confirm each category before applying
2. Edit existing files for updates (preferred)
3. Create new files only for genuinely new artifacts
4. Remove redundant artifacts

### Step 6: Report summary

Output concise summary of what was changed (rules updated, recipes added, insights skipped)

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
