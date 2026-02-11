# Git Plugin

Git workflows, commits, branches, PRs, and repository management for Claude Code.

## Overview

This plugin provides comprehensive Git workflow automation including conventional commits, branch management, pull request handling, and issue processing.

## Skills

| Skill | Description |
|-------|-------------|
| `/git:commit` | Complete workflow from changes to PR - auto-detect issues, create logical commits with proper linkage, push, optionally create PR |
| `/git:issue` | Process GitHub issues with interactive selection, conflict detection, and parallel work support |
| `/git:fix-pr` | Analyze and fix failing PR checks |
| `/git:pr-feedback` | Review PR workflow results and comments, address substantive feedback from reviewers |
| `/git:maintain` | Repository maintenance and cleanup (prune, gc, verify, branches, stash) |
| `/git:derive-docs` | Analyze git history to derive undocumented rules, PRDs, ADRs, and PRPs |

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
| `git-worktree-agent-workflow` | Parallel agent workflows using git worktrees for isolated, concurrent issue work |
| `git-cli-agentic` | Git commands optimized for AI agents with porcelain output |
| `gh-cli-agentic` | GitHub CLI commands optimized for AI agents with JSON output |
| `gh-workflow-monitoring` | Watch GitHub Actions runs with blocking commands (no polling/timeouts) |
| `git-commit-workflow` | Conventional commit patterns and best practices |
| `git-branch-pr-workflow` | Git branching and PR workflow patterns |
| `git-rebase-patterns` | Advanced rebase techniques (--reapply-cherry-picks, --update-refs, --onto, stacked PRs) |
| `git-repo-detection` | Detect GitHub repository name and owner from git remotes |
| `git-security-checks` | Security checks before staging files |
| `github-issue-autodetect` | Auto-detect issues that changes may fix/close for proper commit linkage |
| `github-issue-writing` | Create well-structured GitHub issues with clear titles and acceptance criteria |
| `github-labels` | Discover and apply labels to GitHub PRs and issues |
| `github-pr-title` | Craft effective PR titles using conventional commit format |
| `git-log-documentation` | Derive undocumented rules, PRDs, ADRs, PRPs from git commit history |
| `release-please-configuration` | Release-please config for monorepos and version automation |
| `release-please-protection` | Prevent manual edits to release-please managed files |
| `release-please-pr-workflow` | Batch merge release-please PRs with conflict handling |

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
      "Bash(detect-secrets *)"
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
