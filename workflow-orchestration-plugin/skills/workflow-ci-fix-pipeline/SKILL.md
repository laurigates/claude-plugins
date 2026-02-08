---
model: opus
name: workflow-ci-fix-pipeline
description: |
  Autonomous CI failure diagnosis and fix pipeline. Use when PRs have failing
  checks, CI is red across multiple branches, or you need to systematically
  diagnose and fix build/test/lint failures. Spawns isolated agents per failing
  PR with automatic error categorization and fix application.
args: "[pr-number|--failing|--repo=OWNER/REPO]"
allowed-tools: Bash(gh pr *), Bash(gh run *), Bash(gh repo *), Bash(git fetch *), Bash(git status *), Bash(git diff *), Bash(git log *), Bash(git branch *), Bash(git checkout *), Bash(git add *), Bash(git commit *), Bash(git push *), Bash(git worktree *), Bash(npm run *), Bash(npx *), Bash(uv run *), Bash(cargo *), Bash(pre-commit *), Read, Edit, Write, Grep, Glob, Task, TodoWrite
argument-hint: PR number, --failing for all failing PRs, or --repo=owner/repo
created: 2026-02-08
modified: 2026-02-08
reviewed: 2026-02-08
---

# /workflow:ci-fix

Autonomous CI failure diagnosis and remediation pipeline.

## When to Use This Skill

| Use this skill when... | Use git:fix-pr instead when... |
|------------------------|-------------------------------|
| Multiple PRs have failing checks | Single PR with a known failure |
| Need systematic diagnosis across branches | Simple lint/type error to fix |
| Want parallel fix agents per PR | Already know the exact fix |
| Cross-repo CI monitoring | Working in a single repo |

## Context

- Repo: !`gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null`
- Default branch: !`gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null`
- Failing PRs: !`gh pr list --json number,title,headRefName,statusCheckRollup --limit 20 2>/dev/null`
- Recent failed runs: !`gh run list --status failure --limit 5 --json databaseId,headBranch,conclusion,event 2>/dev/null`

## Parameters

- **PR number**: Fix a specific PR's failing checks
- **`--failing`**: Find and fix all PRs with failing checks
- **`--repo=OWNER/REPO`**: Target a different repository

## Execution

### Phase 1: Identify Failures

```bash
# All failing PRs in current repo
gh pr list --json number,title,headRefName,statusCheckRollup \
  | jq '[.[] | select(.statusCheckRollup[]? | .conclusion == "FAILURE")]'

# Or specific PR checks
gh pr checks $PR_NUMBER --json name,state,conclusion,detailsUrl

# Get failed run logs
gh run view $RUN_ID --log-failed 2>/dev/null | head -100
```

**Categorize each failure**:

| Category | Indicators | Typical Fix |
|----------|-----------|-------------|
| Lint | "eslint", "ruff", "biome", "lint" | Run formatter/linter with --fix |
| Type | "tsc", "type-check", "mypy" | Fix type annotations |
| Test | "test", "jest", "vitest", "pytest" | Fix test or implementation |
| Build | "build", "compile", "bundle" | Fix imports, dependencies |
| Security | "audit", "detect-secrets" | Update deps, remove secrets |
| Format | "prettier", "black", "format" | Run formatter |

### Phase 2: Plan Fixes

Create a TodoWrite plan:

```
For each failing PR:
1. Diagnosis: What checks fail and why
2. Category: lint/type/test/build/security
3. Complexity: auto-fixable / needs-investigation / needs-human
4. Fix strategy: specific commands or code changes needed
```

**Auto-fixable patterns** (apply without investigation):
- Lint errors with `--fix` flag available
- Format errors (run formatter)
- Lockfile out of sync (regenerate)

**Needs investigation**:
- Test failures (read test output, understand intent)
- Build errors (dependency conflicts, missing imports)
- Type errors (understand expected types)

### Phase 3: Execute Fixes

**For single PR**: Fix in current worktree.

**For multiple PRs**: Create worktrees and optionally spawn parallel agents.

```bash
# Create worktree per failing PR
for PR in $FAILING_PRS; do
  BRANCH=$(gh pr view $PR --json headRefName -q .headRefName)
  git worktree add /tmp/ci-fix-pr-$PR $BRANCH
done
```

**Agent prompt for each PR**:
```
You are fixing CI failures for PR #$PR in worktree /tmp/ci-fix-pr-$PR

Branch: $BRANCH
Failing checks: $FAILING_CHECKS

Failed run logs:
$LOG_OUTPUT

Your tasks:
1. Diagnose the failure from the logs above
2. Reproduce locally if possible
3. Apply the fix
4. Run the same checks locally to verify
5. Commit with message: "fix: resolve CI failures for PR #$PR"
6. Do NOT push - report completion status

If the fix requires human judgment (architectural decisions, test intent unclear),
document what you found and what options exist.
```

### Phase 4: Verify Fixes

```bash
for PR in $FAILING_PRS; do
  echo "=== PR #$PR ==="

  # Check that the fix commit exists
  git -C /tmp/ci-fix-pr-$PR log --oneline -1

  # Run the same checks that failed
  # Adapt to project: npm test, cargo test, pytest, etc.
  cd /tmp/ci-fix-pr-$PR

  # Common check commands
  npm run lint 2>/dev/null || true
  npm run typecheck 2>/dev/null || true
  npm run test 2>/dev/null || true
done
```

### Phase 5: Push Fixes

Push sequentially to avoid TLS errors:

```bash
for PR in $FAILING_PRS; do
  BRANCH=$(gh pr view $PR --json headRefName -q .headRefName)
  git -C /tmp/ci-fix-pr-$PR push origin $BRANCH

  # Retry on network failure
  if [ $? -ne 0 ]; then
    sleep 2 && git -C /tmp/ci-fix-pr-$PR push origin $BRANCH
  fi
done
```

### Phase 6: Report and Cleanup

Output a summary:

| PR | Branch | Failure Type | Fix Applied | Status |
|----|--------|-------------|-------------|--------|
| #12 | feat/auth | lint | ruff --fix | pushed |
| #15 | fix/api | test | Fixed assertion | pushed |
| #23 | feat/ui | build | Needs human review | blocked |

```bash
# Cleanup worktrees
for PR in $FAILING_PRS; do
  git worktree remove /tmp/ci-fix-pr-$PR 2>/dev/null || true
done
git worktree prune
```

## Common Fix Commands

| Stack | Lint Fix | Type Check | Test |
|-------|----------|------------|------|
| TypeScript/Bun | `bunx biome check --fix .` | `bunx tsc --noEmit` | `bun test --bail=1` |
| TypeScript/Node | `npx eslint --fix .` | `npx tsc --noEmit` | `npm test` |
| Python/uv | `uv run ruff check --fix .` | `uv run mypy .` | `uv run pytest -x` |
| Rust | `cargo clippy --fix` | `cargo check` | `cargo nextest run` |

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Failing PRs | `gh pr list --json number,statusCheckRollup \| jq '[.[] \| select(..)]'` |
| PR check details | `gh pr checks $N --json name,conclusion,detailsUrl` |
| Failed run logs | `gh run view $ID --log-failed \| head -100` |
| Run by PR | `gh run list --branch $BRANCH --status failure --limit 1 --json databaseId` |
| Quick lint fix | `npx eslint --fix . 2>/dev/null; npx prettier --write . 2>/dev/null` |
| Quick type check | `npx tsc --noEmit --pretty 2>&1 \| head -30` |

## Related Skills

- [git-fix-pr](../../../git-plugin/skills/git-fix-pr/SKILL.md) - Single PR fix workflow
- [gh-workflow-monitoring](../../../git-plugin/skills/gh-workflow-monitoring/SKILL.md) - GitHub Actions monitoring
- [github-actions-inspection](../../../github-actions-plugin/skills/github-actions-inspection/SKILL.md) - Workflow file analysis
