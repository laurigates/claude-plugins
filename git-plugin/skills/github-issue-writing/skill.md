---
created: 2026-01-30
modified: 2026-04-25
reviewed: 2026-04-25
name: github-issue-writing
description: |
  Create well-structured GitHub issues with clear titles, descriptions, and
  acceptance criteria. Use when filing bugs, requesting features, or structuring
  issue content.
user-invocable: false
allowed-tools: Bash(gh issue *), Bash(gh label *), Bash(gh repo *), Read, Grep, Glob, TodoWrite
---

# GitHub Issue Writing

Create well-structured, actionable GitHub issues.

## When to Use This Skill

| Use this skill when... | Use the alternative when... |
|---|---|
| Filing a new bug, feature, or chore issue with clear title and acceptance criteria | Use `git-issue` to start working on existing issues end-to-end |
| Structuring an issue body with reproduction steps, scope, and definition of done | Use `github-issue-autodetect` to link existing issues from staged diffs |
| Choosing the `[Type] Component: Description` title format | Use `github-pr-title` to author the conventional title for the PR that fixes it |
| Designing a feature-request issue before implementation begins | Use `git-issue-manage` for transfer/pin/lock/develop-branch admin operations |

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

## Issue Types

GitHub supports first-class issue types. Use `--type` when creating issues:

| Type | Use For |
|------|---------|
| Bug | Something broken that needs fixing |
| Feature | New functionality request |
| Task | General work item |

Note: Available types depend on repository/org configuration. Use `gh issue create --type "Bug"` to leverage them.

## CLI Commands

```bash
# Create issue
gh issue create --title "[Bug] Auth: Login fails" --body "..."

# With labels
gh issue create --title "..." --body "..." --label "bug" --label "priority: high"

# With assignee
gh issue create --title "..." --body "..." --assignee "@me"

# With issue type
gh issue create --title "..." --body "..." --type "Bug"

# As sub-issue of a parent
gh issue create --title "..." --body "..." && \
  gh api repos/{owner}/{repo}/issues/{parent}/sub_issues -f sub_issue_id={new_id}

# Search before creating
gh issue list --search "login error" --state all
```

## Linking Issues

Pick the mechanism that matches the relationship — GitHub surfaces each one
differently and only the native APIs trigger "Blocked" badges on project boards.

| Relationship | How to record | Why |
|--------------|---------------|-----|
| Hard dependency (must happen before) | Native `dependencies/blocked_by` API — see `/git:issue-hierarchy --blocked-by N` | Sidebar "Relationships" entry + Blocked badge on boards |
| Composition (part-of scope) | Sub-issue API — see `/git:issue-hierarchy --add N` | Progress bar on parent, tracked separately from dependencies |
| Soft reference ("related to") | Plain markdown `Related to #789` in the body | Cross-link only; no lifecycle coupling |
| Auto-close on merge | `Fixes #N` / `Closes #N` footer in commit or PR body | Closes issue when the PR merges |

Do **not** write `Blocks #123` or `Blocked by #456` in issue bodies any more —
those strings used to be GitHub's workaround for missing dependency APIs, but
they are no longer parsed. Call `/git:issue-hierarchy` (or the REST endpoints
at `issues/{N}/dependencies/blocked_by`) so the relationship shows up in the
sidebar and on project boards.

## Quick Reference

| Action | Command |
|--------|---------|
| Create | `gh issue create --title "..." --body "..."` |
| Create with type | `gh issue create --title "..." --body "..." --type "Bug"` |
| Search | `gh issue list --search "keyword"` |
| View | `gh issue view N` |
| Edit | `gh issue edit N --title "..."` |
| Labels | `gh label list` |

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Create issue | `gh issue create --title "..." --body "..."` |
| Create with type | `gh issue create --title "..." --type "Bug" --body "..."` |
| List labels | `gh label list --json name` |
| Search issues | `gh issue list --search "keyword" --state all --json number,title` |
| View issue | `gh issue view N --json title,body,labels` |
