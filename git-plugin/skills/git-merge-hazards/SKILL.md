---
name: git-merge-hazards
description: Traps in GitHub's merge machinery. Use when merging a PR, merging a stacked PR chain, auditing whether a branch really landed, or merging over red CI.
allowed-tools: Read, Grep, Glob, Bash(gh pr *), Bash(gh issue *), Bash(gh api *), Bash(git cherry *), Bash(git merge-tree *), Bash(git rev-parse *), Bash(git log *), Bash(git reflog *), Bash(git rebase *), Bash(git push *), Bash(git fetch *), Bash(just *), Bash(bash *), TodoWrite
created: 2026-08-19
modified: 2026-08-19
reviewed: 2026-08-19
---

# Git Merge Hazards

Read before merging a PR, merging a stacked PR chain, auditing whether a branch
really landed, or merging over red CI. The body below is the verbatim text of
the promoted `~/.claude/rules/pr-merge-hazards.md` rule.

Three notes that are *not* part of that body:

- Two gates below — §1's merged-ness authority order and the whole of §4 — are
  also reproduced verbatim in the `pr-merge-hazards.md` stub, because they are
  read *while* the decision is being made. Edit both copies together.
- §1 overlaps `git-plugin:deadbranch` Step 1.5 ("Reclassify squash-merged
  branches"), which carries the same three signals scoped to branch cleanup.
- The two encoded recipes cited in §1 and §2 below are the author's own (a
  `just -g` recipe in `laurigates/dotfiles`, and a sweep script in
  `laurigates/claude-plugins`), not commands a plugin consumer already has.
  Read the authority ladder in §1 as the instruction; the recipe is a
  convenience, and its REVIEW bucket measured ~90% false positives (#2268).

Four traps in GitHub's merge machinery, one law: "PR merged" says nothing about
*content* — and a red check is not proof of failure. Each: the trap, the
5-second check, the fix. Sibling: `~/.claude/rules/git-hazards.md` (local git).

## 1. `--merged` misses squash-merged branches

A squash-merge collapses a branch into one fresh-SHA commit on `main`, so the
branch's own commits are never ancestors — `git branch --merged` (and any
ancestry check) reports it **unmerged**. "Files identical to main" also fails
once `main` drifts the same files.

- **Check**, in order of authority:
  - `gh pr list --state all --head <branch> --json state` → a MERGED PR is
    **authoritative**. Reach for this first; the git-side checks below are all
    one-way.
  - `git cherry main <branch>` → marks a commit `-` when a patch-equivalent
    commit is already upstream, `+` when it is not. Survives squash **and**
    cherry-pick, and does not care that `main` drifted.
  - `git merge-tree --write-tree main <branch>` equals `git rev-parse main^{tree}`
    → contained. **A match proves containment; a non-match proves nothing.**
- **Not immune to drift** (corrected 2026-07): once `main` moves on over the same
  files, merging an already-merged branch back would re-introduce its older
  versions, so the trees differ and merge-tree reports **not contained** for work
  that fully landed. Observed reporting three merged branches as unmerged. Same
  trap as "files identical to main". Use the PR state or `git cherry` to decide;
  keep merge-tree only as a positive-containment shortcut.
- **Fix**: use the encoded recipe rather than re-deriving: `just -g branch-audit`
  (in `private_dot_config/just/git.just`) prints MERGED vs REVIEW + a paste-ready delete.
- A non-match is "review", **not** proof of unmerged — don't force the count to zero.

## 2. Merging a stacked base auto-CLOSES the child PR

When PR B is based on PR A's branch, merging A and deleting its branch
auto-closes B (GitHub does **not** retarget it), and a closed PR whose base
branch is gone **cannot be reopened**.

- **Fix — order matters**: retarget the child **first**, while the base PR is open:
  1. `gh pr edit <child> --base main`
  2. `gh pr merge <base> --squash --delete-branch`
  3. `git rebase --onto origin/main <old-base-tip> <child-branch>` (drops the
     already-squashed base commits) + `git push --force-with-lease`
  4. merge the child.
- **If already auto-closed**: the head branch survives — rebase as above,
  `gh pr create` fresh, comment "Superseded by #new" on the closed one.
- **Nothing tells you this happened.** The auto-close is silent: no failed
  check, no notification, and the PR list just looks one shorter. claude-plugins
  #2049 sat stranded for a day; a sweep then found 26 dead branches, two carrying
  work that had **never had a PR opened at all** (so no event ever fired for
  them either). A scheduled sweep is the only thing that finds this class —
  an event handler on `pull_request: closed` is too late by construction (the
  base ref is already deleted, so the reopen window is gone) and is blind to
  never-PR'd branches. `claude-plugins scripts/check-stranded-work.sh` is the
  encoded audit; it takes `--repo`, so one run sweeps the portfolio.
- **Telling an accident from a decision**: a closed-unmerged PR whose base ref
  **404s** was auto-closed; one whose base ref is still **alive** was closed by a
  human (duplicate/superseded). That single check is the discriminator — 11 of
  those 26 branches were deliberate closes and must not be resurrected.

## 3. Stacked-chain merges: push by SHA, never `HEAD:` — and expect auto-close races

Working down a stacked-PR chain (retarget child → merge base → rebase child →
force-push → merge, per #2) has three traps of its own (observed 2026-07,
claude-plugins #1979→#1987):

- **`HEAD:` in a push refspec is a race in a shared checkout.** HEAD is
  process-global repo state; a coworker session can move it *between two of
  your Bash calls*. Observed: rebase left HEAD at the child's new tip; by the
  next call HEAD was `main`'s tip, so `git push --force-with-lease origin
  HEAD:<child-branch>` overwrote the branch with main. Resolve the tip to an
  **explicit SHA in the same command that creates it** and push
  `git push --force-with-lease origin <sha>:<branch>`.
- **An empty-diff force-push auto-closes the PR — and a closed PR whose *head*
  moved after closing cannot be reopened.** Sibling of #2's
  base-branch-deleted variant. GitHub saw the branch == main, closed the PR,
  and refused `gh pr reopen` because the head ref had moved since closing.
- **A single mergeability read after a force-push is a race.** GitHub
  recomputes `mergeable` asynchronously; `gh pr merge` right after a push
  fails with "not mergeable" on a perfectly clean PR. Poll
  `gh pr view <n> --json mergeable` until it leaves `UNKNOWN`.
- **Waiting for CI races check *registration*, not just completion.** A loop on
  "zero pending checks" can exit **immediately** after a push/`update-branch`:
  zero pending is trivially true before the jobs are registered. Observed
  2026-07: `state=CLEAN` on a **single** check while three CI jobs had not yet
  appeared — merging there merges untested. Gate on **both** nothing-pending
  **and** `--jq 'length'` ≥ the expected check count. Same root cause as the
  mergeability race above: an async field read once, too early.

- **Check** before every force-push: `git log --oneline origin/main..<sha>` —
  expect *exactly* the child's commits, nothing more, never empty.
- **Recovery** when auto-closed: the rebased commits survive in local objects
  (`git reflog`) — `git push --force-with-lease origin <sha>:<branch>`, open a
  fresh PR from the branch, comment "Superseded by #new" on the closed one.

## 4. A red PR may still be mergeable — `UNSTABLE` is not `BLOCKED`

`mergeStateStatus` separates **required** failing checks (`BLOCKED` — merge
refused) from merely-present ones (`UNSTABLE` — plain `gh pr merge` works), so
`--admin` on an `UNSTABLE` PR takes a privilege you didn't need. Read it first.

Merging over red needs **two** checks: `--json files` (config/docs can't break
a compile) **and** the same check already failing on `main`. Either alone is a
guess — and a stale-green `main` lies, so check `createdAt` (2026-07: a "green"
run was 21 days old; main hadn't compiled for three weeks).


## 5. A **negated** closing keyword still closes the issue

GitHub matches `close|fixes|resolves|…` + an issue reference without parsing the
sentence around it, so the natural way to *disclaim* closure closes the issue.
Markdown emphasis between verb and number doesn't break the match either:

```
Does **not** close #162   →   GitHub reads `close #162`, and closes it
```

- **Check**: `gh issue view <n> --json closedByPullRequestsReferences` names the
  closer; a `closedAt` one second after a merge is automation, not a decision.
- **Fix**: never let a closing verb precede an issue number you don't mean to
  close — `Related: #162`, `Unblocks #162`, or `#162 stays open — it needs …`.
- **Recovery**: `gh issue reopen` works (nothing was deleted, unlike #2), then
  comment so the next reader doesn't re-derive it.

The damage is a **false status report**: 2026-08-05, a PR body written to
disclaim closure closed loractl #162 at merge, and the session reported it open
for two turns afterward. Like #2, GitHub does this silently — only re-reading
issue state from the API catches it.
