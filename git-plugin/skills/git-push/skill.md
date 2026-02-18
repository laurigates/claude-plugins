---
model: haiku
created: 2026-01-21
modified: 2026-02-18
reviewed: 2026-01-23
name: git-push
description: |
  Push local commits to remote repositories. Handles branch tracking, upstream setup,
  and safe push patterns. Use when user says "push", "push changes", "send to remote",
  "update remote", or similar. This skill pushes existing commits - see git-commit for
  creating commits and git-pr for pull request creation.
allowed-tools: Bash(git status *), Bash(git diff *), Bash(git log *), Bash(git push *), Bash(git branch *), Bash(git remote *), Bash(git rev-list *), Bash(git fetch *), Read, Grep, Glob, TodoWrite
---

# Git Push

Push local commits to remote repositories with proper branch tracking.

## When to Use

**Trigger phrases:**
- "push" / "push changes" / "push commits"
- "send to remote" / "update remote"
- "sync with origin"
- "upload changes"

**Context signals:**
- Local commits exist that aren't on remote
- User has just committed changes
- `git status` shows "Your branch is ahead"
- No mention of "PR" or "pull request"

## Workflow

### 1. Assess Push State

```bash
# Check current branch and tracking
git branch --show-current
git status --porcelain=v2 --branch

# Count commits ahead of remote
git rev-list --count @{upstream}..HEAD 2>/dev/null || echo "no upstream"

# Check remote exists
git remote -v
```

### 2. Determine Push Strategy

**Has upstream tracking:**
```bash
# Simple push to tracked branch
git push
```

**No upstream (new branch, same remote branch name):**
```bash
# Set upstream and push — only use -u when local and remote names match
git push -u origin $(git branch --show-current)
```

**On main, pushing to a differently-named remote branch:**
```bash
# Use explicit refspec — no -u, preserves main's tracking
git push origin main:<remote-branch>
```

**Force push needed (rebased/amended):**
```bash
# CAUTION: Only after explicit user confirmation
git push --force-with-lease
```

### 3. Verify Push

```bash
# Confirm sync status
git status --porcelain=v2 --branch

# Should show: branch.ab +0 -0 (no commits ahead/behind)
```

## Push Patterns

### Standard Push (Default)

For regular commits on a tracked branch:
```bash
git push
```

### Push to Remote Feature Branch (Main-Branch Development)

When on main with commits to push for a PR, push directly to a remote feature branch without creating a local branch:
```bash
# Push main commits to a new remote branch
git push origin main:<remote-branch-name>

# Push specific commit range to a remote branch
git push origin <start>^..<end>:<remote-branch-name>
```

This avoids local branch juggling. After the PR merges, a `git pull` on main syncs cleanly.

### First Push (New Branch)

For branches without upstream, when remote branch name matches local:
```bash
git push -u origin $(git branch --show-current)
```

**Warning:** `-u` binds the current local branch's upstream to the named remote branch. If you're on `main` and want to push to a differently-named feature branch, use the refspec form instead — otherwise `main` will track the feature branch:
```bash
# WRONG while on main — sets main to track origin/feat/foo:
# git push -u origin feat/foo

# CORRECT — push main commits to remote feature branch without changing tracking:
git push origin main:feat/foo
```

### Push with Tags

When commits include version tags:
```bash
git push --follow-tags
```

### Force Push (With Lease)

For rebased or amended commits (requires confirmation):
```bash
# Safer than --force: fails if remote has new commits
git push --force-with-lease
```

## Safety Checks

**Before pushing, verify:**
1. **Branch name** - Avoid pushing directly to main/master
2. **Commit count** - Reasonable number of commits
3. **No uncommitted changes** - Clean working tree
4. **Remote reachable** - Network connectivity

### Main Branch Push Behavior

```bash
branch=$(git branch --show-current)
if [ "$branch" = "main" ] || [ "$branch" = "master" ]; then
  # Main-branch development: push to remote feature branch for PRs
  # git push origin main:<feature-branch>  ← expected workflow

  # Direct push to remote main: warn unless explicitly requested
  # git push origin main  ← requires confirmation
fi
```

## Composability

This skill **pushes commits only**. For full workflows:

| User Intent | Skills Invoked |
|-------------|----------------|
| "push" | git-push only |
| "commit and push" | git-commit → git-push |
| "push and create PR" | git-push → git-pr |
| "commit, push, and PR" | git-commit → git-push → git-pr |
| "create PR" (on main) | git-pr handles push + PR creation automatically |

## Output

On success, report:
```
Pushed to origin/feature-branch
Commits pushed: 3
Branch is now up to date with remote

Ready for: create PR, continue working, or merge
```

## Error Handling

**No upstream configured:**
```
Branch has no upstream. Setting upstream to origin/<branch>
```

**Remote has diverged:**
```
Push rejected: remote contains commits not in local branch.
Options:
1. Pull and merge: git pull
2. Pull and rebase: git pull --rebase
3. Force push (loses remote commits): git push --force-with-lease
```

**Remote unreachable:**
```
Cannot reach remote 'origin'. Check network connection.
```

**Protected branch rejection:**
```
Push rejected: branch 'main' is protected.
Create a feature branch and submit a pull request instead.
```

## Quick Reference

| Scenario | Command |
|----------|---------|
| Standard push | `git push` |
| Main to remote feature branch | `git push origin main:<branch-name>` |
| Commit range to remote branch | `git push origin <start>^..<end>:<branch>` |
| New branch (same local/remote name) | `git push -u origin $(git branch --show-current)` |
| With tags | `git push --follow-tags` |
| After rebase | `git push --force-with-lease` |
| Check ahead count | `git rev-list --count @{upstream}..HEAD` |
| Check tracking | `git branch -vv` |

## Best Practices

1. **Push frequently** - Smaller, incremental pushes are safer
2. **Never force push shared branches** - Coordinate with team first
3. **Use feature branches** - Keep main/master clean
4. **Verify before force push** - Always use `--force-with-lease`
5. **Check CI after push** - Ensure tests pass on remote
