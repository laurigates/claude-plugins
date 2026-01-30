---
model: haiku
created: 2026-01-30
modified: 2026-01-30
reviewed: 2026-01-30
name: github-issue-writing
description: |
  Create well-structured GitHub issues with clear titles, descriptions, acceptance
  criteria, and proper labeling. Use when user says "create issue", "write issue",
  "file a bug", "request a feature", or needs help structuring issue content.
allowed-tools: Bash(gh issue:*), Bash(gh label:*), Bash(gh repo:*), Bash(git status:*), Read, Grep, Glob, TodoWrite
---

# GitHub Issue Writing

Expert guidance for creating well-structured, actionable GitHub issues that are easy to understand and implement.

## When to Use This Skill

| Use this skill when... | Use X instead when... |
|------------------------|----------------------|
| Creating a new issue | Processing existing issues (`git:issue` command) |
| Writing bug reports | Auto-detecting issues for commits (`github-issue-autodetect`) |
| Filing feature requests | Reviewing PR content (`git-pr`) |
| Structuring issue content | Managing issue labels only (`github-labels`) |

## Core Expertise

- **Issue Structuring**: Clear titles, descriptions, and acceptance criteria
- **Bug Reports**: Reproducible steps, expected vs actual behavior
- **Feature Requests**: User stories, use cases, acceptance criteria
- **Label Selection**: Appropriate categorization for triage
- **Template Adherence**: Follow repository issue templates when available

## Issue Title Best Practices

### Title Format

| Type | Format | Example |
|------|--------|---------|
| Bug | `[Bug] <component>: <symptom>` | `[Bug] Auth: Login fails with valid credentials` |
| Feature | `[Feature] <component>: <capability>` | `[Feature] API: Add rate limiting support` |
| Docs | `[Docs] <area>: <what needs updating>` | `[Docs] README: Add installation instructions` |
| Chore | `[Chore] <area>: <task>` | `[Chore] CI: Update Node.js version` |

### Title Guidelines

- **Be specific**: "Login fails" vs "Login fails with OAuth when session expires"
- **Include component**: Helps with triage and assignment
- **Use imperative mood for features**: "Add X" not "Adding X"
- **State the problem for bugs**: Describe the symptom, not the cause
- **Keep under 72 characters**: Readable in lists and notifications

### Good vs Bad Titles

| Bad | Good | Why |
|-----|------|-----|
| "Bug" | "[Bug] Auth: 500 error on password reset" | Specific, includes component |
| "New feature idea" | "[Feature] Dashboard: Add export to CSV" | Actionable, scoped |
| "Doesn't work" | "[Bug] API: GET /users returns 404 for valid IDs" | Reproducible context |
| "Please add dark mode" | "[Feature] UI: Add dark mode theme toggle" | Clear scope |

## Bug Report Structure

```markdown
## Description
Brief summary of the bug.

## Steps to Reproduce
1. Go to '...'
2. Click on '...'
3. Scroll down to '...'
4. See error

## Expected Behavior
What you expected to happen.

## Actual Behavior
What actually happened.

## Environment
- OS: [e.g., macOS 14.0]
- Browser: [e.g., Chrome 120]
- Version: [e.g., 2.1.0]

## Screenshots/Logs
If applicable, add screenshots or error logs.

## Additional Context
Any other context about the problem.
```

### Bug Report Checklist

- [ ] Title clearly states the symptom
- [ ] Steps to reproduce are numbered and specific
- [ ] Expected vs actual behavior is clear
- [ ] Environment details are included
- [ ] Error messages/logs are provided if available
- [ ] Screenshots attached for UI issues

## Feature Request Structure

```markdown
## Problem Statement
What problem does this solve? Why is it needed?

## Proposed Solution
Clear description of the desired feature.

## User Story
As a [type of user], I want [goal] so that [benefit].

## Acceptance Criteria
- [ ] Criterion 1
- [ ] Criterion 2
- [ ] Criterion 3

## Alternatives Considered
Other solutions you've considered and why this is preferred.

## Additional Context
Mockups, examples from other tools, or related issues.
```

### Feature Request Checklist

- [ ] Problem statement explains the "why"
- [ ] Solution is specific and actionable
- [ ] User story identifies who benefits
- [ ] Acceptance criteria are measurable
- [ ] Scope is reasonable for a single issue

## Creating Issues via CLI

### Basic Issue Creation

```bash
# Create issue interactively
gh issue create

# Create with title and body
gh issue create --title "[Bug] Auth: Login fails" --body "$(cat <<'EOF'
## Description
Login fails with valid credentials after session timeout.

## Steps to Reproduce
1. Log in successfully
2. Wait for session to expire (30 min)
3. Attempt any action
4. Redirected to login, but login fails

## Expected Behavior
Should be able to log in again normally.

## Actual Behavior
Receives "Invalid credentials" error despite correct password.
EOF
)"

# Create with labels
gh issue create --title "[Feature] Add dark mode" --body "..." --label "enhancement" --label "ui"

# Create with assignee
gh issue create --title "[Bug] Fix memory leak" --body "..." --assignee "@me"

# Create with milestone
gh issue create --title "[Feature] OAuth support" --body "..." --milestone "v2.0"
```

### Using Issue Templates

```bash
# List available templates
gh issue create --web  # Opens browser with template selection

# Check for templates in repo
ls .github/ISSUE_TEMPLATE/ 2>/dev/null || echo "No templates found"
```

### Linking Related Issues

```markdown
## Related Issues
- Blocks #123
- Blocked by #456
- Related to #789
- Duplicate of #012
```

## Label Selection

### Common Label Categories

| Category | Labels | Use For |
|----------|--------|---------|
| Type | `bug`, `enhancement`, `documentation` | Issue classification |
| Priority | `priority: critical`, `priority: high`, `priority: low` | Urgency |
| Status | `needs-triage`, `confirmed`, `wontfix` | Workflow state |
| Area | `area: auth`, `area: api`, `area: ui` | Component |
| Effort | `good-first-issue`, `help-wanted` | Contributor guidance |

### Applying Labels

```bash
# List available labels
gh label list

# Create issue with labels
gh issue create --label "bug" --label "priority: high" --title "..."

# Add labels to existing issue
gh issue edit 123 --add-label "confirmed"
```

## Issue Quality Checklist

Before creating an issue, verify:

### For All Issues

- [ ] Title is specific and under 72 characters
- [ ] Description provides sufficient context
- [ ] Appropriate labels are selected
- [ ] Not a duplicate (search existing issues first)

### For Bug Reports

- [ ] Steps to reproduce are clear
- [ ] Environment details included
- [ ] Error messages/logs attached
- [ ] Expected vs actual behavior stated

### For Feature Requests

- [ ] Problem statement explains the need
- [ ] Solution is actionable
- [ ] Acceptance criteria defined
- [ ] Scope is appropriate

## Searching Before Creating

Always check for existing issues:

```bash
# Search by keyword
gh issue list --search "login error" --state all

# Search in title only
gh issue list --search "in:title login" --state all

# Search by label
gh issue list --label "bug" --state open

# View issue details
gh issue view 123
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Create issue | `gh issue create --title "..." --body "..." --label "..."` |
| List labels | `gh label list --json name,description` |
| Search issues | `gh issue list --search "keyword" --state all --json number,title` |
| Check templates | `ls .github/ISSUE_TEMPLATE/ 2>/dev/null` |
| View issue | `gh issue view N --json title,body,labels,state` |

## Common Patterns

### Bug from Error Log

When reporting a bug from an error:

```bash
# Capture error context
gh issue create --title "[Bug] API: $(head -1 error.log)" --body "$(cat <<EOF
## Description
Encountered error during API request.

## Error Log
\`\`\`
$(cat error.log)
\`\`\`

## Context
- Endpoint: /api/users
- Method: POST
- Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
)"
```

### Feature from User Feedback

```bash
gh issue create --title "[Feature] Dashboard: Export functionality" --body "$(cat <<'EOF'
## Problem Statement
Users frequently request the ability to export dashboard data for reporting.

## User Story
As a dashboard user, I want to export my data to CSV so that I can create custom reports.

## Acceptance Criteria
- [ ] Export button visible on dashboard
- [ ] Supports CSV format
- [ ] Includes all visible columns
- [ ] Downloads immediately (no email)

## Additional Context
Similar to export in Competitor X.
EOF
)" --label "enhancement" --label "user-feedback"
```

## Quick Reference

| Action | Command |
|--------|---------|
| Create issue | `gh issue create --title "..." --body "..."` |
| With labels | `gh issue create --label "bug" --label "high"` |
| With assignee | `gh issue create --assignee "@me"` |
| Search issues | `gh issue list --search "keyword"` |
| View issue | `gh issue view N` |
| Edit issue | `gh issue edit N --title "..." --body "..."` |
| Close issue | `gh issue close N` |
| Reopen issue | `gh issue reopen N` |
| Add label | `gh issue edit N --add-label "label"` |
| Remove label | `gh issue edit N --remove-label "label"` |
