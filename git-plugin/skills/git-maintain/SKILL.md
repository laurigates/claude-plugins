---
created: 2025-12-16
modified: 2026-07-04
reviewed: 2026-07-04
allowed-tools: Bash(git status *), Bash(git branch *), Bash(git stash *), Bash(git prune *), Bash(git gc *), Bash(git repack *), Bash(git maintenance *), Bash(git fsck *), Bash(git rm *), Bash(du *), Read, Glob, TodoWrite
args: "[--prune] [--gc] [--background] [--verify] [--branches] [--stash] [--all]"
argument-hint: "[--prune] [--gc] [--background] [--verify] [--branches] [--stash] [--all]"
disable-model-invocation: true
description: "Repo maintenance — incremental repack, gc, branch pruning, stash cleanup, fsck. Use when asked to clean up the repo, run git maintenance/gc, delete merged branches, prune stashes, or shrink .git."
name: git-maintain
---

## When to Use This Skill

| Use this skill when... | Use the alternative when... |
|---|---|
| Running `git gc`, repacking objects, or shrinking the `.git` directory | Use `git-coworker-check` first if other agents may be writing to the same checkout |
| Pruning merged local branches and old stashes | Use `git-cli-agentic` for read-only branch/stash queries without mutating state |
| Verifying repo integrity with `git fsck` | Use `git-security-checks` for secret scanning rather than object integrity |
| Cleaning up a checkout before a long-lived feature branch goes stale | Use `git-rebase-patterns` to clean up commit history rather than the object store |

## Context

- Current branch: !`git branch --show-current`
- Git status: !`git status --porcelain=v2 --branch`
- Local branches: !`git branch -vv --format='%(refname:short) %(upstream:short) %(upstream:track)'`
- Stash list: !`git stash list`
- Repository size: !`du -sh .git`

## Parameters

Parse these parameters from the command (all optional):

- `--prune`: Remove unreachable objects and run an incremental geometric repack
- `--gc`: Force a full `git gc` consolidation (only when a repo has degraded badly — prefer the incremental repack)
- `--background`: Register the repo for hourly background maintenance (`git maintenance start`) instead of a blocking one-shot pass
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

### Step 5: Repository optimization (if --prune, --gc, --background, or --all)

**Prefer incremental maintenance over `gc --aggressive`.** Modern Git (2.31+)
replaced the blocking, rewrite-everything `git gc --aggressive` pass with
`git maintenance` and **geometric repacking**, which organizes packfiles in
logarithmic layers by object count. Geometric repacking is the default for
manual maintenance in recent Git (2.52+) and avoids the destructive,
time-consuming "all-in-one" repack. Default to it.

```bash
# Incremental geometric repack — logarithmic pack layering + on-disk
# multi-pack index; far cheaper than `gc --aggressive`, safe to run often
git repack --geometric=2 -d --write-midx

# Prune unreachable objects older than the default grace window
git prune --expire=2.weeks.ago

# Show size improvement
du -sh .git
```

For hands-off upkeep (`--background`), register the repo so Git quietly
pre-fetches, optimizes the commit-graph, and repacks loose objects on a
schedule instead of blocking on a manual pass:

```bash
# Register hourly background maintenance (one-time, per repo)
git maintenance start

# Or run the standard task set once, on demand (non-blocking, incremental)
git maintenance run --task=commit-graph --task=incremental-repack --task=loose-objects
```

Reserve a full `git gc` for a repo that has genuinely degraded (only with
`--gc`); skip `--aggressive` unless a one-off deep repack is explicitly needed:

```bash
# Full consolidation — only when --gc is requested and the repo is degraded
git gc
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
- `git repack --geometric=2 -d --write-midx` - Incremental geometric repack (preferred)
- `git maintenance run` / `git maintenance start` - Incremental background upkeep
- `git gc` - Full garbage collection (reserve for degraded repos)
- `git prune` - Prune unreachable objects
- `git fsck` - Verify integrity

These require user confirmation:
- `git branch -d` - Delete branches
- `git stash drop` - Drop stashes

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Routine optimize | `git repack --geometric=2 -d --write-midx` |
| Hands-off upkeep | `git maintenance start` |
| One-shot incremental pass | `git maintenance run --task=incremental-repack --task=commit-graph` |
| Integrity check | `git fsck --full --strict` |
| Size before/after | `du -sh .git` |

## See Also

- **git-branch-pr-workflow** skill for branch management patterns
