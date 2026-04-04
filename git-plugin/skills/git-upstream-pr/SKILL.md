---
name: git-upstream-pr
description: |
  Submit clean PRs to upstream repositories from a fork. Use when you need to
  contribute changes back to the original repo, cherry-pick fork commits for
  upstream, or create cross-fork pull requests. Handles branch creation from
  upstream/main, commit selection, squashing, and cross-fork PR creation.
args: "[--commits sha1,sha2] [--branch name] [--upstream owner/repo] [--draft] [--dry-run]"
allowed-tools: Bash(git status *), Bash(git diff *), Bash(git log *), Bash(git remote *), Bash(git fetch *), Bash(git switch *), Bash(git cherry-pick *), Bash(git reset *), Bash(git commit *), Bash(git push *), Bash(git stash *), Bash(git rev-list *), Bash(git rev-parse *), Bash(git branch *), Bash(gh pr *), Bash(gh repo *), Bash(gh auth *), AskUserQuestion, Read, Grep, Glob, TodoWrite
argument-hint: --commits abc123,def456 or --branch feat/my-upstream-pr
disable-model-invocation: true
created: 2026-03-02
modified: 2026-03-02
reviewed: 2026-03-02
---

# /git:upstream-pr

Submit clean, atomic PRs to upstream repositories from fork work.

## When to Use This Skill

| Use this skill when... | Use `/git:commit` instead when... |
|------------------------|-----------------------------------|
| Contributing changes back to the upstream repo | Committing to your own fork/repo |
| Cherry-picking fork commits for upstream PR | Creating a PR within the same repo |
| Fork's main has diverged from upstream | Fork and upstream are in sync |
| Need a clean branch based on upstream/main | Working on a branch already tracking upstream |

## Context

- Current branch: !`git branch --show-current`
- Git status: !`git status --porcelain=v2 --branch`
- Remotes: !`git remote -v`
- Has upstream: !`git remote get-url upstream`
- Origin URL: !`git remote get-url origin`
- Upstream URL: !`git remote get-url upstream`
- Recent commits: !`git log --oneline --max-count=20`
- Stash list: !`git stash list`

## Parameters

Parse these from `$ARGUMENTS`:

| Parameter | Required | Description |
|-----------|----------|-------------|
| `--commits sha1,sha2,...` | No | Comma-separated commit SHAs to cherry-pick (interactive selection if omitted) |
| `--branch name` | No | Name for the upstream PR branch (auto-generated if omitted) |
| `--upstream owner/repo` | No | Override upstream repo (detected from remote if omitted) |
| `--draft` | No | Create PR as draft |
| `--dry-run` | No | Show what would happen without making changes |

## Execution

Execute this fork-to-upstream PR workflow:

### Step 1: Validate fork environment

1. Verify this is a git repository: `git rev-parse --git-dir`
2. Check if `upstream` remote exists (from context)
3. If no `upstream` remote:
   - Try to detect via `gh repo view --json parent -q '.parent.nameWithOwner'`
   - If found, add it: `git remote add upstream https://github.com/<owner/repo>.git`
   - If not found, ask user with AskUserQuestion for the upstream repo URL
4. Fetch upstream: `git fetch upstream`
5. Record the current branch name and check for uncommitted changes
6. If uncommitted changes exist, stash them: `git stash push -m "upstream-pr: WIP before upstream PR"`

### Step 2: Assess fork state

Report the fork's divergence from upstream:

```
Fork status:
  Upstream: <upstream-repo>
  Behind upstream/main: N commits
  Ahead of upstream/main: M commits
```

If `--dry-run` is set, also show which commits would be selected and stop here.

### Step 3: Select commits

**If `--commits` provided:**
- Parse the comma-separated SHA list
- Validate each SHA exists: `git rev-parse --verify <sha>`
- Show summary of selected commits

**If `--commits` not provided:**
- Show recent commits that are ahead of upstream/main:
  ```bash
  git log --oneline --format='%h %s (%cr)' upstream/main..HEAD
  ```
- Use AskUserQuestion to let the user select which commits to include
- Present commits as options with their subject lines

### Step 4: Create clean branch from upstream/main

1. Generate branch name if `--branch` not provided:
   - Extract scope from first commit message (e.g., `feat(auth): add OAuth` -> `feat/auth-add-oauth`)
   - Fallback: `upstream-pr/<date>`
2. Create branch from upstream/main:
   ```bash
   git switch -c <branch-name> upstream/main
   ```

### Step 5: Cherry-pick and squash

1. Cherry-pick each selected commit in order:
   ```bash
   git cherry-pick <sha1> <sha2> ...
   ```
2. If cherry-pick conflicts occur:
   - Report the conflict to the user
   - Reference [git-conflicts](../git-conflicts/SKILL.md) for resolution
   - After resolution: `git cherry-pick --continue`
3. Squash all cherry-picked commits into one atomic commit:
   ```bash
   git reset --soft upstream/main
   git commit -m "<conventional commit message>"
   ```
4. Use AskUserQuestion to confirm or edit the commit message
   - Default message: derived from the cherry-picked commits
   - Format: conventional commit with scope

### Step 6: Push to fork

```bash
git push -u origin <branch-name>
```

If `--dry-run`, show the command without executing.

### Step 7: Create cross-fork PR

1. Determine the upstream repo (from `--upstream` or detected remote)
2. Determine the fork owner (from `origin` remote URL)
3. Create the PR:
   ```bash
   gh pr create \
     --repo <upstream-owner/upstream-repo> \
     --base main \
     --head <fork-owner>:<branch-name> \
     --title "<conventional commit title>" \
     --body "<PR description>"
   ```
   Add `--draft` if the flag was provided.
4. Report the PR URL to the user

### Step 8: Restore working state

1. Switch back to the original branch:
   ```bash
   git switch <original-branch>
   ```
2. If changes were stashed in Step 1, pop them:
   ```bash
   git stash pop
   ```
3. Report completion summary:
   ```
   Upstream PR created:
     PR: <url>
     Branch: <branch-name>
     Commits: N cherry-picked, squashed into 1
     Original branch restored: <branch>
   ```

## Error Handling

| Error | Recovery |
|-------|----------|
| Cherry-pick conflict | Show conflicted files, reference git-conflicts skill |
| Push rejected | Check if branch already exists on fork; suggest `--branch` override |
| No upstream remote | Auto-detect from `gh repo view --json parent` or ask user |
| Upstream/main not found | Try `upstream/master`; ask user for correct branch name |
| No commits ahead of upstream | Report "Nothing to contribute" and exit |

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Divergence check | `git rev-list --left-right --count upstream/main...HEAD` |
| Commits ahead | `git log --oneline --format='%h %s' upstream/main..HEAD` |
| Validate SHA | `git rev-parse --verify --short <sha>` |
| Fork owner | `git remote get-url origin \| sed -E 's#.*github.com[:/]##; s#\.git$##; s#/.*##'` |
| Upstream repo | `git remote get-url upstream \| sed -E 's#.*github.com[:/]##; s#\.git$##'` |
| Cross-fork PR | `gh pr create --repo <upstream> --head <fork-owner>:<branch>` |

## Related Skills

- [git-fork-workflow](../git-fork-workflow/SKILL.md) - Fork management and sync strategies
- [git-branch-pr-workflow](../git-branch-pr-workflow/SKILL.md) - General branch and PR patterns
- [git-conflicts](../git-conflicts/SKILL.md) - Resolve cherry-pick conflicts
- [git-rebase-patterns](../git-rebase-patterns/SKILL.md) - Advanced rebase techniques
- [gh-cli-agentic](../gh-cli-agentic/SKILL.md) - GitHub CLI cross-fork PR fields
