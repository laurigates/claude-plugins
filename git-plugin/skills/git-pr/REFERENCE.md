# Git PR - Reference

Full PR description templates, main-branch push patterns, stacked-PR merge rules, and post-merge follow-up issue workflow.

## PR Description Format

### Standard Template

The squash body follows the repo's `squash_merge_commit_message`:
`COMMIT_MESSAGES` on release-please repos such as claude-plugins, `PR_BODY`
elsewhere (OpenTofu-managed in laurigates/gitops `main.tf`;
laurigates/gitops#318 moves release-please repos to `PR_BODY`). On a `PR_BODY`
repo a squash-merged PR's body becomes the commit body on `main` — see
[merge-strategies.md](../github-pr-title/merge-strategies.md). So the template
is a commit body: plain prose, then footers. No headings, checklists or HTML
comments; on `PR_BODY` repos the merge-method body lint flags all three.

```markdown
Add retry with backoff to the webhook dispatcher so transient 5xx responses
from receivers no longer drop events. Receivers behind a cold-starting proxy
returned 502 on the first delivery and the event was never retried.

- Retry up to 5 times with jittered exponential backoff
- Record final failures in the dead-letter table
- Expose the retry count as a metric

Follow-up: #456 (run the schema migration after deploy), #457 (update the deployment runbook)

Fixes #123
Refs #124
Refs #456
```

### Body parts

| Part | Purpose | Required |
|------|---------|----------|
| Opening paragraph | What the PR does and why (1–3 sentences) | Yes |
| Change list | Key changes as bullet points | When there is more than one |
| `Follow-up:` line | Issues tracking post-merge actions (see [§ Post-Merge Follow-up Issues](#post-merge-follow-up-issues)) | If post-merge work exists |
| Footer block | Closing keywords and `Refs` lines, one per line, last paragraph | Yes |

Pre-merge verification ("tests pass", "docs updated") goes in a PR comment or
the CI checks, not in the body.

### Issue Linking Syntax

Place at the **bottom** of the PR description, one per line, with no blank
lines between them:

```markdown
Fixes #123
Closes #456
Resolves #789
Refs #124
```

| Keyword | Effect |
|---------|--------|
| `Fixes #N` / `Closes #N` / `Resolves #N` | Auto-closes on merge |
| `Refs #N` | Links without closing |

**Rules:**
- Use `Fixes`, `Closes`, or `Resolves` for issues this PR solves
- Use `Refs` for issues that are related but not solved, including follow-up
  issues — `Closes #N after merge` still closes `#N` the moment the PR merges
- Follow-up work should be created as new issues, not left in a checklist

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
| No dependents (leaf PR) | `gh pr merge --<method> --delete-branch` (default) |
| Has dependents | `gh pr merge --<method>` — **omit `--delete-branch`** |
| Has dependents, want to clean up | Re-target dependents first (see [§ Re-targeting dependents](#re-targeting-dependents)), then merge with `--delete-branch` |

`<method>` is `rebase` or `squash`, whichever `pr-merge-method.py` reports
([merge-strategies.md](../github-pr-title/merge-strategies.md)). Rebase is the
default and keeps a stack cheap to update (next section).

### Re-targeting dependents

Before merging the parent, point each dependent at the parent's base so
they don't auto-close when the parent's branch disappears:

```bash
# For each dependent PR returned above:
gh pr edit <dep-pr-num> --base "$(gh pr view --json baseRefName --jq .baseRefName)"
```

Once every dependent has been re-targeted (or you have explicitly chosen
not to), it is safe to merge the parent with `--delete-branch`.

### After the parent merges: rebase dependents onto the base

Re-targeting alone keeps the dependent **open**, but its history still carries
the parent's *original* commits.

- **Rebase-merged parent:** the parent's commits land on the base as
  patch-equivalent commits, so a plain `git rebase origin/main` skips them.
- **Squash-merged parent:** its commits collapse into one new commit with a
  fresh SHA, so the dependent now double-counts the parent's work. Replay only
  the dependent's own commits:

```bash
git fetch origin
git rebase --onto origin/main <old-parent-tip> <dependent-branch>
git push --force-with-lease origin <dependent-branch>
git log --oneline origin/main..HEAD   # verify: only the dependent's own commits
```

The `--onto` form is correct after either method, so use it when unsure.
Capture `<old-parent-tip>` with `git rev-parse <parent-branch>` **before**
merging the parent (the branch is deleted on merge, so grab the SHA first). If
the dependent and the parent edited the same lines, expect a conflict here:
resolve it once and let `git rerere` replay it across this and any sibling
dependent (see the git-conflicts skill).

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

When a PR requires actions **after** it is merged, create a separate GitHub issue for each follow-up. Link all follow-up issues in the PR description on a `Follow-up:` line, with a `Refs #N` footer for each.

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
   gh pr view <pr-number> --json body -q .body > /tmp/pr-body.md
   # add a "Follow-up: #<n> (…), #<n> (…)" line above the footer block,
   # and a "Refs #<n>" footer per follow-up issue
   gh pr edit <pr-number> --body-file /tmp/pr-body.md
   ```
4. **Do NOT** add post-merge steps as a checklist in the body.

### Example: PR description with follow-up issues

```markdown
Follow-up: #456 (run database migration for user_preferences table), #457 (update production feature-flag config)

Fixes #123
Refs #456
Refs #457
```
