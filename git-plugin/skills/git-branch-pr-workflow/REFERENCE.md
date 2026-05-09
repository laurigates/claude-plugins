# Git Branch PR Workflow — Reference

Detailed troubleshooting, safe-operation guidelines, and recovery workflows for `git-branch-pr-workflow`.

## Troubleshooting

### Branch Diverged from Remote

```bash
# Pull with rebase to maintain linear history
git pull --rebase origin feat/branch-name
```

**Note:** `git reset --hard` is rarely needed. Most "diverged" states resolve cleanly with `git pull`.

### Committed to Main (Expected Workflow)

With main-branch development, committing to main is the expected workflow:

```bash
# Commits are already on main - just push to remote feature branch
git push origin main:feat/new-feature

# Create PR using GitHub MCP (head: feat/new-feature, base: main)

# After PR is merged, local main resolves itself:
git pull origin main  # Fast-forward merge handles this cleanly
```

**Why `git pull` works (no reset needed):**
- Commits exist on both local main and remote feature branch
- When PR merges to remote main, your local main is behind by the same commits
- `git pull` recognizes the commits and fast-forwards cleanly
- No history rewriting, no data loss, no merge conflicts

**After pushing to a PR branch:** Wait for the PR to merge, then use `git pull` to sync automatically.

### Rebase Conflicts Are Too Complex

```bash
# Abort rebase and use merge instead
git rebase --abort
git merge main
```

## Safe Operations

### Recognizing Normal States

These states are expected during development - proceed confidently:

| State | Meaning | Action |
|-------|---------|--------|
| Unstaged changes after pre-commit | Formatters modified files | Stage with `git add -u` and continue |
| Modified files after running formatters | Expected auto-fix behavior | Stage before committing |
| Pre-commit exit code 1 | Files were modified | Stage modifications, re-run pre-commit |
| Branch behind remote | Remote has newer commits | Pull or rebase as appropriate |

### Confirmation-Required Commands

Request user confirmation before running destructive commands:

```bash
# These require explicit user approval:
git branch -d/-D       # "Delete local branch X?"
git push origin --delete  # "Delete remote branch X?"
git reset --hard       # "Discard uncommitted changes?"
git clean -fd          # "Remove untracked files?"
```

### When State is Unclear

When encountering unexpected state:
1. Run diagnostic commands (`git status`, `git log --oneline -5`)
2. Report findings clearly
3. Present options and wait for guidance

## Recovery Workflows

### Pre-commit Modifies Files

This is normal formatter/linter behavior:

```bash
# 1. Check what changed
git status

# 2. Stage modified files
git add -u

# 3. Continue with commit
git commit -m "feat(feature): description"
```

### Push Rejected (Non-Fast-Forward)

Remote has newer commits:

```bash
# Option 1: Rebase local changes on top (preferred for linear history)
git pull --rebase origin <branch>

# Option 2: Merge remote changes
git pull origin <branch>

# Option 3: Overwrite remote (your branch only, use cautiously)
git push --force-with-lease
```

### Commit Fails

1. Read the error message
2. Common causes:
   - Pre-commit hooks failed → Fix issues and retry
   - No staged changes → Stage files first
   - Empty commit message → Provide message
3. Fix the underlying issue and retry
