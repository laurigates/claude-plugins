---
name: workflow-preflight
description: Pre-work validation before implementation. Use when starting an issue or fix to verify remote state, check for existing PRs, and detect branch conflicts before coding.
args: "[issue-number|branch-name]"
allowed-tools: Bash(bash *), Bash(git fetch *), Bash(git status *), Bash(git diff *), Bash(git log *), Bash(git branch *), Bash(git remote *), Bash(git stash *), Bash(gh pr *), Bash(gh issue *), Read, Grep, Glob, TodoWrite
argument-hint: optional issue number or branch name to check
created: 2026-02-08
modified: 2026-06-10
reviewed: 2026-06-10
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

- Repo: !`git remote get-url origin`
- Current branch: !`git branch --show-current`
- Remote tracking: !`git branch -vv --format='%(refname:short) %(upstream:short) %(upstream:track)'`
- Uncommitted changes: !`git status --porcelain`
- Stash count: !`git stash list`

## Execution

### Step 1: Run the deterministic preflight check

Pass `--issue <n>` when an issue number was provided:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/workflow-preflight.sh" --home-dir "$HOME" --project-dir "$(pwd)"
```

The script fetches the remote, computes ahead/behind counts, looks up an existing PR / issue / branch for the target, runs a `merge-tree` dry-run for conflicts, inspects uncommitted + stash state, and emits a `RECOMMENDATION=` from the fixed decision tree. Parse `STATUS=` and `ISSUES:` from the output, plus `RECOMMENDATION=`, `EXISTING_PR_STATE=`, `COMMITS_AHEAD=`/`COMMITS_BEHIND=`, `CONFLICTS_DETECTED=`, `UNCOMMITTED_CHANGES=`, and `STASH_COUNT=`.

### Step 2: Decide on an existing open PR

The script reports `EXISTING_PR_STATE=MERGED|OPEN|NONE`:

- **`MERGED`**: the issue is already addressed — stop before duplicating.
- **`OPEN`**: an existing PR already addresses this. Ask the user whether to continue on that branch or start fresh:

  Use **AskUserQuestion** — "Continue on existing PR #N, or start fresh?" — before doing any work. This judgment call stays interactive; the script only surfaces the PR state.
- **`NONE`**: proceed per the script's `RECOMMENDATION=`.

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
