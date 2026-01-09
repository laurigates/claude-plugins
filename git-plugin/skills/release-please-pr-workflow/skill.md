---
created: 2026-01-09
modified: 2026-01-09
reviewed: 2026-01-09
name: release-please-pr-workflow
description: |
  Manages release-please PR merging workflow for monorepos. Handles batch merging,
  conflict resolution through PR closure/recreation, and iterative processing until
  all PRs are merged. Use when merging release PRs, handling PR conflicts, or
  managing release automation in monorepos.
allowed-tools: Bash, Read, TodoWrite
---

# Release-Please PR Workflow

Expert knowledge for managing release-please PRs in monorepos, including batch merging, conflict handling, and iterative processing.

## Core Workflow

Release-please creates separate PRs per component in monorepos (when `separate-pull-requests: true`). These PRs often need sequential merging due to shared manifest file updates.

### Iterative Merge Process

1. **List pending PRs** with status
2. **Merge clean PRs** (MERGEABLE status)
3. **Handle conflicting PRs** (close for recreation)
4. **Wait for recreation** and repeat
5. **Verify completion** when no PRs remain

## Essential Commands

### List Release PRs

```bash
# List all pending release PRs
gh pr list --label "autorelease: pending"

# With merge status details
gh pr list --label "autorelease: pending" --json number,title,mergeable,mergeStateStatus

# Check specific PR status
gh pr view <number> --json title,mergeable,mergeStateStatus
```

### Check PR Mergeability

| Status | Meaning | Action |
|--------|---------|--------|
| `CLEAN` / `MERGEABLE` | Ready to merge | Merge immediately |
| `UNKNOWN` | GitHub computing | Wait 5-10 seconds, retry |
| `DIRTY` / `CONFLICTING` | Has conflicts | Close and wait for recreation |

### Merge PRs

```bash
# Merge single PR (squash recommended for clean history)
gh pr merge <number> --squash

# Merge multiple clean PRs sequentially
gh pr merge 55 --squash && gh pr merge 56 --squash

# Check result
gh pr list --label "autorelease: pending"
```

### Handle Conflicts

```bash
# Close conflicting PRs with explanation
gh pr close <number> --comment "Closing due to conflicts from merged PRs. Release-please will recreate."

# Trigger workflow (if workflow_dispatch enabled)
gh workflow run release-please.yml

# Otherwise, wait for push trigger or new commit
```

## Conflict Resolution Strategy

### Why Conflicts Occur

Release-please PRs modify `.release-please-manifest.json` which tracks all component versions. When one PR merges:
- The manifest changes
- Other PRs become out of date
- GitHub marks them as conflicting

### Resolution Flow

```
1. Identify conflicting PRs
   ↓
2. Close conflicting PRs with comment
   ↓
3. Wait for release-please to recreate PRs
   (triggered by next push or workflow run)
   ↓
4. New PRs appear with updated base
   ↓
5. Merge clean PRs, repeat if needed
```

### Typical Iteration Pattern

```bash
# Round 1: Initial merge
gh pr list --label "autorelease: pending" --json number,mergeable,mergeStateStatus
# Merge CLEAN ones, note CONFLICTING ones

# Round 2: Close conflicts
gh pr close 45 --comment "Closing for recreation"
gh pr close 46 --comment "Closing for recreation"

# Wait for recreation (5-10 seconds typically)
sleep 5

# Round 3: Check new PRs
gh pr list --label "autorelease: pending" --json number,mergeable,mergeStateStatus
# New PR numbers will appear, merge them

# Repeat until no pending PRs
```

## Complete Merge Workflow

### Full Automation Script Pattern

```bash
# 1. Initial status check
gh pr list --label "autorelease: pending" --json number,title,mergeable,mergeStateStatus

# 2. Wait for GitHub to compute status if UNKNOWN
sleep 5
gh pr list --label "autorelease: pending" --json number,title,mergeable,mergeStateStatus

# 3. Merge clean PRs
for pr in $(gh pr list --label "autorelease: pending" --json number,mergeStateStatus \
  -q '.[] | select(.mergeStateStatus=="CLEAN") | .number'); do
  gh pr merge $pr --squash
done

# 4. Close conflicting PRs
for pr in $(gh pr list --label "autorelease: pending" --json number,mergeStateStatus \
  -q '.[] | select(.mergeStateStatus=="DIRTY") | .number'); do
  gh pr close $pr --comment "Closing for recreation after conflicts"
done

# 5. Wait and repeat until done
sleep 10
gh pr list --label "autorelease: pending"
```

### Interactive Workflow

For complex situations, work iteratively:

```bash
# Check current state
gh pr list --label "autorelease: pending" --json number,title,mergeable,mergeStateStatus

# Merge one by one, checking status between
gh pr merge <number> --squash
gh pr list --label "autorelease: pending" --json number,mergeable,mergeStateStatus

# Handle UNKNOWN status by waiting
sleep 5
gh pr view <number> --json mergeable,mergeStateStatus
```

## Status Interpretation

### mergeStateStatus Values

| Value | Description | Action |
|-------|-------------|--------|
| `CLEAN` | All checks pass, no conflicts | Merge immediately |
| `UNKNOWN` | Status being computed | Wait 5-10 seconds |
| `DIRTY` | Has conflicts | Close PR |
| `BLOCKED` | Branch protection blocking | Check required checks |
| `BEHIND` | Branch is behind base | Update branch or close |

### mergeable Values

| Value | Description |
|-------|-------------|
| `MERGEABLE` | Can be merged |
| `CONFLICTING` | Has merge conflicts |
| `UNKNOWN` | Being calculated |

## Post-Merge Verification

```bash
# Verify all PRs merged
gh pr list --label "autorelease: pending"
# Should return empty

# Check new releases/tags
git fetch --tags
git tag --list --sort=-creatordate | head -10

# Pull latest changes
git pull origin main
```

## Common Issues

### PRs Keep Recreating

**Cause:** Unreleased changes still exist for component
**Check:** `git log --oneline HEAD ^<component>-v<last-version> -- <component>/`
**Solution:** Merge the PR or revert the changes

### Auto-merge Not Working

**Cause:** Repository doesn't have branch protection enabled
**Error:** `Pull request Protected branch rules not configured for this branch`
**Solution:** Use `gh pr merge --squash` without `--auto`

### Workflow Not Triggering

**Cause:** release-please.yml doesn't have `workflow_dispatch`
**Solution:** Wait for next push to main, or make a commit to trigger

### "Already Merged" Message

**Cause:** PR was merged but GitHub CLI cache is stale
**Action:** This is normal, continue with next PR

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick status | `gh pr list --label "autorelease: pending" --json number,mergeStateStatus` |
| Batch merge | `gh pr merge N --squash && gh pr merge M --squash` |
| Close with reason | `gh pr close N --comment "Conflicts"` |
| Wait and check | `sleep 5 && gh pr list --label "autorelease: pending"` |

## Quick Reference

### Command Cheat Sheet

| Task | Command |
|------|---------|
| List pending PRs | `gh pr list --label "autorelease: pending"` |
| Check PR status | `gh pr view N --json mergeable,mergeStateStatus` |
| Merge PR | `gh pr merge N --squash` |
| Close PR | `gh pr close N --comment "reason"` |
| View recent tags | `git tag --sort=-creatordate \| head -10` |
| Check workflow runs | `gh run list --workflow=release-please.yml -L 5` |

### Workflow Labels

| Label | Meaning |
|-------|---------|
| `autorelease: pending` | PR waiting to be merged |
| `autorelease: tagged` | PR merged and release tagged |

## Integration with Other Skills

- **release-please-configuration** - Setting up monorepo config
- **release-please-protection** - Preventing manual edits to managed files
- **git-commit-workflow** - Creating conventional commits that trigger releases
