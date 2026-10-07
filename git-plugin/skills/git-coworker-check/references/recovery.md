# Recovery

Moved verbatim from `SKILL.md` § Recovery. Read when detection did not prevent a collision, or the verdict is `bare_flip_suspected`.

## Recovery

Detection prevents corruption. When prevention fails — a coworker
session moved HEAD between your steps, your commit landed on the
wrong branch, your branch accumulated commits you didn't make — see
[REFERENCE.md](../REFERENCE.md) for procedural recovery.

Quick triage:

| Symptom | Action |
|---|---|
| Your commit is on a branch you didn't expect | REFERENCE.md § Scenario 1 (mixed-reset + `git branch -f` + cherry-pick) |
| About to `git push -u` a new branch, or it holds a commit you didn't author | REFERENCE.md § Shared-checkout branch isolation (`origin/main..HEAD` check; `git branch -a --contains` before any rewrite) |
| `git switch` carried unfamiliar WIP into the new branch | REFERENCE.md § Scenario 2 (selective `git checkout HEAD -- <paths>`) |
| `git stash list` is shorter than you remember | REFERENCE.md § Scenario 3 (recover via `git fsck --unreachable`) |
| You force-pushed the polluted branch already | REFERENCE.md § Scenario 4 (only `--force-with-lease` mitigations) |
| Every `git status`/`commit` fails with "fatal: this operation must be run in a work tree" | Bare-flip recovery below (`core.bare false` + unset leaked env) |

**Always run `git reflog -20` first.** The reflog is the ground truth
for every HEAD move and ref update during the collision window —
recovery procedures all begin from a clear reflog read.

### Recovering from a bare flip / leaked GIT_DIR (issue #1692)

When detection returns `bare_flip_suspected`, the shared checkout was
flipped to `core.bare=true` (or a `GIT_DIR` / `GIT_WORK_TREE` env was
leaked) by a concurrent agent fleet. Recover before any further git ops:

1. **Flip `core.bare` back to false** so the working tree is usable again:

   ```
   git config core.bare false
   ```

   If even `git config` refuses, drive it explicitly with the recovery
   override the issue used (note `-c core.bare=false` plus an explicit
   `GIT_DIR`/`GIT_WORK_TREE`):

   ```
   GIT_DIR=.git GIT_WORK_TREE=. git -c core.bare=false status
   ```

2. **Unset any leaked env** reported as `LEAKED_GIT_DIR` /
   `LEAKED_GIT_WORK_TREE` so git stops targeting another tree:

   ```
   unset GIT_DIR GIT_WORK_TREE
   ```

3. **Recover wiped untracked work.** A concurrent branch switch / reset
   can silently delete *uncommitted, untracked* files. Untracked files
   are not in the reflog, so check first for any copy a sibling agent
   committed — `git fsck --unreachable` and the agent worktree branches
   are the best source:

   ```
   git reflog -20
   git fsck --unreachable
   git worktree list
   git branch -a
   ```

   A file an agent worktree committed survives on its branch even when
   the parent's untracked copy was wiped. If no committed copy exists,
   the work is unrecoverable — which is why committing early matters.

### Commit early to minimize untracked-file exposure

Untracked files are the only work a concurrent branch switch/reset can
destroy with no recovery path (committed work survives in the reflog;
untracked work does not). When many sibling worktrees are active in one
clone — high `LINKED_WORKTREE_COUNT`, or a `coworker_detected` /
`bare_flip_suspected` verdict — **commit or stash new files promptly**
rather than leaving them untracked, and prefer working in your own
`git worktree add ../<repo>-<task>` so a flip in the shared checkout
cannot reach your tree.
