---
model: haiku
created: 2026-01-21
modified: 2026-02-20
reviewed: 2026-02-20
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

| Use this skill when... | Use X instead when... |
|------------------------|----------------------|
| Creating a new PR | Just crafting a title (`github-pr-title`) |
| Full PR workflow | Just pushing (`git-push`) |
| Submit for review | Just committing (`git-commit`) |

## PR Description Format

### Standard Template

```markdown
## Summary
Brief description of what this PR does.

## Motivation
Why this change is needed. Link to issue if applicable.

## Changes
- Key change 1
- Key change 2
- Key change 3

## Pre-merge Checklist
- [ ] Tests pass locally
- [ ] Code reviewed
- [ ] Documentation updated (if needed)

## Follow-up Issues
<!-- Post-merge actions tracked as separate issues so they survive PR closure -->
- Closes #456 after merge: database migration for new schema
- Refs #457: update deployment runbook

## Related Issues
Fixes #123
Related: #124, #125
```

### Section Guidelines

| Section | Purpose | Required |
|---------|---------|----------|
| Summary | What the PR does (1-2 sentences) | Yes |
| Motivation | Why this change is needed | Yes |
| Changes | Key changes as bullet points | Yes |
| Pre-merge Checklist | Actions before merge only — never post-merge steps | If applicable |
| Follow-up Issues | Links to issues tracking post-merge actions | If post-merge work exists |
| Related Issues | Issue links at bottom | Yes |

### Issue Linking Syntax

Place at the **bottom** of the PR description:

```markdown
## Related Issues
Fixes #123              <!-- Auto-closes on merge -->
Closes #456             <!-- Auto-closes on merge -->
Resolves #789           <!-- Auto-closes on merge -->
Related: #124, #125     <!-- Links without closing -->
```

**Rules:**
- Use `Fixes`, `Closes`, or `Resolves` for issues this PR solves
- Use `Related:` for issues that are related but not solved
- Follow-up work should be created as new issues, not left in checklist

## Workflow

> **Before creating the PR**, check whether any post-merge follow-up actions are needed (migrations, deployments, config changes, runbook updates). Create a GitHub issue for each and link them in the PR description. See [Post-Merge Follow-up Issues](#post-merge-follow-up-issues).

### 1. Assess PR Readiness

```bash
# Check current branch
git branch --show-current

# Check if on main (main-branch development pattern)
branch=$(git branch --show-current)
if [ "$branch" = "main" ] || [ "$branch" = "master" ]; then
  git fetch origin
  ahead=$(git rev-list --count origin/$branch..HEAD 2>/dev/null || echo "0")
  if [ "$ahead" = "0" ]; then
    echo "No commits ahead - nothing to create PR for"
    exit 1
  fi
fi

# Check for existing PR
gh pr view --json number,state 2>/dev/null || echo "no existing PR"
```

### 2. Analyze Commits

```bash
# Get commits for PR
base_ref="main"
if [ "$(git branch --show-current)" = "main" ]; then
  base_ref="origin/main"
fi

git log $base_ref..HEAD --format='%H %s'

# Extract issue references
git log $base_ref..HEAD --format='%B' | grep -oE '#[0-9]+' | sort -u

# Get diff stats
git diff $base_ref...HEAD --stat
```

### 3. Identify Post-Merge Follow-ups and Create Issues

Before creating the PR, scan for any actions required **after** the PR is merged (deployments, migrations, config changes, external docs). For each:

```bash
# Create a follow-up issue
gh issue create \
  --title "[Chore] DB: Run migration for new schema" \
  --body "Follow-up to PR that adds user_preferences.\n\nRun: rake db:migrate in production after deploy."
# Returns: https://github.com/org/repo/issues/456
```

Keep a list of created issue numbers to link in the PR body.

### 4. Create PR

```bash
gh pr create \
  --title "feat(scope): add feature" \
  --body "$(cat <<'EOF'
## Summary
Brief description of what this PR does.

## Motivation
Why this change is needed.

## Changes
- Change 1
- Change 2

## Pre-merge Checklist
- [ ] Tests pass locally
- [ ] Code reviewed

## Follow-up Issues
- #456: run database migration after deploy
- #457: update production config

## Related Issues
Fixes #123
Related: #456
EOF
)"
```

## PR Title Format

Use conventional commits format (see `github-pr-title` skill):

```
<type>(<scope>): <subject>
```

Examples:
- `feat(auth): add OAuth2 support`
- `fix(api): handle null response`
- `docs(readme): update installation`

## PR Options

| Option | Command |
|--------|---------|
| Draft | `gh pr create --draft` |
| Labels | `gh pr create --label "enhancement"` |
| Reviewers | `gh pr create --reviewer user1,user2` |
| Base branch | `gh pr create --base develop` |
| Assignee | `gh pr create --assignee @me` |

## Main-Branch Development

When on main, push to remote feature branch:

```bash
# Push main to remote feature branch
git push origin main:feat/feature-name

# Create PR with --head
gh pr create --head feat/feature-name --base main --title "..." --body "..."
```

## Pre-merge Checklist Guidelines

Include only actions **before** merging:
- [ ] Tests pass locally
- [ ] Code reviewed
- [ ] Documentation updated
- [ ] Breaking changes documented

**Do NOT include post-merge steps in the checklist.** PR descriptions are closed and buried after merge — checklists embedded there are easily missed. Post-merge actions must be tracked as GitHub issues.

## Post-Merge Follow-up Issues

When a PR requires actions **after** it is merged, create a separate GitHub issue for each follow-up. Link all follow-up issues in the PR description under a **Follow-up Issues** section.

**Why issues, not PR checklists:** Once a PR is merged and closed, its description is rarely revisited. A GitHub issue stays open and assignable until explicitly closed, ensuring the follow-up is not lost.

### Common post-merge follow-up types

| Type | Example follow-up issue title |
|------|-------------------------------|
| Database migration | `[Chore] DB: Run schema migration for user_preferences table` |
| Deployment | `[Chore] Ops: Deploy feature-flag config to production` |
| Manual configuration | `[Chore] Config: Enable new OAuth provider in admin panel` |
| External documentation | `[Docs] Wiki: Update runbook for new deploy process` |
| Communication | `[Chore] Comms: Announce deprecation of /v1 API to customers` |
| Dependent PR | `[Feature] Next: Implement follow-on X after Y lands` |

### Workflow

1. **Identify** post-merge actions from commit messages, PR body, or conversation context.
2. **Create an issue** for each follow-up:
   ```bash
   gh issue create \
     --title "[Chore] DB: Run migration for new schema" \
     --body "After #42 merges, run: \`rake db:migrate\` in production.\n\nSee PR #42 for context." \
     --label "chore"
   ```
3. **Link** the newly created issues in the PR description:
   ```bash
   gh pr edit <pr-number> --body "$(gh pr view <pr-number> --json body -q '.body')

   ## Follow-up Issues
   - #<issue-num>: run database migration
   - #<issue-num>: update deployment runbook"
   ```
4. **Do NOT** add post-merge steps to the Pre-merge Checklist.

### Example: PR description with follow-up issues

```markdown
## Follow-up Issues
<!-- These issues track post-merge work and will stay open until completed -->
- #456: run database migration for user_preferences table
- #457: update production feature-flag config
```

## Output

On success, report:
```
Created PR #42: feat(auth): add OAuth2 support
URL: https://github.com/org/repo/pull/42

Related Issues:
  Fixes #123
  Related: #456

Status: Open
```

## Error Handling

| Error | Solution |
|-------|----------|
| Branch not pushed | Push first or use main-branch pattern |
| PR exists | `gh pr view` or `gh pr edit` |
| No commits | Commit changes first |

## Quick Reference

| Action | Command |
|--------|---------|
| Create PR | `gh pr create --title "..." --body "..."` |
| Draft PR | `gh pr create --draft` |
| View PR | `gh pr view` |
| Edit PR | `gh pr edit --title "..." --body "..."` |
| List PRs | `gh pr list` |
| Check status | `gh pr checks` |
| Create follow-up issue | `gh issue create --title "[Chore] ..." --body "..."` |

## Agentic Optimizations

| Context | Command |
|---------|---------|
| PR readiness | `gh pr view --json number,state 2>/dev/null` |
| Commits | `git log main..HEAD --format='%s'` |
| Issue refs | `git log main..HEAD --format='%B' \| grep -oE '#[0-9]+'` |
| Create follow-up issue | `gh issue create --title "[Chore] ..." --body "Follow-up to PR #N..."` |
| Create PR | `gh pr create --title "..." --body "..."` |
