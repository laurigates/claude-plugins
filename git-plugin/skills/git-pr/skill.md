---
model: haiku
created: 2026-01-21
modified: 2026-01-21
reviewed: 2026-01-21
name: git-pr
description: |
  Create pull requests with proper descriptions, labels, and issue references. Handles
  draft mode, reviewers, and base branch selection. Use when user says "create PR",
  "open pull request", "submit for review", or similar. This skill creates PRs from
  pushed branches - see git-commit for commits and git-push for pushing.
allowed-tools: Bash(git status:*), Bash(git diff:*), Bash(git log:*), Bash(git branch:*), Bash(git remote:*), Bash(gh pr:*), Bash(gh issue:*), Bash(gh repo:*), Read, Grep, Glob, TodoWrite
---

# Git PR

Create pull requests with comprehensive descriptions and proper issue linkage.

## When to Use

**Trigger phrases:**
- "create PR" / "open PR" / "make PR"
- "open pull request" / "create pull request"
- "submit for review"
- "ready for review"

**Context signals:**
- Branch has commits not in base branch
- User finished a feature or fix
- Commits reference issues that should be closed
- No existing PR for the current branch

## Workflow

### 1. Assess PR Readiness

```bash
# Check current branch
git branch --show-current

# Verify not on main/master
branch=$(git branch --show-current)
if [ "$branch" = "main" ] || [ "$branch" = "master" ]; then
  echo "ERROR: Cannot create PR from $branch"
  exit 1
fi

# Check if pushed to remote
git fetch origin
git rev-list --count origin/$branch..HEAD 2>/dev/null || echo "not pushed"

# Check for existing PR
gh pr view --json number,state 2>/dev/null || echo "no existing PR"
```

### 2. Analyze Commits for PR

```bash
# Get all commits in this branch vs base
git log main..HEAD --format='%H %s'

# Extract issue references from commit messages
git log main..HEAD --format='%B' | grep -oE '#[0-9]+' | sort -u

# Get diff stats for summary
git diff main...HEAD --stat
```

### 3. Create PR

```bash
gh pr create --title "the pr title" --body "$(cat <<'EOF'
## Summary
<1-3 bullet points summarizing changes>

## Changes
<Brief description of what changed and why>

## Test plan
- [ ] Unit tests pass
- [ ] Manual testing completed
- [ ] Edge cases considered

Fixes #123
Refs #456

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

### PR Description Format

```markdown
## Summary
<1-3 bullet points>

## Changes
<What changed and why>

## Test plan
- [ ] Checklist of testing steps

Fixes #N    <!-- Closes issue on merge -->
Refs #M     <!-- Links without closing -->

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
```

## PR Options

### Draft PR

For work-in-progress or early feedback:
```bash
gh pr create --draft --title "WIP: feature name" --body "..."
```

### With Labels

Add labels during creation:
```bash
gh pr create --label "enhancement" --label "needs-review" ...
```

### With Reviewers

Request specific reviewers:
```bash
gh pr create --reviewer username1,username2 ...
```

### Against Non-Default Base

Target a specific branch:
```bash
gh pr create --base develop ...
```

### With Assignees

Assign the PR:
```bash
gh pr create --assignee @me ...
```

## Issue Linking

### Closing Keywords

Use in PR body to auto-close issues on merge:

| Keyword | Example |
|---------|---------|
| `Fixes` | `Fixes #123` |
| `Closes` | `Closes #456` |
| `Resolves` | `Resolves #789` |

### Reference Keywords

Link without closing:

| Keyword | Example |
|---------|---------|
| `Refs` | `Refs #123` |
| `Related to` | `Related to #456` |
| `Part of` | `Part of #789` |

## Composability

This skill **creates PRs only**. For full workflows:

| User Intent | Skills Invoked |
|-------------|----------------|
| "create PR" | git-pr only (assumes pushed) |
| "push and create PR" | git-push → git-pr |
| "commit and create PR" | git-commit → git-push → git-pr |

## Output

On success, report:
```
Created PR #42: feat(auth): add OAuth2 support
URL: https://github.com/org/repo/pull/42

Linked issues:
  Fixes #123
  Refs #456

Status: Open (or Draft)
Ready for: review, CI checks, or continue working
```

## Error Handling

**Branch not pushed:**
```
Branch not pushed to remote. Push first with:
  git push -u origin $(git branch --show-current)
```

**PR already exists:**
```
PR #42 already exists for this branch.
View: gh pr view 42
Edit: gh pr edit 42
```

**On protected branch:**
```
Cannot create PR from main/master.
Create a feature branch first.
```

**No commits to merge:**
```
No commits between main and current branch.
Nothing to create a PR for.
```

## Quick Reference

| Action | Command |
|--------|---------|
| Create PR | `gh pr create --title "..." --body "..."` |
| Draft PR | `gh pr create --draft ...` |
| With labels | `gh pr create --label "bug" ...` |
| With reviewers | `gh pr create --reviewer user1 ...` |
| Against branch | `gh pr create --base develop ...` |
| View existing | `gh pr view` |
| List PRs | `gh pr list` |
| Check PR status | `gh pr checks` |

## Best Practices

1. **Descriptive titles** - Use conventional commit format: `type(scope): description`
2. **Link all issues** - Every PR should reference related issues
3. **Use draft for WIP** - Mark incomplete work as draft
4. **Request reviews** - Tag appropriate reviewers
5. **Keep PRs focused** - One logical change per PR
6. **Include test plan** - Help reviewers understand how to verify
