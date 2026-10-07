---
created: 2025-12-16
modified: 2026-05-09
reviewed: 2026-05-09
name: git-branch-pr-workflow
description: "Branch management and PR workflows — git switch/restore, GitHub MCP. Use when creating branches, opening PRs, or working with feature branches."
user-invocable: false
allowed-tools: Bash, Read, mcp__github__create_pull_request, mcp__github__list_pull_requests, mcp__github__update_pull_request
---

# Git Branch PR Workflow

## When to Use This Skill

| Use this skill when... | Use the alternative when... |
|---|---|
| Designing the overall branch + PR workflow (main-branch dev, MCP integration) | Use `git-branch-naming` to pick or audit a single branch name |
| Choosing between `git switch`, `git restore`, and feature-branch push patterns | Use `git-rebase-patterns` for linear-history cleanup and stacked PRs |
| Creating PRs through GitHub MCP tools rather than `gh pr create` | Use `git-pr` to create PRs from a pushed branch via the `gh` CLI |
| Coordinating commit -> push -> PR end-to-end | Use `git-commit-push-pr` for the consolidated commit+push+PR macro |

Expert guidance for branch management, pull request workflows, and GitHub integration using modern Git commands and linear history practices.

## Core Expertise

- **Main-Branch Development**: Work on main locally, push to remote feature branches for PRs
- **Modern Git Commands**: Use `git switch` and `git restore` instead of checkout
- **Branch Naming**: See [git-branch-naming](../git-branch-naming/SKILL.md) skill
- **Linear History**: Rebase-first workflow, squash merging - see [git-rebase-patterns](../git-rebase-patterns/SKILL.md) for advanced patterns
- **GitHub MCP Integration**: Use mcp__github__* tools instead of gh CLI

## Main-Branch Development (Preferred)

Develop directly on main, push to remote feature branches for PRs. This eliminates local branch management overhead.

### Basic Workflow

```bash
# All work happens on main
git switch main
git pull origin main

# Make changes, commit on main
git add file.ts
git commit -m "feat(auth): add OAuth2 support"

# Push to remote feature branch (creates PR target)
git push origin main:feat/auth-oauth2

# Create PR using GitHub MCP (head: feat/auth-oauth2, base: main)
```

### Multi-PR Workflow (Sequential Commits)

When you have commits for multiple PRs on main, push specific commit ranges to different remote branches:

```bash
# Commits on main:
# abc1234 feat(auth): add OAuth2 support       <- PR #1
# def5678 feat(auth): add token refresh        <- PR #1
# ghi9012 fix(api): handle timeout edge case   <- PR #2

# Push first 2 commits to auth feature branch
git push origin abc1234^..def5678:feat/auth-oauth2

# Push remaining commit to fix branch
git push origin ghi9012^..ghi9012:fix/api-timeout

# Alternative: push from a specific commit to HEAD
git push origin def5678..HEAD:fix/api-timeout
```

**Commit range patterns:**
- `git push origin <start>^..<end>:<remote-branch>` - Push commit range (inclusive)
- `git push origin <commit>..<commit>:<remote-branch>` - Push range (exclusive start)
- `git push origin <commit>..HEAD:<remote-branch>` - Push from commit to current HEAD
- `git push origin main:<remote-branch>` - Push entire main to remote branch

### Benefits

- **No local branch juggling** - Always on main
- **Always on latest main** - No branch drift
- **Clean local state** - No stale branches to clean up
- **Remote branches are ephemeral** - Deleted after PR merge
- **Simpler mental model** - One local branch, many remote targets

## Modern Git Commands (2025)

Use `git switch` for branches and `git restore` for files instead of `git checkout` / `git reset`. See [references/modern-git-commands.md](references/modern-git-commands.md) for the forms and the legacy-to-modern migration table.

## Branch Naming

For comprehensive branch naming conventions including type prefixes, issue linking, and validation patterns, see [git-branch-naming](../git-branch-naming/SKILL.md).

**Quick reference:** `{type}/{issue}-{description}` (e.g., `feat/123-user-auth`)

## Linear History Workflow

Main-branch development (above) is preferred. For a local feature branch (multi-day or experimental work), squash merging, and interactive rebase cleanup, see [references/local-feature-branches.md](references/local-feature-branches.md).

## Advanced Rebase Patterns

For advanced rebase techniques including `--reapply-cherry-picks`, `--update-refs`, `--onto`, stacked PR workflows, and combining flags, see [git-rebase-patterns](../git-rebase-patterns/SKILL.md).

## GitHub MCP Integration

Use GitHub MCP tools for all GitHub operations:

```python
# Get repository information
mcp__github__get_me()  # Get authenticated user info

# List and create PRs
mcp__github__list_pull_requests(owner="owner", repo="repo")
mcp__github__create_pull_request(
  owner="owner",
  repo="repo",
  title="feat: add authentication",
  head="feat/auth",
  base="main",
  body="## Summary\n- JWT authentication\n- OAuth support\n\nCloses #123"
)

# Update PRs
mcp__github__update_pull_request(
  owner="owner",
  repo="repo",
  pullNumber=42,
  title="Updated title",
  state="open"
)

# List and create issues
mcp__github__list_issues(owner="owner", repo="repo")
```

## Best Practices

Always force-push with `--force-with-lease`, never to `main`/shared branches. For the daily rebase-onto-main routine and rebase conflict handling, see [references/local-feature-branches.md](references/local-feature-branches.md).

## Main Branch Protection

Configure branch rules for linear history via GitHub MCP:

```bash
# Require linear history (disable merge commits)
# Configure via GitHub settings or MCP tools
# - Require pull request reviews
# - Require status checks to pass
# - Enforce linear history (squash merge only)
```

## Branch Comparison: Always Use origin/main

**CRITICAL:** When comparing branches for PR creation, always compare against `origin/main` (or `origin/<base-branch>`), **never** local `main`. Local `main` may contain commits that haven't been merged to the remote, causing PRs to include unrelated changes.

### Why This Matters

```bash
# WRONG: compares against local main (may include unpushed commits)
git log main..HEAD --format='%s'
git diff main...HEAD --stat

# CORRECT: compares against remote main (matches what GitHub will show)
git fetch origin main
git log origin/main..HEAD --format='%s'
git diff origin/main...HEAD --stat
```

**Common scenario:** You commit changes on local `main` for one PR, push to a feature branch, then start working on a second PR. If you compare against local `main`, the second PR's diff looks correct. But if the first PR hasn't merged yet, `origin/main` is behind — and comparing against it reveals that both PRs' changes would be included.

### Rules

1. **Always fetch before comparing:** `git fetch origin main`
2. **Use `origin/main` in all diff/log commands** for PR context
3. **Base PRs on `origin/main`** when creating branches: `git switch -c feat/foo origin/main`
4. The `pr-context.sh` script handles this automatically

## PR Context Gathering (Recommended)

Before creating a PR, gather all context in one command:

```bash
# Gather PR context (defaults to main as base, compares against origin/main)
bash "${CLAUDE_PLUGIN_ROOT}/skills/git-branch-pr-workflow/scripts/pr-context.sh"

# Specify different base branch (compares against origin/develop)
bash "${CLAUDE_PLUGIN_ROOT}/skills/git-branch-pr-workflow/scripts/pr-context.sh" develop
```

The script fetches the latest remote state and compares against `origin/<base>` to ensure accurate PR context. Outputs: branch info, remote status, commit range and types, diff stats, issue references found in commits, existing PR detection, and CI check results. Use this output to compose the PR title and body. See [scripts/pr-context.sh](scripts/pr-context.sh) for details.

## Pull Request Workflow

### PR Title Format

Use conventional commit format in PR titles:

- `feat: add user authentication`
- `fix: resolve login validation bug`
- `docs: update API documentation`
- `chore: update dependencies`

### PR Body Template

```markdown
## Summary
Brief description of changes

## Changes
- Bullet points of key changes
- Link related work

## Testing
How changes were tested

## Issue References
<!-- Use GitHub autolink format - ALWAYS include relevant issues -->
Closes #123
<!-- Or use: Fixes #N, Resolves #N, Refs #N -->
```

**Issue Reference Guidelines:**
- Use `Closes #N` / `Fixes #N` / `Resolves #N` to auto-close issues on merge
- Use `Refs #N` / `Related to #N` for context without auto-closing
- Cross-repo: `Fixes owner/repo#N`
- Multiple: `Fixes #1, fixes #2, fixes #3` (repeat keyword)

### PR Creation Best Practices

- **One focus per PR** - Single logical change
- **Small PRs** - Easier to review (< 400 lines preferred)
- **ALWAYS link issues** - Use GitHub autolink format for traceability:
  - Closing keywords: `Closes #123`, `Fixes #456`, `Resolves #789`
  - Reference without closing: `Refs #234`, `Related to #567`
  - Cross-repository: `Fixes owner/repo#123`
  - Multiple issues: `Fixes #1, fixes #2` (repeat keyword for each)
- **Add labels** - Use GitHub labels for categorization
- **Request reviewers** - Tag specific reviewers when needed

## Troubleshooting & Recovery

For troubleshooting (branch diverged, committed-to-main expected workflow, complex rebase conflicts), safe-operation guidance (recognising normal states, confirmation-required commands), and recovery workflows (pre-commit modifies files, push rejected, commit fails), see [REFERENCE.md](REFERENCE.md).
