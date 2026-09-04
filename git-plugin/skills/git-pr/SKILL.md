---
created: 2026-01-21
modified: 2026-06-10
reviewed: 2026-06-10
name: git-pr
description: Create pull requests with descriptions, labels, and issue references. Use when user says "create PR", "open pull request", or "submit for review". From pushed branches.
user-invocable: false
allowed-tools: Bash(bash *), Bash(git status *), Bash(git diff *), Bash(git log *), Bash(git branch *), Bash(git remote *), Bash(git push *), Bash(git fetch *), Bash(git rev-list *), Bash(gh pr *), Bash(gh issue *), Bash(gh repo *), Read, Grep, Glob, TodoWrite
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

## Workflow

> **Before creating the PR**, check whether any post-merge follow-up actions are needed (migrations, deployments, config changes, runbook updates). Create a GitHub issue for each and link them in the PR description. See [REFERENCE.md](REFERENCE.md) § Post-Merge Follow-up Issues.

### 1. Assess PR Readiness

Run the data-gathering script. It fetches the base ref, computes the ahead-count
against `origin/main`, probes for an existing PR (via the `state` field — never
`merged`), scans for stacked dependents, and audits closing keywords:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/git-pr.sh" --home-dir "$HOME" --project-dir "$(pwd)" --base origin/main
```

Parse `STATUS=` and `ISSUES:` from the output. Read `PR_READY` (false when
`AHEAD_COUNT=0` — nothing to PR), `EXISTING_PR` (a number means `gh pr view` /
`gh pr edit` instead of creating), `CURRENT_BRANCH`, `STACK_PARENT` /
`DEPENDENT_PR=<n>` (see [REFERENCE.md](REFERENCE.md) § Stacked PRs), and `BODY_NOT_AUTOCLOSING` (see
Step 5). Authoring the PR body remains your job.

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

After the PR is created, audit the body: every issue referenced by number must
have a matching `Fixes` / `Closes` / `Resolves` keyword. Issues mentioned only
in a markdown table or prose will not auto-close on merge.

Re-run the data-gathering script against the just-created PR's body (write it to
a tempfile first, or pass the fetched body) — it emits `BODY_REFERENCED`,
`BODY_CLOSING`, and `BODY_NOT_AUTOCLOSING`:

```bash
gh pr view --json body --jq .body > /tmp/pr-body-check.md
bash "${CLAUDE_SKILL_DIR}/scripts/git-pr.sh" --home-dir "$HOME" --project-dir "$(pwd)" --body-file /tmp/pr-body-check.md
```

If `BODY_NOT_AUTOCLOSING` is non-empty, edit the PR body with `gh pr edit <num> --body-file ...`
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

## Pre-merge Checklist Guidelines

Include only actions **before** merging:
- [ ] Tests pass locally
- [ ] Code reviewed
- [ ] Documentation updated
- [ ] Breaking changes documented

**Do NOT include post-merge steps in the checklist.** PR descriptions are closed and buried after merge — checklists embedded there are easily missed. Post-merge actions must be tracked as GitHub issues.

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

For the full PR description template, main-branch push pattern, stacked-PR merge rules, and the post-merge follow-up issue workflow, see [REFERENCE.md](REFERENCE.md).
