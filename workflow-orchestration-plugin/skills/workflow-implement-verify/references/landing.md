# Landing the PRs

Moved from `SKILL.md` to keep the body under the size WARN. Tests in
`scripts/tests/test-templates.sh` pin the trial-integration recipe here.

Neither template merges; land from the main session.

**Trial-integrate the landable branches before the first merge.** A verifier and a PR's CI each see
one branch on the base, so units that pass alone can break each other at landing. Two branches
can conflict in a registration file every unit legitimately edits (`.pre-commit-config.yaml`,
`CLAUDE.md`), which `owns` globs do not prevent. Two can also merge cleanly and fail, as when one
unit's new check calls a helper another unit removed. Observed 2026-11-10: four of seven landable branches conflicted
with each other, and two more merged cleanly and then failed tests. In a throwaway worktree
(`git worktree add --detach <tmp> origin/main`), merge each landable branch in landing order with
`git -C <tmp> merge --no-ff --no-edit <branch>`, and stop at the first conflict with
`git -C <tmp> merge --abort`: a conflicted merge leaves modified files that the final remove
refuses without `--force`. Run the run's `gates` on the result, then `git worktree remove <tmp>`.

**When branches conflict or break together, stack them.** Merge the base into the first branch,
the first into the second, and so on, pushing each, so every PR's CI runs on the cumulative
content. Once a lower PR is squash-merged, the next one reads as conflicting, because its history
holds the same change as separate commits. Re-sync it with the no-force route for a stacked
base in `git-plugin:git-merge-hazards`, which decides whether `-X ours` is lossless before using
it: a bare `-X ours` drops any change main made to a line the branch also edited.

When the trial integration is clean, land one PR at a time:

1. Update the branch from main (`gh pr update-branch <n>`, or a rebase in its worktree) and
   confirm `git merge-base origin/main <head>` equals `git rev-parse origin/main`. Checks that
   ran on an older base say nothing about the merged result.
2. When main moved only by a release-please commit, confirm the update touched only release
   files: `git diff --name-only <old head> <updated head>` lists none of the files in
   `gh pr diff <n> --name-only`. Then merge on the required checks of the updated head.
3. After each merge, update the next PR from the new main and repeat from step 1.

For a cross-repository run, land each repository's PRs separately. Chains and
`merge-chain.sh`: `git-plugin:git-merge-hazards`. Update-branch versus rebase, and when a
stale base is safe to leave: `git-plugin:worktree-stale-base-merge`.
