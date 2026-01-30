---
model: haiku
name: git-branch-naming
description: |
  Git branch naming conventions for consistent, traceable branches. Use when creating
  new branches, discussing branch naming standards, or setting up repository conventions.
  Covers type prefixes (feat, fix, chore), issue linking, and kebab-case formatting.
allowed-tools: Bash, Read, Grep, Glob
created: 2026-01-30
modified: 2026-01-30
reviewed: 2026-01-30
---

# Git Branch Naming Conventions

Consistent branch naming improves traceability, enables automation, and makes repository history easier to navigate.

## When to Use This Skill

| Use this skill when... | Use something else when... |
|------------------------|---------------------------|
| Creating a new feature/fix branch | Managing PR workflows → `git-branch-pr-workflow` |
| Setting up team branch conventions | Committing changes → `git-commit-workflow` |
| Discussing naming standards | Rebase/merge strategies → `git-branch-pr-workflow` |

## Branch Name Format

```
{type}/{issue}-{short-description}
```

| Component | Format | Required | Example |
|-----------|--------|----------|---------|
| `type` | Lowercase prefix | Yes | `feat`, `fix` |
| `issue` | Issue number, no `#` | If issue exists | `123` |
| `description` | kebab-case, 2-5 words | Yes | `user-authentication` |

### Examples

```bash
# With issue number (preferred when issue exists)
feat/123-oauth-login
fix/456-null-pointer-crash
chore/789-update-dependencies
docs/101-api-reference

# Without issue number (when no issue exists)
feat/oauth-integration
fix/memory-leak-cleanup
chore/update-eslint-config
refactor/auth-service-split
```

## Branch Types

| Type | Purpose | Conventional Commit |
|------|---------|---------------------|
| `feat/` | New features, capabilities | `feat:` |
| `fix/` | Bug fixes | `fix:` |
| `chore/` | Maintenance, deps, config | `chore:` |
| `docs/` | Documentation only | `docs:` |
| `refactor/` | Code restructuring, no behavior change | `refactor:` |
| `test/` | Adding/updating tests | `test:` |
| `ci/` | CI/CD pipeline changes | `ci:` |
| `hotfix/` | Emergency production fixes | `fix:` (with urgency) |
| `release/` | Release preparation | `chore:` or `release:` |

## Creating Branches

### Standard Workflow

```bash
# With issue number
git switch -c feat/123-user-authentication

# Without issue number
git switch -c fix/login-timeout-handling

# From specific base
git switch -c feat/456-payment-api main
git switch -c hotfix/security-patch production
```

### Validation Pattern

Before creating, validate the format:

```bash
# Branch name regex pattern
^(feat|fix|chore|docs|refactor|test|ci|hotfix|release)/([0-9]+-)?[a-z0-9]+(-[a-z0-9]+)*$
```

Valid:
- `feat/123-user-auth` ✓
- `fix/memory-leak` ✓
- `chore/update-deps` ✓

Invalid:
- `feature/user-auth` ✗ (use `feat`, not `feature`)
- `fix/UserAuth` ✗ (use kebab-case, not PascalCase)
- `my-branch` ✗ (missing type prefix)
- `feat/fix_bug` ✗ (use hyphens, not underscores)

## Issue Linking Best Practices

### When to Include Issue Numbers

| Scenario | Include Issue? | Example |
|----------|----------------|---------|
| Work tracked in GitHub Issues | Yes | `feat/123-add-oauth` |
| Work tracked in external system (Jira, Linear) | Optional | `feat/PROJ-456-oauth` or `feat/oauth` |
| Exploratory/spike work | No | `spike/auth-approaches` |
| Quick fix without issue | No | `fix/typo-readme` |
| Dependabot/automated PRs | No | `chore/bump-lodash` |

### External Ticket Systems

For Jira, Linear, or other systems, use the ticket ID:

```bash
feat/PROJ-123-user-dashboard
fix/LINEAR-456-api-timeout
chore/JIRA-789-update-sdk
```

## Description Guidelines

### Good Descriptions

| Pattern | Example | Why Good |
|---------|---------|----------|
| Action + Target | `add-oauth-login` | Clear what's being done |
| Component + Change | `auth-service-refactor` | Identifies affected area |
| Bug + Context | `null-pointer-user-save` | Describes the issue |

### Avoid

| Anti-pattern | Problem | Better |
|--------------|---------|--------|
| `fix/bug` | Too vague | `fix/123-login-validation` |
| `feat/new-feature` | Meaningless | `feat/user-dashboard` |
| `feat/john-working-on-stuff` | Not descriptive | `feat/456-payment-flow` |
| `fix/issue-123` | Redundant, no description | `fix/123-timeout-error` |
| `feat/add-new-user-authentication-system-with-oauth` | Too long | `feat/oauth-authentication` |

### Length Guidelines

- **Minimum:** 2 words after type/issue (`feat/123-user-auth`)
- **Maximum:** 5 words, ~50 characters total
- **Sweet spot:** 3-4 words (`feat/123-oauth-token-refresh`)

## Special Branch Patterns

### Release Branches

```bash
release/1.0.0
release/2.1.0-beta
release/v3.0.0-rc1
```

### Hotfix Branches

```bash
hotfix/security-vulnerability
hotfix/critical-data-loss
hotfix/production-crash-fix
```

### Long-Running Branches

For multi-week efforts, consider date suffix:

```bash
feat/123-major-refactor-2026q1
epic/new-billing-system
```

## Team Conventions

### User-Prefixed Branches (Optional)

For large teams where branch ownership matters:

```bash
# Pattern: {user}/{type}/{description}
alice/feat/123-oauth
bob/fix/456-memory-leak

# Or: {type}/{user}-{description}
feat/alice-oauth-integration
fix/bob-memory-leak
```

### Protected Branch Patterns

Configure branch protection for:

```
main
master
develop
release/*
hotfix/*
```

## Automation Integration

### Branch Name → Commit Scope

The branch type can inform commit message scope:

| Branch | Suggested Commits |
|--------|-------------------|
| `feat/123-auth` | `feat(auth): ...` |
| `fix/456-api` | `fix(api): ...` |
| `docs/readme` | `docs: ...` |

### CI/CD Triggers

Common patterns for CI pipeline triggers:

```yaml
# GitHub Actions example
on:
  push:
    branches:
      - 'feat/**'
      - 'fix/**'
      - 'hotfix/**'
  pull_request:
    branches:
      - main
```

## Quick Reference

### Branch Creation Checklist

- [ ] Starts with valid type prefix (`feat/`, `fix/`, etc.)
- [ ] Issue number included (if tracked work)
- [ ] Description is kebab-case
- [ ] Description is 2-5 words
- [ ] Total length under 50 characters
- [ ] No underscores, spaces, or uppercase

### Command Reference

| Action | Command |
|--------|---------|
| Create branch | `git switch -c feat/123-description` |
| List by type | `git branch --list 'feat/*'` |
| Delete local | `git branch -d feat/123-description` |
| Delete remote | `git push origin --delete feat/123-description` |
| Rename | `git branch -m old-name new-name` |

### Type Selection Flowchart

```
Is it a bug fix? → fix/
Is it a new capability? → feat/
Is it documentation? → docs/
Is it maintenance/deps? → chore/
Is it restructuring code? → refactor/
Is it adding tests? → test/
Is it CI/CD changes? → ci/
Is it an emergency? → hotfix/
```
