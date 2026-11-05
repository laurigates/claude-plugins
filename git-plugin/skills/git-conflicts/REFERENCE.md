# git-conflicts - Reference

Detail moved verbatim from [SKILL.md](SKILL.md): read when conflicts keep recurring after squash merges, when landing several branches together, or for the Step 5 PR comment example.

## Squash Merge Pitfall

If the same conflicts keep recurring, the likely cause is squash merges. Squash-merging breaks the common ancestry chain, so stacked or sibling branches lose their merge base. Rerere mitigates this by replaying recorded resolutions, but the root fix is to rebase-merge branches with dependents (see [merge-strategies.md](../github-pr-title/merge-strategies.md)). When a squashed base leaves a dependent carrying the now-collapsed commits, recover with `git rebase --onto origin/main <old-base-tip> <dependent>` (see the git-pr skill's Stacked PRs section).

## Pre-Merge Trial Integration (landing a wave of PRs)

When several branches will land together — a wave of parallel feature branches,
a PR stack, or sibling fixes touching overlapping files — surface and resolve
the conflicts **once, on a throwaway branch, before touching `main`**. This also
catches the *silent* failure a plain auto-merge can't: when two branches each add
the **same** helper/import in non-adjacent spots, git merges both copies with no
conflict, producing a tree that does not compile. The merge *message* is not
proof of correctness — only compiling the merged tree is.

```bash
# rerere on, so the resolution you do here is recorded for the real merges
git config rerere.enabled true
git config rerere.autoupdate true

git switch -c trial/integration origin/main
for b in <branch-1> <branch-2> <branch-3>; do
  git merge --no-ff --no-edit "origin/$b" || git commit --no-edit   # resolve, then commit
done

<build + test command>          # e.g. just check / cargo test / npm test — the real gate
```

If the merged tree builds and tests green, the resolution is validated **and
rerere has cached it**. Discard the trial branch and do the real merges/rebases
in order — rerere auto-replays the same resolution on the actual base merge and
on each dependent's `--onto` rebase (see git-pr Stacked PRs), so you never
re-resolve by hand:

```bash
git switch main && git branch -D trial/integration   # the rerere cache persists
```

Payoff: conflicts surface before `main` is touched (not mid-merge under
pressure); one resolution is replayed everywhere via rerere; and compiling the
merged tree catches silent duplicate-addition merges a green merge message hides.

## PR comment example (Step 5)

  ```
  gh pr comment <number> --body "Merge conflicts with <base-branch> resolved automatically.

  Resolved files:
  - file1.json (merged entries from both sides)
  - file2.md (combined changelog entries)
  "
  ```
