---
model: haiku
name: git-rebase-patterns
description: |
  Advanced git rebase patterns for linear history, stacked PRs, and clean commit management.
  Use when rebasing branches, cleaning up commit history, managing PR stacks, or converting
  merge-heavy branches to linear history. Covers --reapply-cherry-picks, --update-refs, --onto,
  and interactive rebase workflows.
allowed-tools: Bash, Read
created: 2026-01-30
modified: 2026-01-30
reviewed: 2026-01-30
---

# Git Rebase Patterns

Advanced rebase techniques for maintaining linear history, managing stacked PRs, and cleaning up commit history.

## When to Use This Skill

| Use this skill when... | Use something else when... |
|------------------------|---------------------------|
| Rebasing feature branches onto updated main | Creating branches → `git-branch-naming` |
| Cleaning up commit history before PR | Creating PRs → `git-branch-pr-workflow` |
| Managing stacked PRs (PR chains) | Simple commits → `git-commit-workflow` |
| Converting merge-heavy branches to linear | Basic git operations → `git-cli-agentic` |

## Linear History Basics

### Trunk-Based Development

```bash
# Feature branch lifecycle (keep short - max 2 days)
git switch main
git pull origin main
git switch -c feat/user-auth

# Daily rebase to stay current
git switch main && git pull
git switch feat/user-auth
git rebase main

# Interactive cleanup before PR
git rebase -i main
# Squash, fixup, reword commits for clean history

# Push and create PR
git push -u origin feat/user-auth
```

### Squash Merge Strategy

Maintain linear main branch history:

```bash
# Manual squash merge
git switch main
git merge --squash feat/user-auth
git commit -m "feat: add user authentication system

- Implement JWT token validation
- Add login/logout endpoints
- Create user session management

Closes #123"
```

### Interactive Rebase Workflow

Clean up commits before sharing:

```bash
# Rebase last 3 commits
git rebase -i HEAD~3

# Common rebase commands:
# pick   = use commit as-is
# squash = combine with previous commit
# fixup  = squash without editing message
# reword = change commit message
# drop   = remove commit entirely

# Example rebase todo list:
pick a1b2c3d feat: add login form
fixup d4e5f6g fix typo in login form
squash g7h8i9j add form validation
reword j1k2l3m implement JWT tokens
```

## Advanced Rebase Flags

### Reapply Cherry-Picks (`--reapply-cherry-picks`)

**Problem:** After merging trunk into your feature branch multiple times (via `git merge main`), you want to rebase onto fresh trunk. Default rebase behavior may create conflicts or duplicate commits.

**Solution:** `--reapply-cherry-picks` detects commits that were already applied via merge and drops the merge commits, keeping only your original changes.

```bash
# Scenario: You merged main into your branch a few times
git log --oneline
# abc123 Merge branch 'main' into feat/auth
# def456 feat: add login endpoint
# ghi789 Merge branch 'main' into feat/auth
# jkl012 feat: add user validation

# Rebase onto fresh main, dropping merge commits
git fetch origin
git rebase --reapply-cherry-picks origin/main

# Result: Clean linear history with just your feature commits
# jkl012 feat: add user validation
# def456 feat: add login endpoint
```

**When to use:**
- After merging trunk into your branch to resolve conflicts
- Converting a merge-heavy branch to linear history
- Before creating a PR to clean up integration merges

### Update Refs (`--update-refs`)

**Problem:** With stacked PRs (PR chains), rebasing one branch requires manually rebasing all dependent branches. Moving commits between branches in the stack is painful.

**Solution:** `--update-refs` automatically updates all branches in the chain when you rebase. Combined with interactive rebase, you can reorganize commits across your entire PR stack in one operation.

```bash
# Scenario: Stacked PRs
# main <- feat/auth-base <- feat/auth-oauth <- feat/auth-refresh

# Rebase the entire stack onto updated main
git switch feat/auth-refresh
git rebase --update-refs main

# All three branches (auth-base, auth-oauth, auth-refresh) are updated
# No manual rebasing of each branch needed

# Interactive rebase to move commits between branches
git rebase -i --update-refs main

# In the editor, move commit lines around to reorganize the stack:
# pick abc123 feat: add auth base      # Will update feat/auth-base
# pick def456 feat: add OAuth support  # Will update feat/auth-oauth
# pick ghi789 feat: add token refresh  # Will update feat/auth-refresh
```

**Stacked PR workflow with update-refs:**

```bash
# Create PR stack
git switch main
git pull origin main

# First PR: Base authentication
git switch -c feat/auth-base
# ... make commits ...
git push -u origin feat/auth-base

# Second PR: OAuth (depends on first)
git switch -c feat/auth-oauth
# ... make commits ...
git push -u origin feat/auth-oauth

# Third PR: Token refresh (depends on second)
git switch -c feat/auth-refresh
# ... make commits ...
git push -u origin feat/auth-refresh

# Main updated - rebase entire stack
git fetch origin
git switch feat/auth-refresh
git rebase --update-refs origin/main

# All branches rebased in one command
git push --force-with-lease origin feat/auth-base
git push --force-with-lease origin feat/auth-oauth
git push --force-with-lease origin feat/auth-refresh
```

**When to use:**
- Managing stacked PRs (PR chains with dependencies)
- Reorganizing commits across multiple branches
- Keeping branch hierarchies in sync during rebase

### Explicit Base Control (`--onto`)

**Problem:** Git's automatic base detection can be ambiguous or incorrect. You want precise control over where commits are rebased.

**Solution:** `--onto` explicitly specifies the new base, bypassing Git's base detection heuristics.

```bash
# Syntax: git rebase --onto <newbase> <upstream> <branch>
# Translates to: Take commits from <upstream>..<branch> and put them onto <newbase>

# Common pattern: Rebase last N commits onto a specific branch
git rebase --onto origin/develop HEAD~5
# Takes your last 5 commits and puts them on top of origin/develop
# Equivalent to: git rebase --onto origin/develop HEAD~5 HEAD

# Example: Move feature commits from old base to new base
# Scenario: You branched from develop, but should have branched from main
git switch feat/payment
git rebase --onto main develop feat/payment
# Takes commits from develop..feat/payment and moves them onto main

# Example: Rebase specific commit range
# Move commits from abc123 to def456 onto main
git rebase --onto main abc123^ def456
# The ^ includes abc123 in the range

# Example: Extract commits to new branch
# You have commits on feat/auth that should be on separate branch
git switch -c feat/auth-ui feat/auth  # Create new branch
git rebase --onto main feat/auth~3 feat/auth-ui
# Takes last 3 commits from feat/auth and puts them on main
```

**Common --onto patterns:**

| Pattern | Command | Use Case |
|---------|---------|----------|
| Last N commits on trunk | `git rebase --onto origin/main HEAD~N` | Rebase recent work onto updated trunk |
| Change branch base | `git rebase --onto <new-base> <old-base>` | Fix branch created from wrong base |
| Extract commit range | `git rebase --onto <target> <start>^ <end>` | Move specific commits to new location |
| Interactive with onto | `git rebase -i --onto <base> HEAD~N` | Clean up and rebase last N commits |

**When to use:**
- When you don't trust Git's automatic base detection
- Rebasing a specific number of recent commits (`HEAD~N` pattern)
- Changing the base of a branch after it was created
- Extracting a subset of commits to a new location

### Combining Advanced Flags

These flags work together for powerful workflows:

```bash
# Rebase stacked PRs with cherry-pick detection
git rebase --reapply-cherry-picks --update-refs origin/main

# Interactive rebase with explicit base and branch updates
git rebase -i --onto origin/main HEAD~10 --update-refs

# Clean up merged history and update dependent branches
git rebase --reapply-cherry-picks --update-refs --onto origin/develop origin/main
```

## Conflict Resolution

```bash
# When rebase conflicts occur
git rebase main
# Fix conflicts in editor
git add resolved-file.txt
git rebase --continue

# If rebase gets messy, abort and merge instead
git rebase --abort
git merge main
```

## Safe Force Pushing

```bash
# Always use --force-with-lease to prevent overwriting others' work
git push --force-with-lease origin feat/branch-name

# Never force push to main/shared branches
# Use this alias for safety:
git config alias.pushf 'push --force-with-lease'
```

## Quick Reference

| Operation | Command |
|-----------|---------|
| Rebase onto main | `git rebase main` |
| Interactive rebase | `git rebase -i HEAD~N` |
| Rebase with cherry-pick cleanup | `git rebase --reapply-cherry-picks origin/main` |
| Rebase stacked PRs | `git rebase --update-refs main` |
| Rebase last N commits | `git rebase --onto origin/main HEAD~N` |
| Change branch base | `git rebase --onto <new> <old>` |
| Abort failed rebase | `git rebase --abort` |
| Continue after conflict | `git rebase --continue` |
| Skip problematic commit | `git rebase --skip` |

## Troubleshooting

### Rebase Conflicts Are Too Complex

```bash
# Abort rebase and use merge instead
git rebase --abort
git merge main
```

### Branch Diverged from Remote

```bash
# Pull with rebase to maintain linear history
git pull --rebase origin feat/branch-name

# Or reset if local changes can be discarded
git fetch origin
git reset --hard origin/feat/branch-name
```

### Lost Commits After Rebase

```bash
# Find lost commits in reflog
git reflog

# Restore to previous state
git reset --hard HEAD@{N}
```
