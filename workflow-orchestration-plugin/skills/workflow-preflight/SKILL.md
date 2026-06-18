---
name: workflow-preflight
description: Pre-work validation before implementation. Use when starting an issue or fix to verify remote state, check for existing PRs, and detect branch conflicts before coding.
args: "[issue-number|branch-name]"
allowed-tools: Bash(bash *), Bash(git fetch *), Bash(git status *), Bash(git diff *), Bash(git log *), Bash(git branch *), Bash(git remote *), Bash(git stash *), Bash(gh pr *), Bash(gh issue *), Read, Grep, Glob, TodoWrite
argument-hint: optional issue number or branch name to check
created: 2026-02-08
modified: 2026-06-18
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

- Repo: !`git remote -v`
- Current branch: !`git branch --show-current`
- Remote tracking: !`git branch -vv --format='%(refname:short) %(upstream:short) %(upstream:track)'`
- Uncommitted changes: !`git status --porcelain`
- Stash count: !`git stash list`

## Execution

Run the preflight check, then apply judgment to its results.

### Step 1: Gather preflight state

Invoke the gatherer. Pass `--issue <n>` or `--branch <name>` when the argument
is a GitHub issue number or branch:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/preflight.sh" --project-dir "$(pwd)" [--issue N] [--branch NAME]
```

The script fetches `origin --prune`, resolves the base ref (`origin/main` →
`origin/master` → `main` → `master`), and emits a structured `KEY=VALUE` block:
`AHEAD` / `BEHIND` divergence, `UNCOMMITTED` / `STASH_COUNT`, `CONFLICTS`
(+ `CONFLICT_FILES`), existing-work lookups (`ISSUE_STATE`, `EXISTING_PRS`,
`BRANCH_MATCHES`), and a fixed `RECOMMENDATION`. It degrades gracefully when
`gh` is unavailable (`GH_AVAILABLE=false`) and never fails on network errors.
Pass `--base <ref>` to override the comparison ref, `--no-fetch` to skip the
network round-trip.

### Step 2: Act on existing work (judgment)

Read `EXISTING_PRS` (`#N:STATE:headRef` entries) and `RECOMMENDATION`:

- **`RECOMMENDATION=already-addressed`** (a `:MERGED:` PR exists): report that
  the issue is already addressed and **stop** — do not duplicate the work.
- **`RECOMMENDATION=existing-pr`** (an `:OPEN:` PR exists): report the PR and
  **ask the user** whether to continue on that branch or start fresh
  (`AskUserQuestion`). Do not pick for them.
- Otherwise continue to the summary.

### Step 3: Summary report

Translate the `KEY=VALUE` block into a summary the user can act on:

| Check | Source key | Detail |
|-------|-----------|--------|
| Remote state | `FETCH` | `ok` / `skipped` / `no-remote` |
| Existing PRs | `EXISTING_PRS` | PR numbers + state, if any |
| Branch state | `AHEAD` / `BEHIND` / `UNCOMMITTED` | ahead/behind counts, dirty tree |
| Conflicts | `CONFLICTS` / `CONFLICT_FILES` | conflicting files |
| Stash | `STASH_COUNT` | number of stash entries |

Lead with the headline `RECOMMENDATION`, then surface every relevant note —
the recommendation is a single first-match headline, but multiple conditions
can be worth mentioning:

| `RECOMMENDATION` | Tell the user |
|------------------|---------------|
| `resolve-conflicts` | Resolve conflicts with the base ref before proceeding |
| `commit-or-stash` | Commit or stash changes before branching |
| `rebase` | Rebase on the base ref before starting work |
| `existing-pr` | A PR already addresses this — review before duplicating |
| `already-addressed` | A merged PR already addresses this — stop |
| `ready` | Ready to proceed |

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Full preflight (default) | `bash "${CLAUDE_SKILL_DIR}/scripts/preflight.sh" --project-dir "$(pwd)"` |
| Preflight for an issue | `bash "${CLAUDE_SKILL_DIR}/scripts/preflight.sh" --issue N` |
| Offline / no network | `bash "${CLAUDE_SKILL_DIR}/scripts/preflight.sh" --no-fetch` |
| Override base ref | `bash "${CLAUDE_SKILL_DIR}/scripts/preflight.sh" --base origin/develop` |

The script wraps `git fetch --prune`, `git rev-list --left-right --count`,
`git merge-tree --write-tree`, `git stash list`, and the `gh` existing-work
lookups behind one structured-output call. See
[`scripts/preflight.sh`](scripts/preflight.sh).

## Quick Reference

| Flag | Description |
|------|-------------|
| `git fetch --prune` | Fetch and remove stale remote refs |
| `git status --porcelain=v2` | Machine-parseable status |
| `gh pr list --search` | Search PRs by content |
| `gh issue view --json` | Structured issue data |
| `git merge-tree` | Dry-run merge conflict detection |
| `git log A..B` | Commits in B but not A |
