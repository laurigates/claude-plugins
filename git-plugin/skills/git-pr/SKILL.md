---
created: 2026-01-21
modified: 2026-10-26
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

Body content of `/tmp/pr-body.md` — the squash body follows the repo's
`squash_merge_commit_message`: `COMMIT_MESSAGES` on release-please repos such as claude-plugins, `PR_BODY` elsewhere (OpenTofu-managed in laurigates/gitops `main.tf`; laurigates/gitops#318 moves release-please repos to `PR_BODY`). On a `PR_BODY` repo a
squash-merged PR's body **is the commit body on `main`** and release-please
parses it. Rebase is the default merge method, but
single-commit and fixup-carrying PRs squash, so write every body as a commit
message: prose first, footers last, no checklists, headings or reviewer-only
notes. Method rule and body lint: `github-pr-title` →
[merge-strategies.md](../github-pr-title/merge-strategies.md).

```markdown
Add retry with backoff to the webhook dispatcher so transient 5xx
responses from receivers no longer drop events.

- Retry up to 5 times with jittered exponential backoff
- Record final failures in the dead-letter table

Follow-up: #456 (run migration after deploy), #457 (prod config)

Fixes #123
Refs #456
```

Rules for the footer paragraph (last block, one per line, no blank lines):

| Line | Effect under squash |
|------|---------------------|
| `Fixes #N` / `Closes #N` | Closes issue on merge |
| `Refs #N` | Link only |
| `BREAKING CHANGE: <what breaks>` | **Major** bump — only when intended |
| `Release-As: X.Y.Z` | Forces version |

Never start a line with `feat(…):` / `fix(…):` in the footer block unless you
mean an additional changelog entry. Reviewer instructions (test steps,
screenshots) go in a PR comment, not the body.

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

Use conventional commit format (`github-pr-title`):

```
<type>(<scope>): <subject>
```

**The scope is required.** Write `type(scope): …` — `docs(readme): update install steps`, never a bare `docs: update install steps`. The Conventional Commits spec lets you omit the scope; this house convention does not (`.claude/rules/conventional-commits.md`). Take it from the component or plugin the change touches.

Examples:
- `feat(auth): add OAuth2 support`
- `fix(api): handle null response`

## PR Options

| Option | Command |
|--------|---------|
| Draft | `gh pr create --draft` — requires a [`## Draft status`](#draft-status) section |
| Labels | `gh pr create --label "enhancement"` |
| Reviewers | `gh pr create --reviewer user1,user2` |
| Base branch | `gh pr create --base develop` |
| Assignee | `gh pr create --assignee @me` |

## Draft status

A PR opened with `--draft` ends its body with a `## Draft status` section: what
is incomplete, and the exact condition for `gh pr ready`. A draft without one
gives nobody a reason to mark it ready, and an automated PR sweep surfaces it
instead of readying it. Run `gh pr ready` yourself once the work is complete.

| Dependency | How to record it |
|------------|------------------|
| PR in the same repo | Stack it: `--base <parent-branch>`; see `git-plugin:git-stacked-prs`. Name the parent in the section as a full URL |
| PR in another repo | Full URL in the section: `Blocked by https://github.com/<owner>/<repo>/pull/<n>` |

Write every blocking PR as a full URL; the sweep marks the draft ready only when
all of them have merged. GitHub's `blocked_by` issue dependencies link issues
only (`gh pr` has no `--blocked-by` flag), so the body is the record.

## Pre-merge Verification

Keep pre-merge checks (tests pass, docs updated, breaking changes documented)
out of the body: a squash merge on a `PR_BODY` repo copies the body into `git log`, where a
`- [ ]` checklist is noise. Verify them through CI or say so in a PR comment.

Post-merge steps never go in the body either. PR descriptions are closed and
buried after merge, so post-merge actions are tracked as GitHub issues and
linked with `Refs #N` (see [REFERENCE.md](REFERENCE.md) § Post-Merge Follow-up Issues).

## Output

On success, report:
```
Created PR #42: feat(auth): add OAuth2 support
URL: https://github.com/org/repo/pull/42

Related Issues:
  Fixes #123
  Refs #456

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
| Merge stacked parent | `gh pr merge --<method>` (omit `--delete-branch`; method from [merge-strategies.md](../github-pr-title/merge-strategies.md)) |
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
