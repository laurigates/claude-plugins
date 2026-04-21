# Git Plugin

Git workflows, commits, branches, PRs, and repository management for Claude Code.

## Overview

This plugin provides comprehensive Git workflow automation including conventional commits, branch management, pull request handling, and issue processing.

## Flow

See [`docs/flow.md`](docs/flow.md) for a diagram of how the skills fit together.

## Skills

| Skill | Description |
|-------|-------------|
| `/git:api-pr` | Create PRs via GitHub API without local git operations - for quick fixes, typos, config updates |
| `/git:commit` | Complete workflow from changes to PR - auto-detect issues, create logical commits with proper linkage, push, optionally create PR |
| `/git:issue` | Process GitHub issues with interactive selection, conflict detection, and parallel work support |
| `/git:issue-hierarchy` | Manage sub-issues and native `blocked_by` / `blocking` dependencies between issues |
| `/git:issue-manage` | Administrative operations: transfer, pin, lock, develop branches, bulk ops, custom fields |
| `/git:fix-pr` | Analyze and fix failing PR checks |
| `/git:pr-feedback` | Review PR workflow results and comments, address substantive feedback from reviewers |
| `/git:conflicts` | Resolve merge conflicts with zdiff3, rerere, and modern git tooling |
| `/git:resolve-conflicts` | Resolve merge conflicts in PRs automatically |
| `/git:maintain` | Repository maintenance and cleanup (prune, gc, verify, branches, stash) |
| `/git:derive-docs` | Analyze git history to derive undocumented rules, PRDs, ADRs, and PRPs |
| `/git:upstream-pr` | Submit clean PRs to upstream repositories from fork work |
| `/git:coworker-check` | Detect another agent working in the same repo clone before destructive git ops |

## Layered Skills (Composable Git Workflows)

Three composable skills that can be invoked individually or combined based on user intent:

| Skill | Trigger Phrases | Description |
|-------|-----------------|-------------|
| `git-commit` | "commit", "save changes", "stage and commit" | Create commits with conventional messages and issue references |
| `git-push` | "push", "push changes", "send to remote" | Push local commits to remote with branch tracking |
| `git-pr` | "create PR", "open pull request", "submit for review" | Create pull requests with descriptions and issue linkage |

### Composability

| User Intent | Skills Invoked |
|-------------|----------------|
| "commit" | git-commit |
| "commit and push" | git-commit → git-push |
| "push and create PR" | git-push → git-pr |
| "commit, push, and create PR" | git-commit → git-push → git-pr |

## Reference Skills

| Skill | Description |
|-------|-------------|
| `git-branch-naming` | Branch naming conventions (type prefixes, issue linking, kebab-case) |
| `git-cli-agentic` | Git commands optimized for AI agents with porcelain output |
| `gh-cli-agentic` | GitHub CLI commands optimized for AI agents with JSON output |
| `gh-workflow-monitoring` | Watch GitHub Actions runs with blocking commands (no polling/timeouts) |
| `git-commit-workflow` | Conventional commit patterns and best practices |
| `git-commit-trailers` | Commit trailer conventions — release-please trailers (BREAKING CHANGE, Release-As), attribution (Co-authored-by, Signed-off-by), git interpret-trailers |
| `git-branch-pr-workflow` | Git branching and PR workflow patterns |
| `git-rebase-patterns` | Advanced rebase techniques (--reapply-cherry-picks, --update-refs, --onto, stacked PRs) |
| `git-repo-detection` | Detect GitHub repository name and owner from git remotes |
| `git-security-checks` | Security checks before staging files |
| `github-issue-autodetect` | Auto-detect issues that changes may fix/close for proper commit linkage |
| `github-issue-writing` | Create well-structured GitHub issues with clear titles and acceptance criteria |
| `github-labels` | Discover and apply labels to GitHub PRs and issues |
| `github-pr-title` | Craft effective PR titles using conventional commit format |
| `git-derive-docs` | Derive undocumented rules, PRDs, ADRs, PRPs from git commit history |
| `release-please-configuration` | Release-please config for monorepos and version automation |
| `release-please-protection` | Prevent manual edits to release-please managed files |
| `release-please-pr-workflow` | Batch merge release-please PRs with conflict handling |
| `git-fork-workflow` | Fork management, upstream sync, divergence detection, cross-fork PRs |

## Agent

| Agent | Description |
|-------|-------------|
| `commit-review` | Commit message review and validation |

## Workflow Examples

### Complete Commit Workflow

```bash
/git:commit --push --pr
```

Analyzes changes, creates logical commits with conventional messages, pushes to remote, and creates a pull request.

### Process GitHub Issues

```bash
/git:issue              # Interactive mode - select issues
/git:issue 123          # Process single issue
/git:issue 123 456 789  # Process multiple issues
/git:issue --auto       # Claude selects and prioritizes
/git:issue --parallel   # Process parallel groups simultaneously
```

Analyzes issues for conflicts and dependencies, implements fixes with TDD workflow, and creates PRs.

### Manage Sub-Issues and Dependencies

```bash
/git:issue-hierarchy 42 --status          # Show sub-issue progress
/git:issue-hierarchy 42 --add 43 44 45    # Add sub-issues to parent
/git:issue-hierarchy 42 --create "Add tests for auth"  # Create new sub-issue
/git:issue-hierarchy 42 --deps            # Blocked-by + blocking + sub-issue graph
/git:issue-hierarchy 42 --blocked-by 40   # Mark #42 as blocked by #40 (native API)
/git:issue-hierarchy 42 --block 50        # Mark #50 as blocked by #42
/git:issue-hierarchy 42 --blocking        # List what #42 currently blocks
/git:issue-hierarchy 42 --unblock 40      # Remove the dependency between #42 and #40
```

Manages parent-child issue relationships and dependency tracking using GitHub's
sub-issues and native issue-dependencies APIs (the same endpoints that power
the sidebar "Relationships" panel and the "Blocked" badge on project boards).

**When to use which link type:**

| Relationship | Command | Use for |
|--------------|---------|---------|
| Sub-issue | `--add N` / `--create "..."` | Composition — child is part of parent's scope |
| Blocked by | `--blocked-by N` | Hard ordering — parent can't start until N closes |
| Blocks | `--block N` | Hard ordering (inverse) — N can't start until parent closes |
| Related to | Plain body text | Soft cross-reference; no lifecycle coupling |

### Issue Administration

```bash
/git:issue-manage transfer 42 other-repo     # Transfer issue
/git:issue-manage pin 42 43                   # Pin important issues
/git:issue-manage lock 42 --reason resolved   # Lock resolved discussions
/git:issue-manage develop 42 --checkout       # Create branch from issue
/git:issue-manage bulk close 100 101 102      # Bulk close issues
/git:issue-manage fields 42 --list            # List custom field values
```

Administrative operations including transfer, pin/unpin, lock/unlock, branch creation, bulk operations, and custom field management.

### Fix Failing PR

```bash
/git:fix-pr 456 --auto-fix --push
```

Analyzes PR #456 check failures and attempts automatic fixes.

### Address PR Feedback

```bash
/git:pr-feedback              # Use current branch's PR
/git:pr-feedback 789          # Review PR #789 feedback
/git:pr-feedback 789 --push   # Address feedback and push fixes
```

Reviews PR workflow results and reviewer comments, categorizes feedback (blocking, substantive, suggestions), and systematically addresses actionable items.

### Derive Documentation from History

```bash
/git:derive-docs --all              # Full analysis (rules, PRD, ADR, PRP)
/git:derive-docs --rules            # Only derive .claude/rules/
/git:derive-docs --adr --since=2025-06-01  # ADRs from recent history
/git:derive-docs --all --dry-run    # Report gaps without creating files
/git:derive-docs --refinements      # Focus on plan refinement detection
```

Analyzes commit history to find undocumented conventions, features, architecture decisions, and plan refinements.

### Resolve Merge Conflicts

```bash
/git:conflicts                # Resolve conflicts in current merge/rebase
/git:conflicts 123            # Fetch base branch for PR #123 and resolve
/git:conflicts --theirs       # Accept all incoming changes
/git:conflicts --push         # Push after resolving
```

Configures zdiff3 conflict markers and rerere, then resolves each conflict intelligently or accepts one side wholesale.

### Submit PR to Upstream from Fork

```bash
/git:upstream-pr                              # Interactive commit selection
/git:upstream-pr --commits abc123,def456      # Specific commits
/git:upstream-pr --branch feat/my-fix --draft # Named branch, draft PR
/git:upstream-pr --dry-run                    # Preview without changes
```

Cherry-picks selected commits onto a clean branch from `upstream/main`, squashes them, and creates a cross-fork PR.

### Repository Maintenance

```bash
/git:maintain --all
```

Runs full repository maintenance: prune remote branches, garbage collection, verify integrity.

## Installation

```bash
/plugin install git-plugin@laurigates-claude-plugins
```

## Recommended Project Settings

For seamless command execution without permission prompts, add these permissions to your project's `.claude/settings.json`:

```json
{
  "permissions": {
    "allow": [
      "Bash(gh pr *)",
      "Bash(gh run *)",
      "Bash(gh issue *)",
      "Bash(gh repo *)",
      "Bash(gh api *)",
      "Bash(gh label *)",
      "Bash(gh workflow *)",
      "Bash(git status *)",
      "Bash(git diff *)",
      "Bash(git log *)",
      "Bash(git add *)",
      "Bash(git commit *)",
      "Bash(git push *)",
      "Bash(git pull *)",
      "Bash(git branch *)",
      "Bash(git switch *)",
      "Bash(git remote *)",
      "Bash(git stash *)",
      "Bash(git restore *)",
      "Bash(git gc *)",
      "Bash(git prune *)",
      "Bash(git fsck *)",
      "Bash(pre-commit *)",
      "Bash(gitleaks *)"
    ]
  }
}
```

This enables:
- **Git operations**: status, diff, log, add, commit, push, branch management
- **GitHub CLI**: PR checks, run viewing, issue management, workflow triggers
- **Security**: pre-commit hooks and secret detection

## Agentic Optimization

Commands use machine-readable output formats:

| Tool | Format | Example |
|------|--------|---------|
| Git status | Porcelain v2 | `git status --porcelain=v2 --branch` |
| Git diff | Numstat | `git diff --numstat` |
| Git log | Custom format | `git log --format='%h %s' -n 10` |
| GH CLI | JSON + jq | `gh pr checks $N --json name,state,conclusion` |

See the `git-cli-agentic` and `gh-cli-agentic` skills for complete reference.

## License

MIT
