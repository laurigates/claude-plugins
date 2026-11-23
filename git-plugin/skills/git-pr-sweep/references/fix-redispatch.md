# Re-dispatching a FAILED or UNVERIFIED fix unit

SKILL.md Step 3.3 re-dispatches such a unit fresh. A fresh pr-fix agent cannot start until the main
session clears two things the dead run can leave behind.

## Why a plain re-dispatch blocks

- **The local branch is ahead of the reviewed head.** The fixer commits onto root's local
  `<branch>` (its worktree is attached to that branch, or it switches to it) and never pushes; only
  Finalise pushes, and only PASS and REPAIRED_PASS rows. An UNVERIFIED row (the verifier died) or a
  FAILED row whose fixer committed before dying leaves `<branch>` at a descendant of `head_sha`. The
  fresh unit carries the same `head_sha` from `units.json`, and the start check accepts only that
  commit or an ancestor of it, so the fresh fixer returns `blocked` every time.
- **A worktree path is already taken.** With `worktrees` set, the paths are fixed:
  `<worktrees>/repair-<unit>`, `<worktrees>/verify-<unit>`, and the same two under
  `<worktrees>/round2/`. A dead agent may never reach its `worktree remove`, and the fresh
  `worktree add` on that path then fails with "already exists". `git worktree prune` does not help:
  it drops only entries whose directory is already gone.

## Steps, per unit, in the main session

1. List what is registered: `bash <skill dir>/scripts/prune-worktrees.sh --root <root>`, adding
   `--worktrees <worktrees>` when the run set it. Each `WORKTREE_<i>=` line is a worktree that still
   exists. Harness-isolated agents (no `worktrees` arg) get worktrees the harness names; treat a
   listed one the same way only when it holds this unit's branch.
2. For each of this unit's paths in that list, `git -C <root> worktree remove <path>`. Never
   `--force`: a refusal means the tree is dirty, and its uncommitted changes are the dead agent's
   work. Report the unit for Lauri and do not re-dispatch it.
3. Compare the branch with the reviewed head: `git -C <root> rev-parse <branch>`, then
   `git -C <root> merge-base --is-ancestor <branch> <head_sha>`. Equal, or exit 0 (the branch only
   lags origin), needs no reset.
4. Otherwise keep the unverified tip, then reset the branch:
   - `git -C <root> branch rescue/<unit> <branch>` (add a numeric suffix when that name exists). The
     rescue ref keeps every commit on the tip, whoever made it; name it in the final report.
   - `git -C <root> branch -f <branch> <head_sha>`. Git refuses this while the branch is checked out
     in any worktree. When the main checkout holds it, report the unit for Lauri: the sweep never
     changes root's branch.
5. Run the `gh pr list` check from Step 3.3, then dispatch the unit fresh with the same `head_sha`.

Do not hand the fresh unit the rescued tip as its `head_sha`. Its commits were never verified, and
pr-fix treats `head_sha` as the reviewed head that Finalise and merge-gate.sh G5 compare against.
