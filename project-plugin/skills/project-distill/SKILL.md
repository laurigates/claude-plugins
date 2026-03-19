---
model: sonnet
name: project-distill
description: |
  Distill session insights into reusable knowledge: Claude rules, skill improvements,
  and justfile recipes. Use at the end of a session to capture learnings, update existing
  artifacts, and avoid reinventing solutions. Prioritizes updating over adding.
allowed-tools: Bash(git diff *), Bash(git log *), Bash(git status *), Bash(just *), Read, Grep, Glob, Edit, Write, AskUserQuestion, TodoWrite
argument-hint: "--rules | --skills | --recipes | --all | --dry-run"
args: "[--rules] [--skills] [--recipes] [--all] [--dry-run]"
created: 2026-02-11
modified: 2026-03-19
reviewed: 2026-02-26
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

The primary context source is the **current conversation history** — all messages, tool calls, and results from this session are available. Git history is supplemental and may be unavailable (e.g., in non-git directories or multi-repo workspaces).

- Git repo detected: !`find . -maxdepth 1 -name '.git' -type d`
- Justfile: !`find . -maxdepth 1 \( -name 'justfile' -o -name 'Justfile' \) -print -quit`
- Rules directory: !`find .claude/rules -name '*.md' -type f`

## Parameters

| Parameter | Description |
|-----------|-------------|
| `--rules` | Only analyze potential rule updates |
| `--skills` | Only analyze potential skill updates |
| `--recipes` | Only analyze potential justfile recipe updates |
| `--all` | Analyze all three categories (default) |
| `--dry-run` | Show proposals without applying changes |

## Tool Call Efficiency

Minimize LLM round-trips throughout execution to avoid API rate limits:

| Principle | How |
|-----------|-----|
| Batch file reads | Issue multiple Read calls in a single response (e.g., read all rule files at once, not one per turn) |
| Batch discovery | Use a single Glob to collect all files in a category, then Read them all in one response |
| Single-pass analysis | Combine evaluation and redundancy checking — do not make separate passes over the same files |
| Sequential categories | When `--all`, fully complete one category before starting the next (rules → skills → recipes) |
| Parallel git commands | Issue independent git commands in a single response |

## Execution

Execute this session distillation workflow:

### Step 1: Analyze session activity

Understand what happened during this session using **all available context**:

1. Review the **conversation history** — tool calls, file edits, commands run, agent dispatches, and results
2. If in a git repo, run these commands in a single response (parallel tool calls):
   - `git log --oneline --max-count=20`
   - `git log --stat --oneline --max-count=10`
3. Identify patterns: repeated operations, workarounds, discoveries
4. Catalog tools used: effective commands, flags, workflows
5. Note pain points: where time was spent figuring things out

**Note:** Conversation history is the primary source. Git history is supplemental — it may be empty (non-git directory, multi-repo workspace, or no commits this session).

### Step 2: Evaluate and check redundancy (single pass per category)

Process categories sequentially. For each active category, batch all reads in one response, then analyze.

**When `--all`: complete rules → then skills → then recipes. Do not interleave.**

**Rules** (`.claude/rules/*.md`):
1. Glob `.claude/rules/*.md` to get the full file list
2. Read ALL rule files in a single response (parallel Read calls)
3. For each potential insight from Step 1, evaluate and check redundancy in one pass:
   - Does it update, contradict, or duplicate an existing rule? → Update in place
   - Does an existing rule already cover this? → Skip
   - Does this make an existing rule redundant? → Propose removal
   - Does this overlap with existing rules? → Propose merging
   - Is this genuinely new and reusable? → Propose addition
   - Prefer updating existing rules over creating new files

**Skills** (relevant plugin skills):
1. Glob to find relevant skill files (target specific plugins from Step 1 activity, not all skills)
2. Read matched skill files in a single response (parallel Read calls)
3. Evaluate and check redundancy in one pass — same criteria as rules

**Justfile recipes**:
1. Run `just --dump --dump-format json` to get all recipes in one call
2. Evaluate session commands against loaded recipes in one pass:
   - Is there a repeated command that should become a recipe?
   - Should an existing recipe be updated with better flags?
   - Is an existing recipe now redundant or superseded?
   - Will this be used more than once? → Skip if one-off

### Step 3: Present proposals

Categorize findings as:

- [UPDATE] `.claude/rules/X.md` - Reason for update (description of change)
- [SKIP] Considered rule Y, but Z already covers it
- [UPDATE] `plugin/skills/skill-name/SKILL.md` - Pattern discovered
- [NEW] Genuinely new and reusable artifact (only if justified)
- [UPDATE] `recipe-name` - Better flags discovered (before/after)
- [REDUNDANT] `old-recipe` - Superseded by new approach

### Step 4: Apply changes

If not `--dry-run`:

1. Use AskUserQuestion to confirm each category before applying
2. Edit existing files for updates (preferred)
3. Create new files only for genuinely new artifacts
4. Remove redundant artifacts

### Step 5: Report summary

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
| Session diff summary | `git log --stat --oneline --max-count=10` |
| Recent commits | `git log --oneline --max-count=20` |
| Files changed | `git log --name-only --max-count=10 --format=''` |
| List justfile recipes | `just --list` |
| Dump justfile as JSON | `just --dump --dump-format json` |
| Dry run recipe | `just --dry-run recipe-name` |
| Find rules | `find .claude/rules -name '*.md' -type f` |
| Batch-read all rules | Glob `.claude/rules/*.md` then Read all results in one response |
| All recipes as JSON | `just --dump --dump-format json` |

## Quick Reference

| Flag | Description |
|------|-------------|
| `--rules` | Scope to rules only |
| `--skills` | Scope to skills only |
| `--recipes` | Scope to justfile recipes only |
| `--all` | All categories (default) |
| `--dry-run` | Propose without applying |
