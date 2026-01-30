---
model: haiku
created: 2026-01-30
modified: 2026-01-30
reviewed: 2026-01-30
name: github-pr-title
description: |
  Craft effective pull request titles using conventional commit format. Use when
  creating PRs, reviewing PR titles, or ensuring consistent PR naming conventions.
  Covers title structure, type prefixes, scope selection, and subject line writing.
allowed-tools: Bash(git log:*), Bash(git diff:*), Bash(gh pr:*), Read, Grep, Glob, TodoWrite
---

# GitHub PR Title

Expert guidance for crafting clear, consistent, and informative pull request titles that communicate changes effectively.

## When to Use This Skill

| Use this skill when... | Use X instead when... |
|------------------------|----------------------|
| Creating a new PR title | Full PR creation workflow (`git-pr`) |
| Reviewing/improving PR titles | Commit message crafting (`git-commit`) |
| Ensuring title conventions | Branch naming (`git-branch-pr-workflow`) |
| Understanding PR title format | Issue title writing (`github-issue-writing`) |

## Core Expertise

- **Conventional Commit Format**: Standard `type(scope): subject` pattern
- **Type Selection**: Choosing the right prefix for changes
- **Scope Definition**: Identifying affected components
- **Subject Writing**: Clear, imperative descriptions
- **Special Cases**: Breaking changes, reverts, WIP

## Title Format

### Standard Structure

```
<type>(<scope>): <subject>
```

| Component | Required | Description |
|-----------|----------|-------------|
| `type` | Yes | Category of change |
| `scope` | Optional | Component/area affected |
| `subject` | Yes | Short description in imperative mood |

### Examples

```
feat(auth): add OAuth2 support
fix(api): handle null response in user endpoint
docs(readme): add installation instructions
refactor(core): extract validation logic
```

## Type Prefixes

### Primary Types

| Type | Meaning | Triggers Version Bump |
|------|---------|----------------------|
| `feat` | New feature | Minor (0.X.0) |
| `fix` | Bug fix | Patch (0.0.X) |
| `docs` | Documentation only | None |
| `style` | Formatting, no code change | None |
| `refactor` | Code restructure, no behavior change | None |
| `perf` | Performance improvement | Patch |
| `test` | Adding/fixing tests | None |
| `build` | Build system or dependencies | None |
| `ci` | CI/CD configuration | None |
| `chore` | Maintenance tasks | None |
| `revert` | Reverting previous changes | Varies |

### Type Selection Decision Tree

```
Does this change add new functionality?
├─ YES → feat
└─ NO → Does it fix a bug?
         ├─ YES → fix
         └─ NO → Does it change code behavior?
                  ├─ YES → Is it performance-related?
                  │        ├─ YES → perf
                  │        └─ NO → refactor (if internal), feat (if user-facing)
                  └─ NO → Is it documentation?
                           ├─ YES → docs
                           └─ NO → Is it tests?
                                    ├─ YES → test
                                    └─ NO → Is it CI/build?
                                             ├─ YES → ci or build
                                             └─ NO → chore
```

## Scope Selection

### Common Scopes

| Pattern | Examples | Use For |
|---------|----------|---------|
| Component | `auth`, `api`, `ui`, `db` | Feature areas |
| Layer | `core`, `utils`, `middleware` | Architecture layers |
| Package | `cli`, `sdk`, `web` | Monorepo packages |
| File type | `deps`, `config`, `types` | File category changes |

### Scope Guidelines

- **Be consistent**: Use the same scope for related changes
- **Keep it short**: 1-2 words, lowercase, hyphenated if needed
- **Match directory structure**: Often aligns with folder names
- **Omit if unclear**: No scope is better than wrong scope

### Repository-Specific Scopes

Discover scopes from existing PRs:

```bash
# Extract scopes from recent PR titles
gh pr list --state merged --limit 50 --json title | \
  jq -r '.[].title' | \
  grep -oE '^\w+\(([^)]+)\)' | \
  sed 's/.*(\(.*\))/\1/' | \
  sort | uniq -c | sort -rn
```

## Subject Line Writing

### Rules

1. **Imperative mood**: "add" not "adds" or "added"
2. **No period at end**: Titles don't end with punctuation
3. **Lowercase start**: After the colon, start with lowercase
4. **Under 50 chars**: Subject portion (after `type(scope): `)
5. **Complete the sentence**: "This PR will..." + subject

### Imperative Verb Reference

| Action | Verbs |
|--------|-------|
| Adding | add, create, implement, introduce |
| Removing | remove, delete, drop, deprecate |
| Fixing | fix, resolve, correct, repair |
| Changing | update, change, modify, adjust |
| Improving | improve, enhance, optimize, refine |
| Refactoring | refactor, restructure, reorganize, extract |
| Moving | move, rename, relocate, migrate |

### Good vs Bad Subjects

| Bad | Good | Why |
|-----|------|-----|
| `Added new login feature` | `add login feature` | Imperative, no "new" |
| `Fixes the bug` | `fix null pointer in auth` | Specific, no "the" |
| `Update` | `update dependencies to latest` | Be specific |
| `Changes to the API.` | `add pagination to list endpoint` | No period, specific |
| `WIP` | `feat(api): add user endpoints (WIP)` | Use proper format |

## Deriving Titles from Changes

### From Commit Messages

```bash
# Get commits in branch vs main
git log main..HEAD --format='%s' --reverse

# First commit often defines the PR purpose
git log main..HEAD --format='%s' --reverse | head -1
```

### From Diff Analysis

```bash
# Get changed files to determine scope
git diff main..HEAD --name-only | \
  head -5 | \
  xargs -I{} dirname {} | \
  sort | uniq

# Get diff stats for subject hints
git diff main..HEAD --stat | tail -1
```

### Title Generation Logic

1. **Single commit**: Use commit message as title
2. **Multiple commits, same scope**: Summarize with common scope
3. **Multiple commits, mixed scope**: Omit scope, use broader subject
4. **Breaking changes**: Use `feat!` or `fix!` prefix

## Special Cases

### Breaking Changes

Use `!` after type or scope:

```
feat!: remove deprecated API endpoints
feat(api)!: change authentication to OAuth2 only
fix!: require Node.js 18+
```

### Reverts

Follow revert convention:

```
revert: feat(auth): add OAuth2 support
```

Or reference the PR:

```
revert: revert PR #123
```

### Work in Progress

Two approaches:

```
# Draft PR (preferred)
gh pr create --draft --title "feat(auth): add OAuth2 support"

# WIP prefix (legacy)
WIP: feat(auth): add OAuth2 support
```

### Multiple Types

When PR includes multiple change types:

1. **Primary type wins**: Use the most significant type
2. **Feature over fix**: `feat` if adding and fixing
3. **Split if needed**: Consider separate PRs for distinct changes

### Dependency Updates

```
build(deps): bump lodash from 4.17.20 to 4.17.21
chore(deps): update dev dependencies
build(deps): upgrade to TypeScript 5.0
```

## Title Length

### Limits

| Guideline | Length |
|-----------|--------|
| Ideal subject | < 50 chars |
| Max subject | 72 chars |
| Total with type/scope | < 100 chars |

### Shortening Techniques

| Too Long | Shortened |
|----------|-----------|
| `add validation for user input in registration form` | `add registration input validation` |
| `fix issue where users cannot log in after password reset` | `fix login after password reset` |
| `update documentation to include new API endpoints` | `document new API endpoints` |

## Integration with Release Tools

### Semantic Release / Release Please

PR titles directly affect changelog generation:

| Title | Changelog Section |
|-------|------------------|
| `feat: ...` | Features |
| `fix: ...` | Bug Fixes |
| `perf: ...` | Performance |
| `docs: ...` | Documentation |
| `feat!: ...` | BREAKING CHANGES |

### Squash Merge Behavior

When "squash and merge" is used:
- PR title becomes the squash commit message
- Ensures clean history
- PR title format is critical

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Get commits | `git log main..HEAD --format='%s' -n 10` |
| Get scopes | `gh pr list --state merged -L 30 --json title \| jq -r '.[].title'` |
| Changed dirs | `git diff main..HEAD --name-only \| xargs dirname \| sort -u` |
| Update PR title | `gh pr edit N --title "new title"` |
| View PR | `gh pr view N --json title` |

## Quick Reference

### Title Templates

| Scenario | Template |
|----------|----------|
| New feature | `feat(<scope>): add <feature>` |
| Bug fix | `fix(<scope>): resolve <issue>` |
| Documentation | `docs(<area>): update <what>` |
| Dependency | `build(deps): bump <package> to <version>` |
| Refactor | `refactor(<scope>): extract <what>` |
| Breaking | `feat(<scope>)!: change <what>` |
| Revert | `revert: <original title>` |
| CI | `ci: update <what>` |

### Validation Checklist

- [ ] Starts with valid type prefix
- [ ] Scope is consistent with repo conventions
- [ ] Subject uses imperative mood
- [ ] Subject is specific and descriptive
- [ ] No period at end
- [ ] Total length under 100 characters
- [ ] Breaking changes marked with `!`

### Common Mistakes

| Mistake | Fix |
|---------|-----|
| `Feat: Add login` | `feat: add login` (lowercase) |
| `fix: Fixed the bug` | `fix: resolve login timeout` (imperative) |
| `update things` | `chore(deps): update dependencies` (add type) |
| `feat(): add feature` | `feat: add feature` (remove empty scope) |
| `feat(auth/login): add sso` | `feat(auth): add SSO login` (simplify scope) |
