# Git Commit Workflow - Reference

Detailed reference material for scope guidelines, staging workflows, issue references, logical change grouping, and troubleshooting.

## Scope Guidelines

Common scopes by area:

```bash
# Feature areas
feat(auth): login system changes
feat(api): API endpoint changes
feat(ui): user interface changes
feat(db): database schema changes

# Component-specific
fix(header): navigation menu bug
fix(footer): copyright date
fix(sidebar): responsive layout

# Infrastructure
chore(deps): dependency updates
chore(ci): CI/CD configuration
chore(docker): container configuration
```

## Pre-commit Hook Integration

Pre-commit hooks often AUTO-MODIFY files (formatters, linters with autofix). This is expected behavior.

```bash
# 1. Run pre-commit checks
pre-commit run --all-files --show-diff-on-failure

# 2. Check if pre-commit modified any files
git status --porcelain
# M  src/file.ts     <- Modified by pre-commit (formatting)

# 3. Stage modified tracked files (original + pre-commit modifications)
git add -u

# 4. Verify pre-commit passes now
pre-commit run --all-files  # Should exit 0

# 5. Commit with all changes
git commit -m "feat(feature): add feature with formatting fixes"
```

**Understanding Pre-commit Exit Codes:**
- Exit 0: All hooks passed
- Exit 1: Hook failed OR files were modified (re-stage and re-run)

Pre-commit file modifications are normal - stage them and proceed with the commit.

## Logical Change Grouping

### Group Related Changes

```bash
# Example: Authentication feature with multiple files
# Group 1: Core implementation
git add src/auth/oauth.ts
git add src/auth/token.ts
git commit -m "feat(auth): implement OAuth2 token handling"

# Group 2: Tests
git add tests/auth/oauth.test.ts
git add tests/auth/token.test.ts
git commit -m "test(auth): add OAuth2 integration tests"

# Group 3: Documentation
git add docs/api/authentication.md
git add README.md
git commit -m "docs(auth): document OAuth2 flow"
```

### Separate Concerns

```bash
# Example: Mixed changes
# Separate linter fixes from feature work

# Group 1: Linter/formatting (chore commit)
git add src/**/*.ts  # (only formatting changes)
git add .eslintrc
git commit -m "chore(lint): apply ESLint fixes and update config"

# Group 2: Feature implementation (feat commit)
git add src/feature/implementation.ts
git add tests/feature.test.ts
git commit -m "feat(feature): add new user management feature"
```

### Change Classification

**Linter/Formatting Group:**
- Whitespace-only changes
- Lock files (package-lock.json, Cargo.lock)
- Auto-generated linter configs
- Commit type: `chore`

**Feature/Fix Groups:**
- Implementation code
- Related tests
- Relevant documentation
- Commit type: `feat`, `fix`, `refactor`

**Documentation Group:**
- README updates
- API documentation
- User guides
- Commit type: `docs`

## GitHub Issue References (Autolink Format)

**ALWAYS reference related GitHub issues in commit messages.** This creates traceability, enables project management, and provides context for future code archaeology.

### Autolink Reference Formats

GitHub automatically converts these patterns into clickable links:

| Format | Example | Use Case |
|--------|---------|----------|
| `#N` | `#123` | Same repository issue/PR |
| `GH-N` | `GH-123` | Alternative same-repo format |
| `owner/repo#N` | `octo-org/api#456` | Cross-repository reference |

### Closing Keywords

GitHub recognizes **9 keywords** to automatically close issues when commits merge to the default branch:

| Keyword | Variants | Effect |
|---------|----------|--------|
| close | `close`, `closes`, `closed` | Closes the issue |
| fix | `fix`, `fixes`, `fixed` | Closes the issue |
| resolve | `resolve`, `resolves`, `resolved` | Closes the issue |

### Reference Syntax Patterns

```bash
# Close issue in same repository
Fixes #123
Closes #456
Resolves #789

# Close issue in different repository
Fixes octo-org/octo-repo#100

# Close multiple issues (use full keyword for each)
Fixes #123, fixes #456, fixes #789

# Reference without closing (for related context)
Refs #234
Related to #567
See #890
```

### Formatting Flexibility

- **Case insensitive:** `FIXES #123`, `Fixes #123`, `fixes #123`
- **Optional colon:** `Fixes: #123`, `Fixes #123`
- **Whitespace:** `Fixes #123` or `Fixes#123` (space optional)

### When to Use Each Pattern

| Scenario | Pattern | Example |
|----------|---------|---------|
| Bug fix that resolves an issue | `Fixes #N` | `Fixes #123` |
| Feature that completes an issue | `Closes #N` | `Closes #456` |
| Work related to but not completing issue | `Refs #N` | `Refs #789` |
| Partial progress on larger issue | `Refs #N` | `Refs #101` |
| Breaking change with migration guide | `See #N` | `See #202` |

**Important:** Keywords only auto-close issues when merged to the **default branch**. PRs targeting other branches link but don't auto-close.

### Automatic Issue Detection

Before creating commits, scan open issues to find matches for staged changes:

```bash
# Fetch open issues for matching
gh issue list --state open --json number,title,labels --limit 30

# Get changed files for analysis
git diff --cached --name-only
```

**Matching Heuristics:**
- File paths mentioned in issue body -> High confidence
- Error messages or function names match -> High confidence
- Directory/component matches issue labels -> Medium confidence
- Keyword overlap in issue title -> Medium confidence

**See:** **github-issue-autodetect** skill for full detection algorithm and decision tree.

### Issue Reference Examples

```bash
# Fix with auto-close (single issue)
git commit -m "fix(api): handle timeout

Fixes #123"

# Feature linked to multiple issues
git commit -m "feat(ui): redesign dashboard

Implements designs from #456
Closes #457, closes #458"

# Cross-repository reference
git commit -m "fix(shared): resolve validation bug

Fixes org/shared-lib#42"

# Breaking change with migration reference
git commit -m "feat(api)!: change authentication

BREAKING CHANGE: API key format changed.
See migration guide: #789"

# Reference without closing (use "Refs" or "Related to")
git commit -m "refactor(auth): extract token validation

Refs #234"
```

## Workflow Examples

### Complete Staging and Commit Flow

```bash
# 1. Check current state
git status

# 2. Run pre-commit checks
pre-commit run --all-files

# 3. Stage files explicitly
git add src/feature.ts
git add tests/feature.test.ts

# 4. Review what's staged
git status
git diff --cached --stat

# 5. Commit with conventional message
git commit -m "feat(feature): add new capability

Implements X feature with Y functionality.
Includes unit tests and integration tests.

Closes #123"

# 6. Verify commit
git log -1 --stat
```

### Amending Commits

```bash
# Fix last commit (before pushing)
git add forgotten-file.ts
git commit --amend --no-edit

# Update commit message
git commit --amend -m "feat(auth): improved OAuth2 implementation"
```

### Interactive Staging

```bash
# Stage parts of a file
git add -p file.ts

# Review hunks and choose:
# y - stage this hunk
# n - do not stage
# s - split into smaller hunks
# e - manually edit hunk
```

## Troubleshooting

### Accidentally Staged Wrong Files

```bash
# Unstage specific file
git restore --staged wrong-file.ts

# Unstage all
git restore --staged .
```

### Wrong Commit Message

```bash
# Amend last commit message (before push)
git commit --amend -m "corrected message"

# After push (prefer pre-push correction when possible)
git commit --amend -m "corrected message"
git push --force-with-lease origin branch-name
```

### Forgot to Add File to Last Commit

```bash
# Add file and amend
git add forgotten-file.ts
git commit --amend --no-edit
```

### Need to Split Last Commit

```bash
# Undo last commit but keep changes staged
git reset --soft HEAD~1

# Unstage all
git restore --staged .

# Stage and commit in groups
git add group1-file.ts
git commit -m "first logical group"

git add group2-file.ts
git commit -m "second logical group"
```
