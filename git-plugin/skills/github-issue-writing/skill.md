---
model: haiku
created: 2026-01-30
modified: 2026-01-30
reviewed: 2026-01-30
name: github-issue-writing
description: |
  Create well-structured GitHub issues with clear titles, descriptions, and
  acceptance criteria. Use when filing bugs, requesting features, or structuring
  issue content.
allowed-tools: Bash(gh issue *), Bash(gh label *), Bash(gh repo *), Read, Grep, Glob, TodoWrite
---

# GitHub Issue Writing

Create well-structured, actionable GitHub issues.

## When to Use

| Use this skill when... | Use X instead when... |
|------------------------|----------------------|
| Creating new issues | Processing existing issues (`git:issue`) |
| Writing bug reports | Auto-detecting issues (`github-issue-autodetect`) |
| Filing feature requests | Creating PRs (`git-pr`) |

## Issue Title Format

```
[Type] Component: Brief description
```

| Type | Example |
|------|---------|
| Bug | `[Bug] Auth: Login fails with valid credentials` |
| Feature | `[Feature] API: Add rate limiting support` |
| Docs | `[Docs] README: Add installation instructions` |
| Chore | `[Chore] CI: Update Node.js version` |

**Guidelines:**
- Be specific (not "Bug" but "Login fails with OAuth")
- Include component for triage
- Keep under 72 characters

## Bug Report Template

```markdown
## Summary
Brief description of the bug.

## Steps to Reproduce
1. Go to '...'
2. Click on '...'
3. See error

## Expected Behavior
What should happen.

## Actual Behavior
What actually happens.

## Environment
- OS: macOS 14.0
- Browser: Chrome 120
- Version: 2.1.0
```

## Feature Request Template

```markdown
## Summary
What this feature does.

## Motivation
Why this is needed. What problem does it solve?

## Proposed Solution
Description of desired behavior.

## Acceptance Criteria
- [ ] Criterion 1
- [ ] Criterion 2
- [ ] Criterion 3
```

## CLI Commands

```bash
# Create issue
gh issue create --title "[Bug] Auth: Login fails" --body "..."

# With labels
gh issue create --title "..." --body "..." --label "bug" --label "priority: high"

# With assignee
gh issue create --title "..." --body "..." --assignee "@me"

# Search before creating
gh issue list --search "login error" --state all
```

## Linking Issues

```markdown
## Related Issues
Blocks #123
Blocked by #456
Related to #789
```

## Quick Reference

| Action | Command |
|--------|---------|
| Create | `gh issue create --title "..." --body "..."` |
| Search | `gh issue list --search "keyword"` |
| View | `gh issue view N` |
| Edit | `gh issue edit N --title "..."` |
| Labels | `gh label list` |

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Create issue | `gh issue create --title "..." --body "..."` |
| List labels | `gh label list --json name` |
| Search issues | `gh issue list --search "keyword" --state all --json number,title` |
| View issue | `gh issue view N --json title,body,labels` |
