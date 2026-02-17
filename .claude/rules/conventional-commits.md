---
created: 2026-02-14
modified: 2026-02-14
reviewed: 2026-02-14
---

# Conventional Commits Standards

Both commit messages and PR titles must follow conventional commit format to drive release-please automation and maintain consistent git history.

## Format

```
<type>(<scope>): <subject>

[optional body]

[optional footer(s)]
```

## Types

| Type | Use Case | Version Bump | Example |
|------|----------|--------------|---------|
| `feat` | New feature | Minor | `feat(auth): add OAuth2 support` |
| `fix` | Bug fix | Patch | `fix(api): handle timeout edge case` |
| `perf` | Performance improvement | Patch | `perf(db): optimize query indexing` |
| `refactor` | Code restructure (no behavior change) | None | `refactor(core): simplify error handling` |
| `docs` | Documentation only | None | `docs(readme): update installation steps` |
| `test` | Test changes | None | `test(auth): add OAuth flow tests` |
| `ci` | CI/CD configuration | None | `ci(workflows): add release automation` |
| `build` | Build system or dependencies | None | `build(deps): upgrade TypeScript to v5` |
| `chore` | Maintenance, tooling | None | `chore(deps): update dev dependencies` |
| `revert` | Revert previous commit | Varies | `revert: feat(auth): add OAuth2 support` |

## Type Selection Decision Tree

```
What changed?
├─ New functionality added? → feat
├─ Bug fixed? → fix
├─ Performance improved? → perf
├─ Code restructured (behavior unchanged)? → refactor
├─ Documentation updated? → docs
├─ Tests added/modified? → test
├─ CI/CD changed? → ci
├─ Build/deps changed? → build
├─ Everything else (cleanup, setup)? → chore
└─ Reverting a prior commit? → revert
```

## Scope

Optional component or area identifier. Choose from:

### Scope Selection Rules

1. **Use consistent scopes** - Look at recent commits to match existing scope names
2. **Keep short** - 1-3 words, kebab-case
3. **Be specific** - Name the component/feature affected
4. **Omit if unclear** - Bare `feat:` is better than vague scope

### Discovering Scopes

```bash
# Show most common scopes in recent commits
git log --format='%s' -n 50 | grep -oE '\([^)]+\)' | sort | uniq -c | sort -rn

# Or from PRs (for repository patterns)
gh pr list --state merged -L 30 --json title | jq -r '.[].title' | grep -oE '\([^)]+\)' | sort | uniq -c | sort -rn
```

### Common Scope Examples

| Scope | Use For |
|-------|---------|
| `auth` | Authentication, authorization |
| `api` | API endpoints, routes |
| `ui` | User interface, components |
| `db` | Database, queries, migrations |
| `test` | Testing infrastructure |
| `docs` | Documentation |
| `config` | Configuration files |
| `deps` | Dependencies, package management |
| `workflow` | Git workflows, PR handling |

## Subject

The subject line comes after the colon and scope.

### Subject Requirements

- **Imperative mood**: "add" not "adds" or "added"
- **Lowercase start**: After type/scope, begin with lowercase letter
- **No period**: Don't end with punctuation
- **Concise**: Ideally under 50 characters
- **Descriptive**: Clearly states what changed

### Subject Examples

| ❌ Bad | ✅ Good |
|--------|---------|
| `Added login button` | `add login button` |
| `Fixes the null pointer issue.` | `fix null pointer in auth service` |
| `Update` | `update dependencies` |
| `Changed API response format` | `change API response to return timestamps` |
| `Adds OAuth2 Support` | `add OAuth2 support` |

### Pattern Templates

- **Feature**: `feat(<scope>): add <what>`
- **Bug fix**: `fix(<scope>): resolve <what>`
- **Improvement**: `perf(<scope>): optimize <what>`
- **Refactor**: `refactor(<scope>): simplify <what>`
- **Docs**: `docs(<scope>): update <what>`

## Breaking Changes

Breaking changes trigger a major version bump and are marked with a `!` suffix before the colon.

### Syntax

```
feat(api)!: redesign authentication endpoints
feat!: require Node.js 18+
fix(db)!: remove deprecated query method
```

### In Commit Body

For longer explanation, include footer:

```
feat(api)!: remove deprecated /v1/users endpoint

BREAKING CHANGE: /v1/users endpoint has been removed. Use /v2/users instead.
- Old endpoint accepted GET requests returning user profile
- New endpoint requires POST with JSON body
- See migration guide: docs/migration/v1-to-v2.md
```

## Issue References

Link commits to GitHub issues using footer keywords:

| Keyword | Effect | Use Case |
|---------|--------|----------|
| `Fixes #N` | Closes issue when merged | Bug fixes |
| `Closes #N` | Closes issue when merged | Features (non-bugs) |
| `Refs #N` | Links without closing | Partial work, references |

### Syntax

```bash
git commit -m "feat(auth): add OAuth2 support

Closes #123
Refs #456"
```

Multiple issues:
```bash
git commit -m "fix(api): handle timeout edge case

Fixes #100
Fixes #101
Refs #102"
```

## Commit Body

Optional detailed explanation after a blank line. Include:

- **What changed** and why
- **Context** for the change
- **Trade-offs** or decisions made
- **Issue links** (Fixes/Closes/Refs)

```
feat(auth): add OAuth2 support

Previously, authentication was only available via basic auth,
limiting enterprise adoption. This adds OAuth2 support for
better security and federated identity management.

Implements:
- OAuth2 authorization code flow
- Token refresh handling
- Scope-based permission validation

Closes #123
Refs #456
```

## Scoped Commits in Monorepos

For monorepos with multiple packages, include the package name as the scope:

```
feat(blueprint-plugin): add new command syntax
fix(git-plugin): handle merge conflicts
docs(configure-plugin): update README
build(packages): upgrade TypeScript to v5
```

Release-please uses scoped commits to determine which packages to release.

## PR Titles

**PR titles MUST follow conventional commit format.** This ensures:

1. Consistent git history when using "squash and merge"
2. Accurate changelog generation by release-please
3. Clear communication of changes via PR list

### PR Title Checklist

- [ ] Starts with valid type (`feat`, `fix`, `docs`, etc.)
- [ ] Includes scope if applicable: `type(scope):`
- [ ] Subject is concise and clear
- [ ] Uses lowercase after colon
- [ ] No trailing period
- [ ] Subject under 50 characters

### Examples

```
feat(auth): add OAuth2 support
fix(api): handle null response in serializer
docs(readme): update installation steps
refactor(core): simplify error handling
perf(db): optimize query performance
```

## Commit Messages vs PR Titles

| Aspect | Commit Message | PR Title |
|--------|----------------|----------|
| Format | Must be conventional | Must be conventional |
| Body | Optional detailed explanation | N/A (use PR description) |
| Scope | Specific component | Specific component |
| When created | Local commit | On PR creation/update |
| Auto-linking | To issues (Fixes/Refs) | Separate PR description |
| Purpose | Individual change | Aggregated changes |

### Workflow

1. **Create commits** with conventional format and issue links
2. **Push to branch**
3. **Create PR** with title matching `git log --format='%s'` of commits being merged
4. **Use PR description** for context on multiple commits

## Release-Please Integration

Conventional commits drive automated versioning:

### Version Bump Logic

```
Any commit with feat: → Minor version bump
Any commit with fix: or perf: → Patch version bump
Any commit with !: → Major version bump
Docs, test, ci, build, chore → No version bump
```

### CHANGELOG Generation

Commits are grouped in CHANGELOG by type:

```markdown
## Features
- add OAuth2 support (abc1234)
- add timeout configuration (def5678)

## Bug Fixes
- fix null pointer in auth service (ghi9012)
- resolve timing issue in scheduler (jkl3456)

## Performance
- optimize database query performance (mno7890)
```

## Validation

### Pre-commit Hooks

Ensure commits follow conventional format:

```bash
# List recent commits to verify format
git log --oneline -n 10

# Check commit format
git log -1 --format='%s'  # Should match pattern
```

### PR Title Validation

Before merging, verify:
```bash
# Get PR title
gh pr view --json title --jq '.title'

# Verify it matches conventional format
```

## Emergency Commits

When immediate action is needed (hotfixes, reverts):

1. Still use conventional format
2. Reference related issues in footer
3. Document reason for urgency in commit body

```
fix(critical): patch XSS vulnerability in auth

CRITICAL: This XSS vulnerability allows token theft.
Apply immediately to all environments.

Affected versions: 1.2.0-1.2.3
Fix: Properly escape OAuth callback URL

Fixes #500
```

## Troubleshooting

### Commit message has wrong format

Fix the commit:
```bash
# If not yet pushed
git commit --amend -m "feat(scope): new message"

# If pushed (rebase or force-push as needed)
git rebase -i HEAD~1
# Edit the commit message
```

### PR title doesn't match commits

Update PR title:
```bash
gh pr edit <NUMBER> --title "feat(scope): new title"
```

### Release-please didn't detect change

Verify:
1. Commit message starts with valid type
2. Type matches `feat`, `fix`, `perf`, `refactor`, `docs`, `test`, `ci`, `build`, `chore`, or `revert`
3. Scope matches package name (in monorepos)

