---
created: 2026-01-15
modified: 2026-01-15
reviewed: 2026-01-15
name: github-issue-autodetect
description: |
  Automatically detect GitHub issues that staged changes may fix or close.
  Analyzes diffs, file paths, and issue metadata to suggest appropriate
  closing keywords (Fixes, Closes, Resolves) for commit messages.
  Use when committing changes to ensure proper issue linkage.
allowed-tools: Bash, Read, Grep, Glob, mcp__github__list_issues, mcp__github__get_issue
---

# GitHub Issue Auto-Detection

Expert guidance for automatically detecting GitHub issues that staged changes may fix or close, ensuring proper issue linkage in commit messages.

## Core Expertise

- **Issue Detection**: Match staged changes to open issues
- **Keyword Selection**: Choose appropriate closing vs reference keywords
- **Context Analysis**: Parse issue titles, bodies, and labels for relevance
- **File Path Matching**: Correlate changed files to issue descriptions

## Detection Workflow

### Step 1: Fetch Open Issues

```bash
# Get open issues with relevant metadata (using gh CLI)
gh issue list --state open --json number,title,body,labels --limit 50

# Or filter by specific labels for targeted detection
gh issue list --state open --label bug --json number,title,body
gh issue list --state open --label enhancement --json number,title,body
```

### Step 2: Analyze Staged Changes

```bash
# Get list of changed files
git diff --cached --name-only

# Get detailed diff for content analysis
git diff --cached

# Get summary of changes
git diff --cached --stat
```

### Step 3: Match Issues to Changes

Analyze staged changes against issues using these heuristics:

| Signal | Weight | Example |
|--------|--------|---------|
| File path in issue body | High | Issue mentions `src/auth/login.ts`, diff includes that file |
| Error message match | High | Issue title contains error text found in diff |
| Component/scope match | Medium | Issue labeled `auth`, changes are in `src/auth/` |
| Keyword overlap | Medium | Issue mentions "login", diff modifies login logic |
| Function name match | Medium | Issue references `validateToken()`, diff modifies it |

### Detection Algorithm

```
For each staged file:
  1. Extract file path components (directory, filename, extension)
  2. Extract modified function/class names from diff
  3. Extract error messages or string literals from diff

For each open issue:
  1. Parse title for keywords, file references, error messages
  2. Parse body for code snippets, file paths, stack traces
  3. Check labels for component/area tags

Score each (file, issue) pair:
  - +3 points: Exact file path match
  - +2 points: Error message or function name match
  - +1 point: Directory/component match
  - +1 point: Keyword overlap (>2 significant words)

Report issues with score >= 2 as potential matches
```

## Keyword Selection Guide

### Closing Keywords (Auto-Close on Merge)

Use when the commit **fully resolves** the issue:

| Keyword | Use Case |
|---------|----------|
| `Fixes #N` | Bug fixes - something was broken, now it works |
| `Closes #N` | Feature completion - requested feature is implemented |
| `Resolves #N` | General resolution - issue is addressed |

### Reference Keywords (Link Without Closing)

Use when the commit **relates to** but doesn't fully resolve:

| Keyword | Use Case |
|---------|----------|
| `Refs #N` | Partial progress toward issue |
| `Related to #N` | Tangentially related changes |
| `See #N` | Context or discussion reference |
| `Part of #N` | One of multiple commits for an issue |

### Decision Tree

```
Is this commit the FINAL fix for the issue?
├─ YES → Is it a bug fix?
│        ├─ YES → Use "Fixes #N"
│        └─ NO → Use "Closes #N"
└─ NO → Does it make progress on the issue?
         ├─ YES → Use "Refs #N"
         └─ NO → Use "Related to #N" or omit
```

## Common Patterns

### Bug Fix Detection

```bash
# Issue: "Login fails with 'invalid token' error"
# Staged changes in: src/auth/token.ts

# Detection signals:
# - File path: src/auth/* matches "Login" context
# - Error message: "invalid token" may appear in diff
# - Issue label: bug

# Suggested: Fixes #123
```

### Feature Implementation Detection

```bash
# Issue: "Add dark mode support"
# Staged changes in: src/theme/dark-mode.ts, src/components/ThemeToggle.tsx

# Detection signals:
# - New files with relevant names
# - Issue label: enhancement
# - Keywords: "dark mode", "theme"

# Suggested: Closes #456
```

### Partial Work Detection

```bash
# Issue: "Refactor authentication system"
# Staged changes in: src/auth/oauth.ts (but more work needed)

# Detection signals:
# - File path matches scope
# - Issue is large (multiple sub-tasks in body)
# - Other files mentioned in issue not yet changed

# Suggested: Refs #789
```

## Integration Commands

### Quick Issue Scan Before Commit

```bash
# One-liner to show relevant issues for staged changes
gh issue list --state open --json number,title,labels --limit 20 | \
  jq -r '.[] | "#\(.number): \(.title)"'
```

### Detailed Issue Analysis

```bash
# Get full issue details for matching
gh issue view <number> --json title,body,labels,assignees

# Search issues by keyword
gh issue list --search "keyword in:title,body" --state open
```

### File-Based Issue Search

```bash
# Search for issues mentioning specific file
gh issue list --search "filename.ts in:body" --state open

# Search for issues mentioning directory
gh issue list --search "src/auth in:body" --state open
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick issue list | `gh issue list --state open --json number,title -L 20` |
| Bug issues only | `gh issue list --state open --label bug --json number,title` |
| Search by keyword | `gh issue list --search "keyword" --state open --json number,title` |
| Full issue detail | `gh issue view N --json title,body,labels` |

## Output Format for Agent

When reporting detected issues, use this format:

```
Detected potentially related issues:

HIGH CONFIDENCE:
- #123 "Login fails with invalid token" → Fixes #123
  Match: File path src/auth/token.ts, error message match

MEDIUM CONFIDENCE:
- #456 "Improve auth error handling" → Refs #456
  Match: Directory src/auth/, keyword "error"

Suggested commit message footer:
Fixes #123
Refs #456
```

## Best Practices

1. **Always check for related issues** before committing
2. **Prefer `Fixes` over `Closes`** for bug fixes (clearer intent)
3. **Use `Refs` for partial work** to maintain traceability without premature closure
4. **Include multiple references** when a commit addresses several issues
5. **Verify issue state** - don't reference already-closed issues unless reopening
6. **Cross-reference PRs** - issues may already have linked PRs in progress

## Edge Cases

### No Matching Issues Found

If no open issues match the staged changes:
- Consider if an issue should be created first (for traceability)
- For trivial fixes, commit without issue reference is acceptable
- For significant changes, create issue retroactively and link in PR

### Multiple Matching Issues

When several issues relate to the same changes:
```bash
# Close all that are fully resolved
Fixes #123, fixes #124, fixes #125

# Or mix closing and reference keywords
Fixes #123
Refs #124, #125
```

### Cross-Repository Issues

```bash
# Reference issue in another repository
Fixes owner/other-repo#42

# Common for monorepo or multi-repo projects
```
