---
model: haiku
created: 2026-01-30
modified: 2026-02-14
reviewed: 2026-02-14
name: github-pr-title
description: |
  Craft PR titles using conventional commits format. Use when creating PRs or
  ensuring consistent PR naming. PR titles MUST follow conventional commits to
  drive release-please automation and maintain consistent git history.
allowed-tools: Bash(git log *), Bash(git diff *), Bash(gh pr *), Read, Grep, Glob, TodoWrite
---

# GitHub PR Title

Craft clear PR titles using conventional commits format.

**CRITICAL:** PR titles must follow conventional commit format. This drives release-please version automation and ensures consistent git history when using squash-and-merge.

## When to Use

| Use this skill when... | Use X instead when... |
|------------------------|----------------------|
| Creating a PR title | Full PR workflow (`git-pr`) |
| Reviewing title format | Issue titles (`github-issue-writing`) |
| Updating existing PR title | Fixing committed messages (see `git-commit`) |

## Format

```
<type>(<scope>): <subject>
```

See [Conventional Commits Standards](../../.claude/rules/conventional-commits.md) for comprehensive format guide.

### Type Selection

| Type | Use Case | Version Bump |
|------|----------|--------------|
| `feat` | New feature | Minor |
| `fix` | Bug fix | Patch |
| `perf` | Performance improvement | Patch |
| `refactor` | Code restructure (no behavior change) | None |
| `docs` | Documentation only | None |
| `test` | Tests | None |
| `build` | Build/deps | None |
| `ci` | CI config | None |
| `chore` | Maintenance | None |

**Decision tree:** Feature → `feat` | Bug → `fix` | Performance → `perf` | Restructure → `refactor` | Docs → `docs` | Everything else → `chore`

### Scope

Optional component identifier. Keeps commits organized:

```
feat(auth): add OAuth support
fix(api): handle null response
docs(readme): update install steps
refactor(core): simplify error handling
```

**Discover repo scopes:**
```bash
gh pr list --state merged -L 30 --json title | jq -r '.[].title' | grep -oE '\([^)]+\)' | sort | uniq -c | sort -rn
```

Or from commits:
```bash
git log --format='%s' -n 50 | grep -oE '\([^)]+\)' | sort | uniq -c | sort -rn
```

### Subject

- **Imperative mood**: "add" not "adds" or "added"
- **Lowercase**: Start with lowercase after colon
- **No period**: Don't end with punctuation
- **Under 50 chars**: Keep concise

**Examples:**

| ❌ Bad | ✅ Good |
|--------|---------|
| `Added login button` | `add login button` |
| `Fixes the bug.` | `fix null pointer in auth` |
| `Update` | `update dependencies` |
| `Resolved Performance Issues` | `improve query performance` |

### Breaking Changes

Append `!` before colon:

```
feat(api)!: remove deprecated endpoints
fix!: require Node.js 18+
refactor(db)!: change schema format
```

Breaking changes trigger major version bumps.

### Reverts

```
revert: feat(auth): add OAuth support
```

## Quick Reference

| Scenario | Template |
|----------|----------|
| Feature | `feat(<scope>): add <what>` |
| Bug fix | `fix(<scope>): resolve <what>` |
| Performance | `perf(<scope>): optimize <what>` |
| Docs | `docs(<scope>): update <what>` |
| Refactor | `refactor(<scope>): simplify <what>` |
| Deps | `build(deps): bump <pkg> to <ver>` |
| Breaking | `feat(<scope>)!: change <what>` |

## Why This Matters

**Conventional commit PR titles ensure:**

1. **Accurate automation** - release-please reads PR titles to determine version bumps
2. **Clean git history** - squash-and-merge uses PR title as commit message
3. **Searchable commits** - type prefix makes filtering easy
4. **CHANGELOG accuracy** - commits are grouped by type in generated changelogs

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Get commits | `git log main..HEAD --format='%s' -n 10` |
| Changed dirs | `git diff main..HEAD --name-only \| xargs dirname \| sort -u` |
| Update title | `gh pr edit N --title "new title"` |
| Discover scopes | `gh pr list --state merged -L 30 --json title \| jq -r '.[].title' \| grep -oE '\([^)]+\)' \| sort \| uniq` |

## Reference

For detailed rules, patterns, and troubleshooting, see [Conventional Commits Standards](../../.claude/rules/conventional-commits.md).
