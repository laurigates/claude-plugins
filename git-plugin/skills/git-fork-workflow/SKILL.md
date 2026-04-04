---
created: 2026-03-02
modified: 2026-03-02
reviewed: 2026-03-02
name: git-fork-workflow
description: |
  Fork management and upstream synchronization. Use when working with forked
  repositories, syncing fork with upstream, managing divergence between fork
  and upstream, or preparing commits for upstream contribution. Covers remote
  architecture, divergence detection, sync strategies, and cross-fork PRs.
  For creating upstream PRs, see git-upstream-pr.
allowed-tools: Bash(git remote *), Bash(git fetch *), Bash(git log *), Bash(git status *), Bash(git diff *), Bash(git rev-list *), Bash(gh repo *), Read, Grep, Glob
---

# Git Fork Workflow

Expert guidance for managing forked repositories, synchronizing with upstream, and contributing back cleanly.

## When to Use This Skill

| Use this skill when... | Use git-upstream-pr instead when... |
|------------------------|-------------------------------------|
| Understanding fork remote architecture | Ready to submit a PR to upstream |
| Diagnosing fork divergence from upstream | Need step-by-step PR creation workflow |
| Syncing fork's main with upstream | Cherry-picking specific commits for upstream |
| Deciding on a sync strategy | Creating a cross-fork PR via `gh` CLI |

## Remote Architecture

Forks use two remotes:

| Remote | Points To | Purpose |
|--------|-----------|---------|
| `origin` | Your fork (`you/repo`) | Push your work here |
| `upstream` | Original repo (`owner/repo`) | Pull updates from here |

### Setup

```bash
# Verify remotes
git remote -v

# Add upstream if missing
git remote add upstream https://github.com/owner/original-repo.git

# Verify
git fetch upstream
git remote -v
```

### Identifying Fork vs Upstream

```bash
# Check if upstream remote exists
git remote get-url upstream

# Get fork owner
git remote get-url origin | sed -E 's#.*github\.com[:/]##; s#\.git$##'

# Get upstream owner
git remote get-url upstream | sed -E 's#.*github\.com[:/]##; s#\.git$##'
```

## The Divergence Problem

When you squash-merge branches into your fork's main, the commit SHAs differ from upstream's commits. This creates divergence even when the code content is identical.

### Detecting Divergence

```bash
# Fetch latest from both remotes
git fetch origin
git fetch upstream

# Count ahead/behind
git rev-list --left-right --count upstream/main...origin/main

# Show divergent commits
git log --oneline upstream/main..origin/main   # Commits on fork not on upstream
git log --oneline origin/main..upstream/main   # Commits on upstream not on fork
```

### Reading the Output

`git rev-list --left-right --count upstream/main...origin/main` returns two numbers:

| Output | Meaning |
|--------|---------|
| `0  0` | Perfectly in sync |
| `5  0` | Fork is 5 behind upstream (upstream has 5 new commits) |
| `0  3` | Fork is 3 ahead (fork has 3 commits not on upstream) |
| `5  3` | Diverged: upstream has 5 new, fork has 3 unique |

## Sync Strategies

### Strategy 1: GitHub CLI Sync (Simplest)

```bash
# Syncs fork's default branch with upstream via GitHub API
gh repo sync owner/fork-repo

# Then pull locally
git pull origin main
```

Best when: fork has no unique commits worth preserving on main.

### Strategy 2: Fast-Forward Merge (Clean Canary)

```bash
git fetch upstream
git merge --ff-only upstream/main
```

Best when: fork's main has not diverged. Fails cleanly if diverged (no messy merge commits).

### Strategy 3: Hard Reset (Force Sync)

```bash
git fetch upstream
git reset --hard upstream/main
git push --force-with-lease origin main
```

Best when: fork's main has diverged and you want to discard fork-only commits. **Destructive** - ensure no unique work is on main.

### Strategy 4: Rebase (Preserve Fork Work)

```bash
git fetch upstream
git rebase upstream/main
git push --force-with-lease origin main
```

Best when: fork has unique commits on main that should sit on top of upstream's history.

### Strategy Selection

| Situation | Strategy |
|-----------|----------|
| Fork main is clean, no unique commits | Fast-forward or `gh repo sync` |
| Fork main diverged, unique work expendable | Hard reset |
| Fork main diverged, unique work worth keeping | Rebase |
| Just want to match upstream exactly | Hard reset |
| Not sure | Try fast-forward first; it fails safely if diverged |

## Golden Rule for Upstream PRs

**Branch from `upstream/main`, not from your fork's main.** This completely bypasses fork divergence:

```bash
git fetch upstream
git switch -c feat/my-contribution upstream/main
# Cherry-pick, code, or apply changes here
git push -u origin feat/my-contribution
# Create cross-fork PR targeting upstream
```

See [git-upstream-pr](../git-upstream-pr/SKILL.md) for the complete workflow.

## Cross-Fork PR Syntax

```bash
# Create PR from fork branch to upstream repo
gh pr create \
  --repo owner/upstream-repo \
  --base main \
  --head your-username:feat/branch-name \
  --title "feat: description" \
  --body "PR description"
```

The `--head` must include the fork owner prefix (`your-username:branch`) when targeting a different repository.

## Common Patterns

### Check if Working in a Fork

```bash
# Has upstream remote = likely a fork
git remote get-url upstream 2>/dev/null && echo "Fork" || echo "Not a fork"
```

### Periodic Sync Workflow

```bash
# Weekly sync routine
git fetch upstream
git switch main
git merge --ff-only upstream/main || echo "Diverged - manual sync needed"
git push origin main
```

### View Upstream Changes Since Last Sync

```bash
git fetch upstream
git log --oneline origin/main..upstream/main
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Divergence count | `git rev-list --left-right --count upstream/main...origin/main` |
| Fork ahead commits | `git log --oneline --format='%h %s' upstream/main..origin/main` |
| Fork behind commits | `git log --oneline --format='%h %s' origin/main..upstream/main` |
| Quick sync check | `git fetch upstream && git merge --ff-only upstream/main` |
| Remote listing | `git remote -v` |

## Related Skills

- [git-upstream-pr](../git-upstream-pr/SKILL.md) - Submit clean PRs to upstream repositories
- [git-branch-pr-workflow](../git-branch-pr-workflow/SKILL.md) - General branch and PR workflow patterns
- [git-rebase-patterns](../git-rebase-patterns/SKILL.md) - Advanced rebase techniques
- [git-conflicts](../git-conflicts/SKILL.md) - Resolve cherry-pick and merge conflicts
- [git-repo-detection](../git-repo-detection/SKILL.md) - Remote URL parsing patterns
