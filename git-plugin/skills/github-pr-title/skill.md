---
model: haiku
created: 2026-01-30
modified: 2026-01-30
reviewed: 2026-01-30
name: github-pr-title
description: |
  Craft PR titles using conventional commits format. Use when creating PRs or
  ensuring consistent PR naming. Covers type prefixes, scope, and subject writing.
allowed-tools: Bash(git log:*), Bash(git diff:*), Bash(gh pr:*), Read, Grep, Glob, TodoWrite
---

# GitHub PR Title

Craft clear PR titles using conventional commits format.

## When to Use

| Use this skill when... | Use X instead when... |
|------------------------|----------------------|
| Creating a PR title | Full PR workflow (`git-pr`) |
| Reviewing title format | Issue titles (`github-issue-writing`) |

## Format

```
<type>(<scope>): <subject>
```

### Types

| Type | Use For | Version Bump |
|------|---------|--------------|
| `feat` | New feature | Minor |
| `fix` | Bug fix | Patch |
| `docs` | Documentation only | None |
| `refactor` | Code restructure | None |
| `perf` | Performance | Patch |
| `test` | Tests | None |
| `build` | Build/deps | None |
| `ci` | CI config | None |
| `chore` | Maintenance | None |

### Type Selection

```
New functionality? → feat
Bug fix? → fix
Performance? → perf
Code restructure (no behavior change)? → refactor
Documentation? → docs
Tests? → test
CI/build? → ci or build
Everything else → chore
```

### Scope

Optional component identifier. Keep short, lowercase:

```
feat(auth): add OAuth support
fix(api): handle null response
docs(readme): update install steps
```

Discover repo scopes:
```bash
gh pr list --state merged -L 30 --json title | jq -r '.[].title' | grep -oE '\([^)]+\)' | sort | uniq -c | sort -rn
```

### Subject

- **Imperative mood**: "add" not "adds" or "added"
- **No period**: Don't end with punctuation
- **Lowercase**: Start with lowercase after colon
- **< 50 chars**: Keep subject concise

| Bad | Good |
|-----|------|
| `Added login` | `add login` |
| `Fixes the bug.` | `fix null pointer in auth` |
| `Update` | `update dependencies` |

### Breaking Changes

Use `!` suffix:

```
feat(api)!: remove deprecated endpoints
fix!: require Node.js 18+
```

### Reverts

```
revert: feat(auth): add OAuth support
```

## Quick Reference

| Scenario | Template |
|----------|----------|
| Feature | `feat(<scope>): add <what>` |
| Bug fix | `fix(<scope>): resolve <issue>` |
| Docs | `docs(<area>): update <what>` |
| Deps | `build(deps): bump <pkg> to <ver>` |
| Breaking | `feat(<scope>)!: change <what>` |

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Get commits | `git log main..HEAD --format='%s' -n 10` |
| Changed dirs | `git diff main..HEAD --name-only \| xargs dirname \| sort -u` |
| Update title | `gh pr edit N --title "new title"` |
