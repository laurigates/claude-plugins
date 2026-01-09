# Git Plugin

Git workflows, commits, branches, PRs, and repository management for Claude Code.

## Overview

This plugin provides comprehensive Git workflow automation including conventional commits, branch management, pull request handling, and issue processing.

## Commands

| Command | Description |
|---------|-------------|
| `/git:commit` | Complete workflow from changes to PR - analyze, create logical commits, push, optionally create PR |
| `/git:issue` | Process and fix a single GitHub issue with TDD workflow |
| `/git:issues` | Process multiple GitHub issues in sequence |
| `/git:fix-pr` | Analyze and fix failing PR checks |
| `/git:maintain` | Repository maintenance and cleanup (prune, gc, verify, branches, stash) |

## Skills

| Skill | Description |
|-------|-------------|
| `git-commit-workflow` | Conventional commit patterns and best practices |
| `git-branch-pr-workflow` | Git branching and PR workflow patterns |
| `git-repo-detection` | Detect GitHub repository name and owner from git remotes |
| `git-security-checks` | Security checks before staging files |
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

### Process GitHub Issue

```bash
/git:issue 123
```

Fetches issue #123, creates a branch, implements the fix with TDD, and prepares for PR.

### Fix Failing PR

```bash
/git:fix-pr 456 --auto-fix --push
```

Analyzes PR #456 check failures and attempts automatic fixes.

### Repository Maintenance

```bash
/git:maintain --all
```

Runs full repository maintenance: prune remote branches, garbage collection, verify integrity.

## Installation

```bash
/plugin install git-plugin@lgates-claude-plugins
```

## License

MIT
