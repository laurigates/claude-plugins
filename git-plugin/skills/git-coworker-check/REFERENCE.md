# git-coworker-check — Recovery REFERENCE

When detection fires *too late* — i.e., a coworker collision has already
corrupted your local git state — this reference walks through specific
recovery scenarios. Detection (SKILL.md) prevents the damage; this file
fixes the damage when prevention failed.

## When To Reach For This File

You ran a destructive op in good faith, the coworker's interleaved
operation moved HEAD between your steps, and now something is on a
branch where it doesn't belong. Common symptoms:

| Symptom | Likely scenario |
|---|---|
| `git log --oneline -1` shows your commit on a branch you didn't expect | A coworker switched HEAD between your `git switch -c` and your `git commit` |
| Your feature branch contains commits that belong to someone else's WIP | A coworker committed onto your branch before switching away |
| `git status` shows files you don't recognise as your work | A coworker's `git switch` carried their WIP into your tree |
| `git stash list` is unexpectedly empty | A coworker ran `git stash drop` thinking the stash was theirs |

Before doing anything else: **run `git reflog -20` and read the timeline**.
The reflog is the ground truth — every HEAD move, commit, and reset is
recorded. The recovery procedure is always "figure out what each step
did, then undo only your commits, never theirs."

## Scenario 1 — Your commit landed on the wrong branch

**Symptoms**

You ran:
```
git switch -c feat/your-thing origin/main
# ...edits, terraform validate, etc...
git add path/to/file
git commit -m "feat(scope): your message"
```

But `git log --oneline -1` now shows your commit on a *different* branch
(typically the coworker's WIP branch). `git reflog -20` will reveal an
interleaved `checkout: moving from feat/your-thing to <other-branch>`
between your `switch` and your `commit`.

Worse, your intended branch (`feat/your-thing`) may now point at one of
the coworker's commits because they committed onto it before switching
away.

**Recovery** (all operations are local-only and reversible via reflog)

```
# 1. Snapshot the current state of every ref you care about
git rev-parse HEAD feat/your-thing <coworker-branch> origin/main

# 2. Drop your commit from the wrong branch.
#    `--mixed` moves HEAD back and leaves your file changes UNSTAGED.
#    This preserves the working tree (including any unrelated WIP).
git reset --mixed HEAD~1

# 3. Revert ONLY your files to clean. The coworker's WIP modifications
#    in the working tree must NOT be touched. List paths explicitly.
git checkout HEAD -- path/to/file path/to/other-file

# 4. Force-move feat/your-thing back to origin/main (drops the
#    coworker's pollution from the branch).
git branch -f feat/your-thing origin/main

# 5. Switch to the clean feat branch.
git switch feat/your-thing

# 6. Cherry-pick your orphaned commit by SHA.
#    The commit object still exists (reflog keeps it for ~30 days);
#    cherry-pick re-applies its diff to the new base.
git cherry-pick <your-orphaned-sha>

# 7. Sanity check: branch diff against origin/main should be EXACTLY
#    your intended change.
git diff origin/main...HEAD --stat
```

**Why each step matters**

| Step | Why |
|---|---|
| `git reset --mixed` not `--hard` | `--hard` wipes the entire working tree, including coworker's unrelated WIP. `--mixed` only moves HEAD; working tree stays exactly as it was. |
| `git checkout HEAD -- <explicit paths>` | A bare `git checkout HEAD -- .` would clobber the coworker's WIP files too. Only revert the files you committed. |
| `git branch -f` while not on the branch | Safe operation: moves a ref without touching the working tree. Reflog records the move so you can recover if you targeted the wrong commit. |
| Cherry-pick by SHA, not by branch | The SHA is the durable identifier. The orphaned commit isn't on any branch tip, but its object exists until git gc runs. |
| Final `git diff origin/main...HEAD --stat` | This is a **branch** diff (three dots), not a working-tree diff. Confirms the feat branch contains exactly the commits you meant, with no carryover from the coworker. |

## Scenario 2 — Coworker's WIP carried into your `git switch`

**Symptoms**

`git switch <branch>` succeeded, but your working tree now contains
modifications you didn't make. The coworker had uncommitted changes
when you switched, and `git switch` carried them along (the default
when no conflicts).

**Recovery**

```
# Distinguish their WIP from yours.
git status --porcelain=v2 | head -40

# For files that are ENTIRELY the coworker's WIP and you didn't touch:
git checkout HEAD -- path/to/their-file

# For files where their WIP overlaps with yours: stash YOUR work in
# progress first (label it), then revert the file, then unstash and
# let conflict resolution surface the overlap.
git stash push -m "my-work-$(date +%s)" -- path/to/contested-file
git checkout HEAD -- path/to/contested-file
git stash pop
```

Do **not** run a bare `git checkout HEAD -- .` — it wipes both yours
and theirs.

## Scenario 3 — Coworker dropped a stash that was yours

**Symptoms**

`git stash list` is empty (or shorter than expected), and you know you
had work stashed. The coworker ran `git stash drop` or `git stash pop`
thinking the stash was theirs.

**Recovery — only if no GC has run yet**

Dropped stashes are still in the object database until git's garbage
collector runs (default: stale objects > 2 weeks old, runs on `git gc`
or implicitly on heavy operations).

```
# Find unreferenced commit objects with stash-shaped commit messages
git fsck --unreachable --no-reflogs 2>/dev/null \
  | rg '^unreachable commit' \
  | awk '{print $3}' \
  | while read -r sha; do
      msg=$(git log -1 --format='%s' "$sha" 2>/dev/null)
      if echo "$msg" | rg -q '^WIP on |^On '; then
        echo "$sha $msg"
      fi
    done
```

For each candidate SHA, inspect:
```
git stash show -p <sha>
```

To restore:
```
git stash apply <sha>
# or, to fully resurrect into the stash list:
git update-ref refs/stash <sha>
```

If `git fsck` returns nothing useful, the stash is gone — the worker
ran `git gc` or the commit predates the reflog window.

## Scenario 4 — You force-pushed the polluted branch

**Symptoms**

You ran `git push --force` on `feat/your-thing` before realising it
contained coworker commits. The remote now has the polluted history.

**Recovery**

This is the only scenario where prevention is the only real fix —
the remote ref has been overwritten and other clones may have already
fetched the bad state. The mitigations:

1. **If no one else has fetched yet**: re-run Scenario 1's local
   recovery, then `git push --force-with-lease` to rewrite the remote.
   `--force-with-lease` will reject the push if anyone else has
   advanced the remote ref in the meantime.
2. **If a CI pipeline ran on the polluted branch**: cancel any
   in-flight CI runs that match the bad SHA (they may try to deploy).
3. **Communicate**: anyone who fetched the bad ref needs to
   `git fetch --prune` and reset their local tracking branch.

`--force-with-lease` is the safe-by-default force-push. Plain
`--force` makes Scenario 4 worse, not better — it cannot detect that
someone else's pollution is now on the remote.

## Avoiding the Whole Class of Problem

The robust answer to coworker collision is **worktrees**:

```
git worktree add ../your-repo-task feat/your-thing
cd ../your-repo-task
# isolated working tree, separate HEAD, separate index
```

A worktree has its own `.git/HEAD` and index. No coworker session can
move HEAD between your steps, because they're on a different working
directory entirely. The `git-coworker-check` skill's own SKILL.md
recommends this as the structural fix; recovery procedures in this
file should only be needed when worktree discipline broke down (or
when you joined a session already in progress and didn't realise it
was shared).

When a session-start detection flags `coworker_detected`: stop, create
a worktree, and start fresh. That is one minute of overhead versus
the 20+ minutes a Scenario 1 recovery costs.

## Field Notes

- **theme-management Sentry secrets PR, 2026-05-27**: Scenario 1 played
  out exactly as documented above. Reflog showed the coworker's two
  commits had interleaved with my switch-and-commit sequence. The
  recovery procedure (steps 1–7) took ~3 minutes and produced a clean
  feat branch with exactly the intended diff (2 files, +29 lines)
  while leaving the coworker's redpanda branch tip and uncommitted
  WIP undisturbed. The full reflog trace and the diff before/after
  recovery are in the PR thread:
  https://github.com/ForumViriumHelsinki/infrastructure/pull/1840
