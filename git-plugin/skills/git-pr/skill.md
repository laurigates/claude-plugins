---
model: haiku
created: 2026-01-21
modified: 2026-01-23
reviewed: 2026-01-23
name: git-pr
description: |
  Create pull requests with proper descriptions, labels, and issue references. Handles
  draft mode, reviewers, and base branch selection. Use when user says "create PR",
  "open pull request", "submit for review", or similar. This skill creates PRs from
  pushed branches - see git-commit for commits and git-push for pushing.
allowed-tools: Bash(git status *), Bash(git diff *), Bash(git log *), Bash(git branch *), Bash(git remote *), Bash(git push *), Bash(git fetch *), Bash(git rev-list *), Bash(gh pr *), Bash(gh issue *), Bash(gh repo *), Read, Grep, Glob, TodoWrite
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

# Check if on main/master (main-branch development pattern)
branch=$(git branch --show-current)
if [ "$branch" = "main" ] || [ "$branch" = "master" ]; then
  # Check for commits ahead of remote
  git fetch origin
  ahead=$(git rev-list --count origin/$branch..HEAD 2>/dev/null || echo "0")
  if [ "$ahead" = "0" ]; then
    echo "ERROR: No commits ahead of origin/$branch - nothing to create PR for"
    exit 1
  fi
  # Proceed with main-branch development pattern (Step 1b)
fi

# For feature branches: check if pushed to remote
git rev-list --count origin/$branch..HEAD 2>/dev/null || echo "not pushed"

# Check for existing PR
gh pr view --json number,state 2>/dev/null || echo "no existing PR"
```

### 1b. Handle Commits on Main (Main-Branch Development Pattern)

When commits are on `main`, automatically push them to a remote feature branch:

1. **Determine branch name** from the first/primary commit message:
   - Extract the conventional commit type and scope: `feat(auth): add OAuth` → `feat/auth-add-oauth`
   - If no scope: `fix: handle timeout` → `fix/handle-timeout`
   - Kebab-case, max ~50 chars

2. **Push to remote feature branch** (no local branch checkout):
   ```bash
   # Push main commits to a new remote branch
   git push origin main:<generated-branch-name>
   ```

3. **Create PR** targeting `main` with `--head <generated-branch-name>`

4. **Do NOT reset local main** - when the PR is merged and you pull main, it resolves cleanly via fast-forward

**Why this works:**
- Commits exist on both local main and the remote feature branch
- When the PR merges to remote main, local main just needs a `git pull` to sync
- No history rewriting, no branch juggling, clean workflow

### 2. Analyze Commits for PR

```bash
# Get all commits in this branch vs base
# If on main: compare against origin/main (commits not yet on remote)
# If on feature branch: compare against main
base_ref="main"
if [ "$(git branch --show-current)" = "main" ]; then
  base_ref="origin/main"
fi

git log $base_ref..HEAD --format='%H %s'

# Extract issue references from commit messages
git log $base_ref..HEAD --format='%B' | grep -oE '#[0-9]+' | sort -u

# Get diff stats for summary
git diff $base_ref...HEAD --stat
```

### 3. Create PR

```bash
# If on main: use --head to specify the remote feature branch
# If on feature branch: gh pr create uses current branch automatically
gh pr create \
  --head "<remote-branch-name>" \
  --base main \
  --title "the pr title" \
  --body "$(cat <<'EOF'
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

This skill creates PRs. When on main, it also handles pushing to a remote feature branch automatically.

| User Intent | On Feature Branch | On Main |
|-------------|-------------------|---------|
| "create PR" | Assumes already pushed | Auto-pushes to remote feature branch, then creates PR |
| "push and create PR" | git-push → git-pr | git-pr handles both (push + PR) |
| "commit and create PR" | git-commit → git-push → git-pr | git-commit → git-pr (auto-push) |

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

**Feature branch not pushed:**
```
Branch not pushed to remote. Push first with:
  git push -u origin $(git branch --show-current)
```
Note: This only applies to feature branches. On main, commits are automatically pushed to a remote feature branch.

**PR already exists:**
```
PR #42 already exists for this branch.
View: gh pr view 42
Edit: gh pr edit 42
```

**On main with no commits ahead:**
```
No commits ahead of origin/main - nothing to create PR for.
Commit your changes first, then create the PR.
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
