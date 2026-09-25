---
name: git-local-hazards
description: Local git traps where a green command is wrong. Use when branching after a squash-merge, cutting a PR branch, after a clean merge or rebase, when a staged file vanishes, or before reset --hard.
allowed-tools: Read, Grep, Glob, Bash(git *), Bash(gh pr list *), Bash(grep *), TodoWrite
created: 2026-09-24
modified: 2026-09-25
reviewed: 2026-09-24
---

# Git Local Hazards — Verify the Content, Not the Exit Code

Promoted from the always-loaded `~/.claude/rules/git-hazards.md` rule, whose
stub keeps the gate lines. The body below is that rule's text. Sibling:
`git-plugin:git-merge-hazards` (GitHub PR/merge machinery), which follows the
same promotion pattern.

Six local-git traps, one law: **a green git command is not proof the result is
correct** — exit 0 is a claim about mechanics, not content. Each: the trap, the
5-second check, the fix.

## When to Use This Skill

| Use this skill when... | Use something else when... |
|---|---|
| Starting follow-up work after a branch's PR squash-merged | Deciding whether a branch really landed on GitHub → `git-merge-hazards` |
| Cutting a new PR branch | Another agent may be moving HEAD in this clone → `git-coworker-check` |
| A merge or rebase reported success over sibling work | Resolving an actual conflict → `git-conflicts` |
| A staged file vanished or `git status` flaps | Deleting a whole checkout → `git-repo-delete-check` |
| About to `reset --hard` / `checkout` / `restore` / `clean`, or recovering after one | |

## 1. Commits added after a squash-merge are orphaned

Anything committed to a branch **after** its squash-merge is in neither `main`
nor the squash commit. A fresh branch off `origin/main` silently lacks that
work; the first symptom is an ImportError far downstream.

- **Check** before follow-up work: `git grep <symbol> origin/main -- <path>` —
  don't trust "the PR merged". The symbol must be **unique to the change**: a
  grep for `tier == "deliver"` reported a change as landed when the hit came
  from a pre-existing line that merely contained the same text (2026-08-19).
  Prefer `git cherry origin/main <branch>` — `+` means not upstream, and it
  survives SHA rewriting (rebase, cherry-pick) and a single-commit squash,
  which plain ancestry checks do not. It does **not** survive a multi-commit
  squash: no single commit's patch matches the combined squash commit, so
  every commit — landed or orphaned — reads `+`. There, compare
  `git log --format='%h %cI %s' origin/main..<branch>` against the PR's
  `mergedAt`; commits dated after it are the orphans.
- **Fix**: replay only the orphans: `git rebase --onto origin/main <squash-point> <branch>`,
  then verify `git log --oneline origin/main..HEAD` shows only the orphaned + new commits.
  Confirm nothing was lost by comparing **trees**, not diffs:
  `git rev-parse HEAD^{tree} <old-tip>^{tree}` must match.

### The variant with no symptom at all: the PR merges WHILE you are still on the branch

The framing above assumes you come back later and branch afresh. The quieter
case is that you **never leave**: the PR is merged mid-session — by CI, by a
teammate, by the user in another window — and you keep committing to the same
branch. Every `git push` succeeds, `git status` is clean, and nothing says the
branch's PR is closed. Observed 2026-08-19: two commits, and the source that
produced an hour-long delivery render, sat on a branch whose PR had already
merged. It surfaced only because an unrelated `git switch main` failed on local
changes.

- **The tell is on the remote, not locally.** `gh pr list --head <branch>`
  returns nothing (and `--state all` shows MERGED) while you still have commits
  in `origin/main..HEAD`.
- **Do not reuse the merged branch for the new PR.** A merged PR cannot take new
  commits; push the rebased work to a **new** branch name so the fresh PR is not
  tangled with the closed one.
- Cheap habit: before the *second* push to any branch in a long session, run
  `gh pr list --head "$(git branch --show-current)" --json number,state`.

## 2. Unpushed commits on local `main` ride into new branches

Branching off local `main` inherits whatever it is ahead of `origin/main` by;
the PR then bundles stray commits under an unrelated title (squash hides it —
visible only in the file list).

- **Rule**: cut PR branches from the remote, always:
  `git fetch origin && git switch -c <branch> origin/main`.
- **Check** when unsure: `git log --oneline origin/main..main` — empty means clean.

## 3. A clean textual merge can duplicate identical additions

When two branches each add the **same** helper/import/enum arm in non-adjacent
spots, `git merge` sees no overlapping hunk, reports success, and keeps **both
copies** — a duplicate-definition build break (or worse, silent shadowing in
lax languages).

- **Check**: build/test the merged tree before committing the merge; when
  siblings solved related problems, `grep -c '<symbol>' <file>` — expect 1.
- **Fix**: hand-resolve to a single combined definition; never trust
  "Automatic merge went well" as a verdict on content.

**The rebase variant: zero conflicts, broken result, no textual overlap.** Same
law, and easier to miss because a rebase that replays cleanly *feels* verified.
When `main` gains a file that depends on state your branch **removed**, the two
never touch the same lines, so there is nothing to conflict on — and the merged
tree is still broken.

> Observed 2026-08 (a data-pipeline repo): a branch removed TimescaleDB by
> rewriting the three `0001_initial` migrations. Meanwhile `main` gained
> `measurements/0004`, calling `decompress_chunk()`/`show_chunks()`
> unconditionally. `git rebase origin/main` reported **success with no
> conflicts** — different files — and produced a migration tree that cannot
> apply on the plain PostgreSQL the branch exists to target
> (`function show_chunks(unknown) does not exist`). Caught by reading `main`'s
> new commits, not by any gate.

- **Check after any rebase that spans many upstream commits**: list what `main`
  added while you were away (`git log --oneline --name-only <old-base>..origin/main`)
  and ask whether any of it depends on something your branch deletes — an
  extension, a column, a helper, a config key. Then run the suite *on the target
  environment*, not just the one you develop in.
- The durable fix is a **CI matrix over both environments**; a hand-run recorded
  in a PR description is what let the original divergence through.

## 4. `git add` aborts atomically on a bad pathspec

`git add fileA nonexistent` stages **nothing** — not "fileA plus a warning".
Classic trip: `git mv old new`, edit `new`, then `git add new old` → the stale
`old` aborts the add, and the commit ships the rename with pre-edit content.

- **Rules**: one pathspec per `git add`, or only confirmed-present paths.
  After `git mv` + edit, `git add <newname>` alone.
- **Check**: `git status --short` before committing — the index column must
  show the change you intend.
- **Recovery**: the edit is still unstaged in the working tree; add and
  commit/amend — don't redo the work.

## 5. A "vanished" staged file in a shared checkout was probably committed by a coworker

Sibling of the push-by-SHA HEAD race in `git-plugin:git-merge-hazards` (the
stacked-chain protocol and its three async races): the **index and HEAD are
process-global**, so a coworker session's commit lands between two of your Bash
calls with no warning. Observed 2026-07 (dotfiles): a file another session had
staged (`A `) disappeared from `git status`, then `ls` said it didn't exist,
then status flapped `A ` → `M ` across consecutive calls. The wrong theory
("pre-commit's stash dance ate it") was nearly acted on; the truth was the
coworker had committed the file to `main` mid-flight — every observation was a
stale read of state the coworker kept moving.

- **Check first, before any recovery**: `git log --oneline -3` — did HEAD
  move? — and `git log -1 -- <path>`; a fresh commit touching the path is the
  discriminator between "lost" and "landed".
- **Don't blind-restore.** Re-adding your own copy of a "lost" file can
  silently **downgrade** the coworker's version (observed: the restored copy
  lacked frontmatter the coworker had added before committing). Diff your
  candidate against `HEAD:<path>` and keep the committed version unless yours
  is genuinely newer.
- **Status flapping between consecutive calls is itself the tell** that a
  coworker is active — stop mutating shared state (index, HEAD, branch
  switches) until the flapping stops; re-read state fresh in the same command
  that acts on it (same instinct as push-by-SHA).

## 6. Work destroyed by `reset --hard` is often still in a pre-commit stash

Unstaged content has no reflog entry, so this looks unrecoverable — but
`pre-commit` stashes unstaged changes around every run, and those stash
**commits** go dangling and survive until `gc`.

- **Prevent**: `git status` before `reset --hard`/`checkout`/`restore`/`clean`;
  `git stash -u` anything present.
- **Recover**: `git fsck --lost-found`, then per dangling *commit* (not blob)
  `git show <c>:<path>`; rank by `git diff --numstat HEAD <c> -- <path>`
  against the diff shape you remember.

## Related

- `git-plugin:git-merge-hazards` — GitHub-side traps: squash-merge detection,
  stacked-PR auto-close, push-by-SHA races, merging over red
- `git-plugin:git-coworker-check` — detection before destructive ops, and the
  shared-checkout branch-isolation check before `git push -u`
- `git-plugin:git-pr-sync-check` — is the current PR branch still live
