---
created: 2026-03-02
modified: 2026-06-14
reviewed: 2026-06-10
name: git-fork-workflow
description: "Fork management and upstream sync. Use when working with forks, syncing with upstream, detecting divergence, or preparing commits for contribution."
allowed-tools: Bash(bash *), Bash(git remote *), Bash(git fetch *), Bash(git log *), Bash(git status *), Bash(git diff *), Bash(git rev-list *), Bash(gh repo *), Read, Grep, Glob
---

# Git Fork Workflow

Expert guidance for managing forked repositories, synchronizing with upstream, and contributing back cleanly.

## Data-Gathering Script

Run this first to detect the upstream remote, compute ahead/behind via
`git rev-list`, and get a **recommended** sync strategy (a pure function — it
runs no mutations):

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/git-fork-workflow.sh" --home-dir "$HOME" --project-dir "$(pwd)"
```

Parse `STATUS=` and `ISSUES:` from the output. It emits `IS_FORK`,
`UPSTREAM` / `ORIGIN`, `BEHIND` / `AHEAD` (from
`git rev-list --left-right --count upstream/main...origin/main`), and
`RECOMMENDED_STRATEGY` (one of `in-sync`, `fast-forward`, `ahead-only`,
`rebase`, `not-a-fork`). The strategy is a recommendation only — **executing
any destructive sync (reset, rebase, force-push) stays your call**, per the
strategy prose below.

## When to Use This Skill

| Use this skill when... | Use git-upstream-pr instead when... |
|------------------------|-------------------------------------|
| Understanding fork remote architecture | Ready to submit a PR to upstream |
| Diagnosing fork divergence from upstream | Need step-by-step PR creation workflow |
| Syncing fork's main with upstream | Cherry-picking specific commits for upstream |
| Deciding on a sync strategy | Creating a cross-fork PR via `gh` CLI |
| Contributing from an environment that can't reach upstream | Upstream is directly reachable for a normal cross-fork PR |

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

The data-gathering script (above) fetches both remotes and computes the
ahead/behind counts — read `BEHIND` and `AHEAD` from its output. To view the
specific divergent commits behind those counts:

```bash
# Show divergent commits
git log --oneline upstream/main..origin/main   # Commits on fork not on upstream
git log --oneline origin/main..upstream/main   # Commits on upstream not on fork
```

### Reading the Counts

The script's `BEHIND` / `AHEAD` come from
`git rev-list --left-right --count upstream/main...origin/main`:

| `BEHIND` `AHEAD` | Meaning |
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

The script's `RECOMMENDED_STRATEGY` maps the `BEHIND`/`AHEAD` counts to a
strategy keyword via a pure function; use it as the starting point and confirm
against this table before running any destructive command:

| `RECOMMENDED_STRATEGY` | Situation | Strategy |
|---|-----------|----------|
| `in-sync` | 0 behind, 0 ahead | Nothing to do |
| `fast-forward` | Behind only, fork main clean | Fast-forward or `gh repo sync` |
| `ahead-only` | Ahead only, nothing to pull | No sync needed; fork leads upstream |
| `rebase` | Diverged, unique work worth keeping | Rebase (Strategy 4) |
| _(diverged, work expendable)_ | Unique work expendable / match upstream exactly | Hard reset (Strategy 3) |
| _(unsure)_ | Not sure | Try fast-forward first; it fails safely if diverged |

The recommendation never executes a sync — picking and running Strategy 3
(hard reset) or 4 (rebase + force-push) stays your decision.

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

## Fork-Main as an Upstream Staging Area

When the environment **cannot reach upstream directly** — e.g. a Claude Code session whose repository scope only includes your fork, so issues/PRs against `owner/repo` are denied — don't let that block development. Stage the contribution in your fork's `main`, then resubmit upstream from a session that can reach it.

### The pattern

1. **Stage in the fork.** Branch (ideally from `upstream/main`), implement, open a PR into your **fork's** `main`, self-review, and merge. The change is now landed and usable immediately, independent of upstream reachability.
2. **Contain the divergence.** Merging into fork `main` diverges it from `upstream/main` (different SHAs — the [Divergence Problem](#the-divergence-problem) above). That is the accepted cost of staging. Keep it bounded by periodically pulling `upstream/main` back in (rebase or merge) so the fork doesn't rot.
3. **Resubmit cleanly — never PR `fork:main → upstream:main`.** That drags every staged commit plus the divergence into one PR. Instead, from a session that can reach upstream, branch fresh from `upstream/main` and **cherry-pick only the one contribution's commit(s)**, then open the cross-fork PR (syntax below). Each upstream PR stays atomic and reviewable — what maintainers actually accept.
4. **Track upstream status.** Stamp staged commits so a later session knows what still needs a PR:

   ```
   Upstream-status: pending          # staged in fork, not yet submitted
   Upstream-PR: https://github.com/owner/repo/pull/NN   # once submitted
   ```

   List what's still pending with `git log --grep='Upstream-status: pending' upstream/main..origin/main`.

### When to use vs. the Golden Rule

| Situation | Approach |
|-----------|----------|
| You can reach upstream now | Branch from `upstream/main`, open the cross-fork PR directly (Golden Rule above) |
| You cannot reach upstream from this environment | Stage in fork `main` now; cherry-pick onto an `upstream/main` branch and PR later |

The staging pattern is the Golden Rule deferred — it still ends with a clean `upstream/main`-based branch; it just buys you an unblocked checkpoint in between.

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
