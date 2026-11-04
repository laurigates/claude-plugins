# Workflow Guidance

Moved verbatim from `SKILL.md`. Read when handling pre-commit output, choosing direct vs feature-branch mode, or writing issue references.

## Workflow Guidance

- After running pre-commit hooks, stage files modified by hooks using `git add -u`
- Unstaged changes after pre-commit are expected formatter output - stage them and continue
- **Direct mode** (`--direct`): Use `git push origin HEAD` to push current branch directly
- **Feature branch mode** (default): Create a local feature branch from main, commit there, push with `git push -u origin <branch>`
- When encountering unexpected state, report findings and ask user how to proceed
- Include all pre-commit automatic fixes in commits
- **GitHub issue references (REQUIRED)**: Every commit should reference related issues:
  - **Closing keywords** (`Fixes`, `Closes`, `Resolves`) auto-close issues when merged to default branch
  - **Reference keywords** (`Refs`, `Related to`, `See`) link without closing - use for partial work
  - Format examples: `Fixes #123`, `Fixes: #123`, `fixes org/repo#123`
  - Multiple issues: `Fixes #1, fixes #2, fixes #3` (repeat keyword for each)
  - When `--issue <num>` provided, use `Fixes #<num>` or `Closes #<num>` in commit body
  - If no specific issue exists, consider creating one first for traceability

## Issue reference keywords (Step 3)

   - **Closing keywords** (auto-close when merged to default branch):
     - `Fixes #N` - for bug fixes that resolve an issue
     - `Closes #N` - for features that complete an issue
     - `Resolves #N` - alternative closing keyword
   - **Reference without closing** (for related context):
     - `Refs #N` - references issue without closing
     - `Related to #N` - indicates relationship
   - **Cross-repository references**:
     - `Fixes owner/repo#N` - closes issue in different repo
   - **Multiple issues**: `Fixes #1, fixes #2, fixes #3`
   - Keywords are case-insensitive and work with optional colon: `Fixes: #123`

## Merge pitfall: deleting the branch from its own worktree

> **Pitfall — `--delete-branch` from the PR's own working tree:** before running `gh pr merge <N> --<method> --auto --delete-branch`, switch your working tree to `main` (or any branch other than the PR head). If your cwd or any worktree has the PR's branch checked out, the local-branch-delete step fails with `cannot delete branch 'X' used by worktree at Y` even though the server-side merge is queued correctly. The misleading error makes it look like the merge failed; confirm with `gh pr view <N> --json state`.
>
> Safer two-step pattern:
>
> ```bash
> git switch main
> git pull
> gh pr merge <pr-number> --<method> --auto --delete-branch
> ```

## Follow-up issue example (Step 5a)

```bash
# Write tool → /tmp/follow-up.md (markdown body, no shell escaping)
gh issue create \
  --title "[Chore] DB: Run migration for new schema" \
  --body-file /tmp/follow-up.md \
  --label "chore"
# Note the returned issue number for the PR body
```

Common follow-up types: database migrations, production deployments, manual config changes, external documentation updates, customer-facing announcements, dependent follow-on PRs.
