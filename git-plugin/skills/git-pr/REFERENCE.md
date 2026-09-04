# Git PR - Reference

Full PR description templates, main-branch push patterns, stacked-PR merge rules, and post-merge follow-up issue workflow.

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

## Main-Branch Development

When on main, push to remote feature branch:

```bash
# Push main to remote feature branch
git push origin main:feat/feature-name

# Create PR with --head
gh pr create --head feat/feature-name --base main --title "..." --body-file /tmp/pr-body.md
```

## Stacked PRs

> This section covers **ad-hoc** chains — a PR opened with `--base` pointing at
> another PR's branch. A stack **registered with GitHub** (`gh stack`, public
> preview) auto-retargets its upper PRs on merge and runs CI on all of them, so
> none of the manual work below applies to it — see
> `git-plugin:git-stacked-prs`.

When merging a PR whose head branch is the **base** of one or more open
downstream PRs, deleting the head branch on merge will close every dependent
PR. `gh pr merge --delete-branch` and the matching UI checkbox both delete
the head branch — safe for leaf PRs, destructive for stack parents.

### Pre-merge check

The data-gathering script (Step 1) already scanned for open PRs targeting the
current branch as their base — read `STACK_PARENT` and the `DEPENDENT_PR=<n>
HEAD=<branch>` lines from its output. If `STACK_PARENT=true`, this PR is the
parent of a stack. To re-probe on demand:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/git-pr.sh" --home-dir "$HOME" --project-dir "$(pwd)" --base origin/main
```

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

### After a squash-merge: rebase dependents off the squashed commits

Re-targeting alone keeps the dependent **open**, but its diff is still wrong.
When the parent is **squash-merged** (the release-please / conventional-commit
default), its commits collapse into one new commit on the base with a fresh
SHA — so a re-targeted dependent still carries the parent's *original* commits
in its history and now double-counts the parent's work. Drop them by replaying
only the dependent's own commits onto the updated base:

```bash
git fetch origin
git rebase --onto origin/main <old-parent-tip> <dependent-branch>
git push --force-with-lease origin <dependent-branch>
git log --oneline origin/main..HEAD   # verify: only the dependent's own commits
```

Capture `<old-parent-tip>` with `git rev-parse <parent-branch>` **before**
merging the parent (the branch is deleted on merge, so grab the SHA first). A
*merge*-merged parent keeps its patch-ids, so a plain `git rebase origin/main`
auto-skips the duplicates instead — but squash is the common default, so assume
the `--onto` form. If the dependent and the parent edited the same lines, expect
a conflict here: resolve it once and let `git rerere` replay it across this and
any sibling dependent (see the git-conflicts skill).

### Ad-hoc stacked PRs get no CI until retargeted

CI configured with `on: pull_request: branches: [main]` only runs for PRs
**targeting `main`**. A dependent PR based on a feature branch therefore shows
**no checks at all** until it is re-targeted — unless the chain is a
GitHub-registered stack, where those workflows run for every PR in the stack
(`git-plugin:git-stacked-prs`) — its pre-merge verification falls
to a local build/test run in the meantime. Retarget early (or verify locally);
don't wait on a green check that will never appear while the PR's base is a
feature branch.

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
