---
model: haiku
created: 2025-12-16
modified: 2026-02-14
reviewed: 2026-01-15
name: git-commit-workflow
description: |
  Commit message conventions, staging practices, and commit best practices.
  Covers conventional commits, explicit staging workflow, logical change grouping,
  humble fact-based communication style, and automatic issue detection.
  Use when user mentions committing changes, writing commit messages, git add,
  git commit, staging files, or conventional commit format.
allowed-tools: Bash, Read
---

# Git Commit Workflow

Expert guidance for commit message conventions, staging practices, and commit best practices using conventional commits and explicit staging workflows.

For detailed examples, advanced patterns, and best practices, see [REFERENCE.md](REFERENCE.md).

## Core Expertise

- **Conventional Commits**: Standardized format for automation and clarity
- **Explicit Staging**: Always stage files individually with clear visibility
- **Logical Grouping**: Group related changes into focused commits
- **Communication Style**: Humble, factual, concise commit messages
- **Pre-commit Integration**: Run checks before committing

**Note:** Commits are made on main branch and pushed to remote feature branches for PRs. See **git-branch-pr-workflow** skill for the main-branch development pattern.

## Conventional Commit Format

### Standard Format

```
type(scope): description

[optional body]

[optional footer(s)]
```

### Commit Types

- **feat**: New feature for the user
- **fix**: Bug fix for the user
- **docs**: Documentation changes
- **style**: Formatting, missing semicolons, etc (no code change)
- **refactor**: Code restructuring without changing behavior
- **test**: Adding or updating tests
- **chore**: Maintenance tasks, dependency updates, linter fixes
- **perf**: Performance improvements
- **ci**: CI/CD changes

### Examples

```bash
# Feature with scope
git commit -m "feat(auth): implement OAuth2 integration"

# Bug fix with body
git commit -m "fix(api): resolve null pointer in user service

Fixed race condition where user object could be null during
concurrent authentication requests."

# Breaking change
git commit -m "feat(api)!: migrate to GraphQL endpoints

BREAKING CHANGE: REST endpoints removed in favor of GraphQL.
See migration guide at docs/migration.md"
```

### Commit Message Best Practices

**DO:**
- Use imperative mood ("add feature" not "added feature")
- Keep first line under 72 characters
- Be concise and factual
- **ALWAYS reference related issues** - every commit should link to relevant issues
- Use GitHub closing keywords: `Fixes #123`, `Closes #456`, `Resolves #789`
- Use `Refs #N` for related issues that should not auto-close
- Use lowercase for type and scope
- Be humble and modest

**DON'T:**
- Use past tense ("added" or "fixed")
- Include unnecessary details in subject line
- Use vague descriptions ("update stuff", "fix bug")
- Omit issue references - always link commits to their context
- Use closing keywords (`Fixes`) when you only mean to reference (`Refs`)

## Pre-Commit Context Gathering (Recommended)

Before committing, gather all context in one command:

```bash
# Basic context: status, staged files, diff stats, recent log
bash "${CLAUDE_PLUGIN_ROOT}/skills/git-commit-workflow/scripts/commit-context.sh"

# With issue matching: also fetches open GitHub issues for auto-linking
bash "${CLAUDE_PLUGIN_ROOT}/skills/git-commit-workflow/scripts/commit-context.sh" --with-issues
```

The script outputs: branch info, staged/unstaged status, diff stats, detected scopes, recent commit style, pre-commit config status, and optionally open issues. Use this output to compose the commit message. See [scripts/commit-context.sh](scripts/commit-context.sh) for details.

## Explicit Staging Workflow

### Always Stage Files Individually

```bash
# Show current status
git status --porcelain

# Stage files one by one for visibility
git add src/auth/login.ts
git add src/auth/oauth.ts
git status  # Verify what's staged

# Show what will be committed
git diff --cached --stat
git diff --cached  # Review actual changes

# Commit with conventional message
git commit -m "feat(auth): add OAuth2 support"
```

## Commit Message Formatting

### HEREDOC Pattern (Required)

**ALWAYS use HEREDOC directly in git commit.**

```bash
git commit -m "$(cat <<'EOF'
feat(auth): add OAuth2 support

Implements token refresh and secure storage.

Fixes #123
EOF
)"
```

## Communication Style

### Humble, Fact-Based Messages

```bash
# Good: Concise, factual, modest
git commit -m "fix(auth): handle edge case in token refresh"

git commit -m "feat(api): add pagination support

Implements cursor-based pagination for list endpoints.
Includes tests and documentation."
```

Focus on facts: **What changed**, **Why it changed** (if non-obvious), and **Impact** (breaking changes).

## Issue Reference Summary

| Scenario | Pattern | Example |
|----------|---------|---------|
| Bug fix resolving issue | `Fixes #N` | `Fixes #123` |
| Feature completing issue | `Closes #N` | `Closes #456` |
| Related but not completing | `Refs #N` | `Refs #789` |
| Cross-repository | `Fixes owner/repo#N` | `Fixes org/lib#42` |
| Multiple issues | Repeat keyword | `Fixes #1, fixes #2` |

## Best Practices

### Commit Frequency

- **Commit early and often**: Small, focused commits
- **One logical change per commit**: Easier to review and revert
- **Keep commits atomic**: Each commit should be a complete, working state

### Commit Message Length

```bash
# Subject line: <= 72 characters
feat(auth): add OAuth2 support

# Body: <= 72 characters per line (wrap)
# Use blank line between subject and body
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Pre-commit context | `bash "${CLAUDE_PLUGIN_ROOT}/skills/git-commit-workflow/scripts/commit-context.sh"` |
| Context + issues | `bash "${CLAUDE_PLUGIN_ROOT}/skills/git-commit-workflow/scripts/commit-context.sh" --with-issues` |
| Quick status | `git status --porcelain` |
| Staged diff stats | `git diff --cached --stat` |
| Recent commit style | `git log --format='%s' -5` |
| Open issues for linking | `gh issue list --state open --json number,title --limit 30` |
