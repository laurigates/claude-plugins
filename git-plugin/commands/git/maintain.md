---
allowed-tools: Bash, Read, Glob, TodoWrite
argument-hint: [--prune] [--gc] [--verify] [--branches] [--stash] [--all]
description: Perform repository maintenance and cleanup
---

## Context

- Current branch: !`git branch --show-current`
- Git status: !`git status --short`
- Local branches: !`git branch -vv`
- Stash list: !`git stash list`
- Repository size: !`du -sh .git`

## Parameters

Parse these parameters from the command (all optional):

- `--prune`: Remove unreachable objects and optimize repository
- `--gc`: Run git garbage collection (aggressive)
- `--verify`: Verify integrity of git objects
- `--branches`: Clean up merged branches only
- `--stash`: Clean up stashes only
- `--all`: Run all maintenance tasks (default if no flags specified)

## Your task

Perform repository maintenance and cleanup based on the flags provided.

### Step 1: Check for accidentally committed files

- Environment files, IDE files, dependencies, build artifacts, secrets
- Suggest adding to `.gitignore` and removing with `git rm --cached`

### Step 2: Update .gitignore

- Suggest common patterns if missing
- Offer to append missing patterns

### Step 3: Delete merged branches (if --branches or --all)

- List and clean branches merged via GitHub PR
- Protect main, master, develop, staging, production
- Delete local branches safely with `git branch -d`
- **Require user confirmation** before deleting branches

### Step 4: Clean up redundant stashes (if --stash or --all)

- Show stash ages and context
- Suggest cleanup for old stashes (>30 days)
- Drop stashes from deleted branches
- **Require user confirmation** before dropping stashes

### Step 5: Repository optimization (if --prune, --gc, or --all)

```bash
# Prune unreachable objects
git prune

# Run garbage collection
git gc --aggressive

# Repack objects
git repack -ad

# Show size improvement
du -sh .git
```

### Step 6: Verify repository integrity (if --verify or --all)

```bash
git fsck --full --strict
```

Report any issues found.

### Step 7: Final summary

- Report all actions taken
- Show before/after metrics

## Safe Operations

These operations are safe and non-destructive:
- `git gc` - Garbage collection
- `git prune` - Prune unreachable objects
- `git fsck` - Verify integrity

These require user confirmation:
- `git branch -d` - Delete branches
- `git stash drop` - Drop stashes

## See Also

- **git-branch-pr-workflow** skill for branch management patterns
