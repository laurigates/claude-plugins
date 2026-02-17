---
model: haiku
name: workflow-preflight
description: |
  Pre-work validation before starting implementation. Use when beginning work
  on an issue, feature, or fix to verify remote state, check for existing PRs,
  detect branch conflicts, and prevent redundant work. Catches problems that
  cause wasted effort: already-merged fixes, stale branches, unclean diffs.
args: "[issue-number|branch-name]"
allowed-tools: Bash(git fetch *), Bash(git status *), Bash(git diff *), Bash(git log *), Bash(git branch *), Bash(git remote *), Bash(git stash *), Bash(gh pr *), Bash(gh issue *), Read, Grep, Glob, TodoWrite
argument-hint: optional issue number or branch name to check
created: 2026-02-08
modified: 2026-02-08
reviewed: 2026-02-08
---

# /workflow:preflight

Pre-work validation to prevent wasted effort from stale state, redundant work, or branch conflicts.

## When to Use This Skill

| Use this skill when... | Skip when... |
|------------------------|-------------|
| Starting work on a new issue or feature | Quick single-file edit |
| Resuming work after a break | Already verified state this session |
| Before spawning parallel agents | Working in an isolated worktree |
| Before creating a branch for a PR | Branch already created and verified |

## Context

- Repo: !`gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null`
- Current branch: !`git branch --show-current 2>/dev/null`
- Remote tracking: !`git branch -vv --format='%(refname:short) %(upstream:short) %(upstream:track)' 2>/dev/null`
- Uncommitted changes: !`git status --porcelain 2>/dev/null`
- Stash count: !`git stash list 2>/dev/null`

## Execution

### Step 1: Fetch Latest Remote State

```bash
git fetch origin --prune 2>/dev/null
```

### Step 2: Check for Existing Work

If an issue number was provided, check if it's already addressed:

```bash
# Check if issue exists and its state
gh issue view $ISSUE --json number,title,state,labels 2>/dev/null

# Check for PRs that reference this issue
gh pr list --search "fixes #$ISSUE OR closes #$ISSUE OR resolves #$ISSUE" --json number,title,state,headRefName 2>/dev/null

# Check for branches that reference this issue
git branch -a --list "*issue-$ISSUE*" --list "*fix/$ISSUE*" --list "*feat/$ISSUE*" 2>/dev/null
```

**If a merged PR exists**: Report that the issue is already addressed. Stop.
**If an open PR exists**: Report the PR and ask if the user wants to continue on that branch or start fresh.

### Step 3: Verify Branch State

```bash
# Check divergence from main/master
git log --oneline origin/main..HEAD 2>/dev/null || git log --oneline origin/master..HEAD 2>/dev/null

# Check if main has moved ahead
git log --oneline HEAD..origin/main -5 2>/dev/null || git log --oneline HEAD..origin/master -5 2>/dev/null

# Check for uncommitted changes
git status --porcelain=v2 --branch 2>/dev/null
```

**Report**:
- Commits ahead/behind remote
- Uncommitted changes that might interfere
- Whether a rebase is needed

### Step 4: Check for Conflicts

```bash
# Dry-run merge to detect conflicts (without actually merging)
git merge-tree $(git merge-base HEAD origin/main) HEAD origin/main 2>/dev/null | head -20
```

### Step 5: Summary Report

Output a structured summary:

| Check | Status | Detail |
|-------|--------|--------|
| Remote state | fresh/stale | Last fetch time |
| Existing PRs | none/open/merged | PR numbers if any |
| Branch state | clean/dirty/diverged | Ahead/behind counts |
| Conflicts | none/detected | Conflicting files |
| Stash | empty/N items | Stash contents |

**Recommendations**:
- If behind remote: "Rebase recommended before starting work"
- If existing PR found: "PR #N already addresses this - review before duplicating"
- If dirty state: "Commit or stash changes before branching"
- If conflicts detected: "Resolve conflicts with main before proceeding"
- If clean: "Ready to proceed"

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick remote sync | `git fetch origin --prune 2>/dev/null` |
| Check existing PRs | `gh pr list --search "fixes #N" --json number,state,headRefName` |
| Branch divergence | `git log --oneline origin/main..HEAD` |
| Conflict detection | `git merge-tree $(git merge-base HEAD origin/main) HEAD origin/main` |
| Compact status | `git status --porcelain=v2 --branch` |
| Remote tracking | `git branch -vv --format='%(refname:short) %(upstream:track)'` |

## Quick Reference

| Flag | Description |
|------|-------------|
| `git fetch --prune` | Fetch and remove stale remote refs |
| `git status --porcelain=v2` | Machine-parseable status |
| `gh pr list --search` | Search PRs by content |
| `gh issue view --json` | Structured issue data |
| `git merge-tree` | Dry-run merge conflict detection |
| `git log A..B` | Commits in B but not A |
