---
created: 2026-01-21
modified: 2026-05-30
reviewed: 2026-04-29
name: git-pr
description: Create pull requests with descriptions, labels, and issue references. Use when user says "create PR", "open pull request", or "submit for review". Creates PRs from pushed branches — see git-commit for commits and git-push for pushing.
user-invocable: false
allowed-tools: Bash(git status *), Bash(git diff *), Bash(git log *), Bash(git branch *), Bash(git remote *), Bash(git push *), Bash(git fetch *), Bash(git rev-list *), Bash(gh pr *), Bash(gh issue *), Bash(gh repo *), Read, Grep, Glob, TodoWrite
---

# Git PR

Create pull requests with comprehensive descriptions and proper issue linkage.

## When to Use This Skill

| Use this skill when... | Use the alternative when... |
|---|---|
| Opening a PR from a pushed branch with description, labels, and issue refs | Use `github-pr-title` if you only need to author or fix the conventional title |
| Selecting a base branch, draft mode, or reviewers as part of PR creation | Use `git-push` first if the branch has not been pushed to remote yet |
| Going from a pushed branch to an open pull request | Use `git-commit` first if there are uncommitted changes locally |
| Inserting `Fixes #N` / `Closes #N` issue references into the PR body | Use `git-commit-push-pr` for the consolidated commit + push + PR macro |

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

> **Do NOT use markdown tables to track linked issues.** GitHub's auto-close
> machinery only fires on `Fixes #N` / `Closes #N` / `Resolves #N` keywords
> in the PR body or commits. A `| Issue | Status |` table is decorative —
> linked issues will not auto-close on merge, even if every row says "fixed".
> Always include the closing keyword as a bare line at the bottom of the
> body (or in a commit message).

## Workflow

> **Before creating the PR**, check whether any post-merge follow-up actions are needed (migrations, deployments, config changes, runbook updates). Create a GitHub issue for each and link them in the PR description. See [Post-Merge Follow-up Issues](#post-merge-follow-up-issues).

### 1. Assess PR Readiness

```bash
# Check current branch
git branch --show-current

# Fetch latest remote state for accurate comparison
git fetch origin main

# Check commits ahead of origin/main (always compare against remote)
ahead=$(git rev-list --count origin/main..HEAD 2>/dev/null || echo "0")
if [ "$ahead" = "0" ]; then
  echo "No commits ahead of origin/main - nothing to create PR for"
  exit 1
fi

# Check for existing PR
gh pr view --json number,state 2>/dev/null || echo "no existing PR"
```

### 2. Analyze Commits

**CRITICAL:** Always compare against `origin/main` (not local `main`) to avoid including commits that haven't been merged to the remote. Local `main` may be ahead of `origin/main` with unrelated commits.

```bash
# Fetch latest remote state
git fetch origin main

# Always use origin/main as base reference
base_ref="origin/main"

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

Write the PR body to a tempfile with the `Write` tool, then pass it via `--body-file`. This sidesteps shell quoting entirely — backticks, code fences, and shell metacharacters are preserved byte-for-byte. See the **Body content** rule in `github-issue-writing` for the canonical guidance and the threshold for when bare `--body "..."` is still acceptable.

```bash
# 1) Write tool → /tmp/pr-body.md (no shell escaping involved)
# 2) gh pr create --body-file
gh pr create \
  --title "feat(scope): add feature" \
  --body-file /tmp/pr-body.md
```

For a short body you can skip the tempfile and stream it over stdin with `--body-file -` and a **quoted** heredoc:

```bash
gh pr create --title "feat(scope): add feature" --body-file - <<'EOF'
## Summary
Use `code`, ${vars}, and $shell syntax freely — they render verbatim.
EOF
```

**Inside `<<'EOF'` (quoted delimiter), backticks, `$`, and `\` are already literal — never backslash-escape them.** A reflexive `\`` survives into the rendered PR description and needs a follow-up `gh pr edit --body-file` to clean up. (The `Write` tool → `--body-file` path above sidesteps the question entirely and stays the default for non-trivial bodies.)

Body content of `/tmp/pr-body.md`:

```markdown
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
```

### 5. Verify Closing Keywords

After the PR is created, fetch the body back and confirm every issue
referenced by number has a matching `Fixes` / `Closes` / `Resolves`
keyword. Issues mentioned only in a markdown table or prose will not
auto-close on merge.

```bash
PR_NUM=$(gh pr view --json number --jq .number)
pr_body=$(gh pr view "$PR_NUM" --json body --jq .body)
referenced=$(echo "$pr_body" | grep -oE '#[0-9]+' | sort -u)
closing=$(echo "$pr_body" | grep -oiE '(closes|fixes|resolves)[[:space:]]+#[0-9]+' | grep -oE '#[0-9]+' | sort -u)
missing=$(comm -23 <(echo "$referenced") <(echo "$closing"))
[ -n "$missing" ] && echo "WARN: referenced but not auto-closing: $missing"
```

If `missing` is non-empty, edit the PR body with `gh pr edit <num> --body-file ...`
to add `Fixes #N` / `Closes #N` lines for any issue this PR is meant to close.
`Related: #N` is correct for issues the PR references but does not close —
those should not appear in the warning if you re-run the check.

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
gh pr create --head feat/feature-name --base main --title "..." --body-file /tmp/pr-body.md
```

## Stacked PRs

When merging a PR whose head branch is the **base** of one or more open
downstream PRs, deleting the head branch on merge will close every dependent
PR. `gh pr merge --delete-branch` and the matching UI checkbox both delete
the head branch — safe for leaf PRs, destructive for stack parents.

### Pre-merge check

Before merging, query for any open PR that targets the current branch as
its base:

```bash
HEAD_BRANCH=$(gh pr view --json headRefName --jq .headRefName)
dependents=$(gh pr list --base "$HEAD_BRANCH" --state open --json number,title,headRefName)
echo "$dependents" | jq -e 'length > 0' >/dev/null && echo "WARN: $dependents"
```

If `dependents` is a non-empty array, this PR is the parent of a stack.

### Merge rules for stacked PRs

| Situation | Merge command |
|-----------|---------------|
| No dependents (leaf PR) | `gh pr merge --squash --delete-branch` (default) |
| Has dependents | `gh pr merge --squash` — **omit `--delete-branch`** |
| Has dependents, want to clean up | Re-target dependents first (see below), then merge with `--delete-branch` |

### Re-targeting dependents

Before merging the parent, point each dependent at the parent's base so
they don't auto-close when the parent's branch disappears:

```bash
# For each dependent PR returned above:
gh pr edit <dep-pr-num> --base "$(gh pr view --json baseRefName --jq .baseRefName)"
```

Once every dependent has been re-targeted (or you have explicitly chosen
not to), it is safe to merge the parent with `--delete-branch`.

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
| Create PR | `gh pr create --title "..." --body-file /tmp/pr-body.md` |
| Draft PR | `gh pr create --draft` |
| View PR | `gh pr view` |
| Edit PR | `gh pr edit --title "..." --body-file /tmp/pr-body.md` |
| List PRs | `gh pr list` |
| Check status | `gh pr checks` |
| Verify closing keywords | `gh pr view <num> --json body --jq .body \| grep -oiE '(closes\|fixes\|resolves)[[:space:]]+#[0-9]+'` |
| Check for stacked dependents | `gh pr list --base <head> --state open --json number,title` |
| Merge stacked parent | `gh pr merge --squash` (omit `--delete-branch`) |
| Create follow-up issue | `gh issue create --title "[Chore] ..." --body-file /tmp/issue-body.md` |

## Agentic Optimizations

| Context | Command |
|---------|---------|
| PR readiness | `gh pr view --json number,state 2>/dev/null` |
| Commits | `git log origin/main..HEAD --format='%s'` |
| Issue refs | `git log origin/main..HEAD --format='%B' \| grep -oE '#[0-9]+'` |
| Verify auto-close | `gh pr view <num> --json body --jq .body \| grep -oiE '(closes\|fixes\|resolves)[[:space:]]+#[0-9]+'` |
| Stacked-PR safety check | `gh pr list --base <head> --state open --json number,title,headRefName` |
| Create follow-up issue | `gh issue create --title "[Chore] ..." --body-file /tmp/follow-up.md` |
| Create PR | `gh pr create --title "..." --body-file /tmp/pr-body.md` |
