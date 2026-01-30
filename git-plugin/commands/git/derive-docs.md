---
model: opus
created: 2026-01-24
modified: 2026-01-24
reviewed: 2026-01-24
allowed-tools: Bash(git log *), Bash(git shortlog *), Bash(git diff *), Bash(git branch *),
               Bash(git show *), Bash(git rev-list *), Bash(git diff-tree *),
               Bash(git status *), Read, Grep, Glob, Edit, Write, TodoWrite
argument-hint: [--rules] [--prd] [--adr] [--prp] [--all] [--since=<date>] [--depth=<N>]
description: Analyze git history to derive undocumented rules, PRDs, ADRs, and PRPs
---

## Context

- Current branch: !`git branch --show-current`
- Commit count: !`git rev-list --count HEAD 2>/dev/null || echo "0"`
- First commit: !`git log --format='%ai' --reverse 2>/dev/null | head -1`
- Latest commit: !`git log --format='%ai' -1 2>/dev/null`
- Existing rules: !`ls .claude/rules/ 2>/dev/null || echo "none"`
- Existing docs: !`ls docs/prds/ docs/adrs/ docs/prps/ 2>/dev/null || echo "none"`
- Commit conventions sample: !`git log --format='%s' -20 2>/dev/null`

## Parameters

- `--rules`: Derive `.claude/rules/` from commit patterns (conventions, naming, tooling)
- `--prd`: Detect features implemented without requirements documentation
- `--adr`: Detect architecture decisions made without decision records
- `--prp`: Detect implementation work done without planning documentation
- `--all`: Run all detection categories (default if no flags specified)
- `--since=<date>`: Limit analysis to commits after date (e.g., `--since=2025-01-01`)
- `--depth=<N>`: Number of commits to analyze (default: 200)
- `--dry-run`: Report findings without creating files
- `--refinements`: Focus on plan refinement detection (approach changes, reverts, rework)

## Your task

Analyze git commit history to identify documentation gaps. Use the `git-log-documentation` skill as reference for detection patterns and analysis techniques.

### Step 1: Determine Scope

Parse flags to determine which categories to analyze. Default to `--all` if no category flags provided.

Set analysis depth:
```bash
# Use --since if provided, otherwise --depth (default 200)
git log --format='%H %s' --since="$SINCE" 2>/dev/null || git log --format='%H %s' -$DEPTH
```

### Step 2: Rules Detection (if --rules or --all)

Analyze commit patterns for implicit conventions:

```bash
# File naming patterns
git log --diff-filter=A --name-only --format='' -$DEPTH | sort | uniq -c | sort -rn | head -20

# Commit message conventions
git log --format='%s' -$DEPTH | grep -oP '^\w+(\([^)]+\))?' | sort | uniq -c | sort -rn

# Tool/config patterns
git log --oneline -$DEPTH -- '*.config.*' 'tsconfig*' 'biome.json' '.eslintrc*' 'pyproject.toml' 'Cargo.toml'

# Test file conventions
git log --diff-filter=A --name-only --format='' -$DEPTH -- '*.test.*' '*.spec.*' '*_test.*' | head -20
```

Cross-reference with existing `.claude/rules/` to avoid duplicates.

### Step 3: PRD Detection (if --prd or --all)

Find features built without requirements documentation:

```bash
# Feature commits without PRD references
git log --format='%H %s' -$DEPTH | grep -iE '^[a-f0-9]+ feat' | head -20

# Large additions (new feature directories)
git log --diff-filter=A --name-only --format='%H---' -$DEPTH | awk '/^[a-f0-9]+---/{hash=$0;next}{if(hash)print hash,$0}'

# Cluster commits by directory to find feature groups
git log --format='' --name-only -$DEPTH | grep -oP '^[^/]+/[^/]+' | sort | uniq -c | sort -rn | head -15
```

Cross-reference with existing `docs/prds/` to avoid duplicates.

### Step 4: ADR Detection (if --adr or --all)

Find architecture decisions without documentation:

```bash
# Dependency changes
git log --oneline -$DEPTH -- 'package.json' 'Cargo.toml' 'pyproject.toml' 'go.mod'

# Migration/replacement commits
git log --format='%H %s' -$DEPTH | grep -iE 'migrate|switch|replace|upgrade|from .+ to'

# Infrastructure changes
git log --oneline -$DEPTH -- 'docker*' 'Dockerfile*' '.github/workflows/*' 'terraform/*' 'k8s/*'

# Refactors indicating architectural shifts
git log --format='%H %s' -$DEPTH | grep -iE 'refactor.*to|restructure|reorganize|redesign'
```

Cross-reference with existing `docs/adrs/` to avoid duplicates.

### Step 5: PRP Detection (if --prp or --all)

Find implementation work without planning docs:

```bash
# Sequential implementation commits
git log --format='%s' -$DEPTH | grep -iE 'step [0-9]|part [0-9]|phase [0-9]|wip'

# Multi-file coordinated changes
git log --format='%H %s' -$DEPTH | while read hash msg; do
  files=$(git diff-tree --no-commit-id --name-only -r "$hash" 2>/dev/null | wc -l)
  [ "$files" -gt 5 ] && echo "$files files: $msg"
done | sort -rn | head -10

# Feature branches
git branch -a --format='%(refname:short)' | grep -iE 'feat|feature|implement'
```

Cross-reference with existing `docs/prps/` to avoid duplicates.

### Step 6: Plan Refinement Detection (if --refinements or --all)

Find approach changes not documented:

```bash
# Reverts and reworks
git log --format='%H %s' -$DEPTH | grep -iE 'revert|redo|rework|rethink|redesign'

# "Actually" commits (approach corrections)
git log --format='%H %s' -$DEPTH | grep -iE 'actually|instead|better approach|try different'

# High-churn files (approach unclear, iterated heavily)
git log --format='' --name-only -$DEPTH | sort | uniq -c | sort -rn | head -15

# Short-lived implementations (created then significantly changed)
git log --format='%H %ai %s' -$DEPTH | grep -i 'refactor' | head -10
```

### Step 7: Generate Report

Compile findings into a prioritized report:

```markdown
## Documentation Gaps Report

Generated: <date>
Commits analyzed: <N>
Period: <first> to <last>

### High Priority
[Items with strong evidence and high impact]

### Medium Priority
[Items with moderate evidence]

### Low Priority
[Minor patterns or old history items]
```

### Step 8: Create Documents (unless --dry-run)

For each accepted finding:

**Rules**: Create/update `.claude/rules/<name>.md` with:
- Convention description
- Evidence from commits
- Examples

**PRD/ADR/PRP**: Generate skeleton documents in appropriate directories. If blueprint commands are available, suggest using:
- `/blueprint:prd` for PRDs
- `/blueprint:adr` for ADRs
- `/blueprint:prp-create` for PRPs

### Step 9: Summary

Report:
- Number of gaps found per category
- Documents created (if not --dry-run)
- Suggested next steps

## See Also

- **git-log-documentation** skill for detailed detection patterns
- **document-detection** skill (blueprint-plugin) for conversation-based detection
- `/docs:generate --changelog` for changelog generation from commits
