---
created: 2025-12-16
modified: 2026-11-08
reviewed: 2026-04-25
allowed-tools: Bash(gh pr checks *), Bash(gh pr view *), Bash(gh run view *), Bash(gh run list *), Bash(gh repo view *), Bash(git status *), Bash(git diff *), Bash(git log *), Bash(git add *), Bash(git commit *), Bash(git push *), Bash(git fetch *), Bash(git switch *), Bash(git cherry-pick *), Bash(gh pr create *), Bash(gh pr close *), Bash(uv lock *), Bash(pre-commit *), Bash(npm run *), Bash(uv run *), Read, Edit, Grep, Glob, TodoWrite, mcp__github__pull_request_read
args: "[pr-number] [--auto-fix] [--push]"
argument-hint: "[pr-number] [--auto-fix] [--push]"
description: "Failing PR checks — reproduce locally, patch the code, push the fix. Use when asked to fix a PR, resolve red CI, or auto-fix lint/test failures."
name: git-fix-pr
---

## When to Use This Skill

| Use this skill when... | Use the alternative when... |
|---|---|
| Fixing failing CI checks on an existing PR (lint, type, test) | Use `git-pr-feedback` to address reviewer comments rather than CI failures |
| Reproducing red GitHub Actions runs locally before pushing corrections | Use `gh-workflow-monitoring` to passively watch a run rather than fix it |
| Auto-applying lint/format/type fixes and pushing them to the PR branch | Use `git-conflicts` when the failure is a merge conflict, not a check |
| Diagnosing why a pull request is red after a push | Use `git-triage` to sweep many PRs at once instead of fixing one |

## Context

- Repo: !`git remote -v`
- Current branch: !`git branch --show-current`
- Git status: !`git status --porcelain=v2 --branch`
- Staged changes: !`git diff --cached --numstat`
- Unstaged changes: !`git diff --numstat`
- Recent commits: !`git log --format='%h %s' --max-count=5`

## Parameters

Parse these parameters from the command (all optional):
- `$1`: PR number (if not provided, detect from current branch)
- `--auto-fix`: Automatically apply fixes for common issues
- `--push`: Push fixes to the branch after committing

## Your task

Analyze and fix failing PR checks.

### Step 1: Determine PR

1. **Get PR number** from argument or detect from current branch
2. **Fetch PR status** using `gh pr checks <pr-number>` or mcp__github__pull_request_read

### Step 2: Analyze Failures

1. **Identify failing checks** from PR status
2. **Research error messages** in workflow logs
3. **Categorize failures**:
   - Linting errors
   - Type errors
   - Test failures
   - Build errors

### Step 3: Reproduce Locally

1. **Run tests locally** to reproduce issues
2. **Run linters** to check for style issues
3. **Run type checker** if applicable

### Step 4: Apply Fixes (if --auto-fix)

Based on failure type:

- **Linting errors**: Run appropriate linters/formatters
  ```bash
  # Python
  uv run ruff check --fix .
  uv run ruff format .

  # JavaScript/TypeScript
  npm run lint -- --fix
  ```

- **Type errors**: Fix type annotations or implementations
- **Test failures**: Fix failing tests or implementation bugs

### Bot dependency PRs: fix on a branch of your own

This section replaces Steps 5–6 when **both** hold:

- the repo's workflows call a reusable auto-resolve-conflicts workflow such as `reusable-auto-resolve-conflicts.yml` (`grep -l reusable-auto-resolve-conflicts .github/workflows/*`), and
- the PR's head branch is `renovate/*` or `dependabot/*`.

Why: when such a PR starts to conflict with `main`, that workflow does not resolve it. It runs `gh pr close --delete-branch` on those branch patterns by design, because the bot will recreate the PR. The recreated PR carries only the bot's change, so a fix pushed to the bot branch is lost and the check fails again. The workflow's other skipped patterns (release-please, version-tracking, config-sync branches) have their own regeneration paths and are out of scope here.

1. **Leave the bot branch untouched.** Branch from `main` under a name outside those patterns (for example `chore/deps-<topic>`), cherry-pick the bot's commits (`git log origin/main..origin/<bot-branch>`; a fresh Renovate branch holds only its own), commit the fix on top, and open that branch as the PR. Once it merges, `main` has the update and the bot has nothing left to propose. Close the bot PR by hand, or let auto-resolve close it when it conflicts.
2. **For a lock-maintenance PR, regenerate the locks instead of cherry-picking them.** Run the package manager's upgrade command in each project the PR lists (`uv lock --upgrade` for uv) with the version CI pins: the `version:` input of the setup action (`astral-sh/setup-uv`, `oven-sh/setup-bun`, …) in `.github/workflows/`, not the locally installed one. Commit the failure fix in the same commit, because either change alone can leave the check red, then re-run the failing check. As a sanity check, not a threshold, compare per-file sizes from `git diff --stat origin/main` with the bot PR's file list; a large gap points to a different resolver version or a moved base.
3. **Hold a bump that cannot be made to work.** When no change in the repo makes the new version pass, add a `packageRules` entry to `renovate.json` with `allowedVersions` (stay below the failing release) or `enabled: false` (stop updates), plus a `description` saying why. Without it, the bot proposes the same bump on its next run.

### Step 5: Commit and Push (if --push)

For a bot PR that matches [Bot dependency PRs](#bot-dependency-prs-fix-on-a-branch-of-your-own), follow that section instead of Steps 5–6.

1. **Stage fixes**: `git add -u`
2. **Commit**: `git commit -m "fix: resolve CI failures"`
3. **Push**: `git push`

### Step 6: Verify

1. **Re-run checks** locally to verify fixes
2. **Monitor PR checks** after push

## Common Fix Patterns

| Check Type | Common Fixes |
|------------|--------------|
| Linting | Run formatter, fix import order |
| Types | Add type annotations, fix mismatches |
| Tests | Fix assertions, update snapshots |
| Build | Fix imports, resolve dependencies |

## See Also

- **github-actions-inspection** skill for workflow analysis
- **git-branch-pr-workflow** skill for PR patterns
