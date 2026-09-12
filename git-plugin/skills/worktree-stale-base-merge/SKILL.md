---
name: worktree-stale-base-merge
description: "Merging a PR from a parallel worktree-agent branch, or any branch cut from an older main. Use when deciding whether a green CI check still means anything after sibling branches have landed."
allowed-tools: Bash, Read, Grep, Glob, TodoWrite
created: 2026-08-06
modified: 2026-09-12
reviewed: 2026-09-12
---

# Rebase a Parallel Worktree-Agent Branch Before Merging — Its Green CI Is About a `main` That No Longer Exists

When you dispatch several `isolation: "worktree"` agents that each branch off
`origin/main` and open a PR, **the ones that finish later were cut from a main
that no longer exists.** Their CI ran against that older tree, so a green check
is a claim about a base the merge will not use. Nothing on the PR page says so:
the checks are green, the diff looks like a clean feature addition, and the
sibling work that landed in the meantime is invisible.

The merge itself is safe — see "What this rule used to say" below. The exposure
is **verification**: the branch was never built or tested against the tree it is
about to become part of. A sibling that renamed a function, changed a signature,
tightened a lint, or added a conflicting migration produces a `main` that is red
the moment both land, and the failure surfaces on someone else's PR.

This is the merge-time companion to `agent-worktree-resume-for-pr-feedback.md`
(resume vs. fresh worktree for PR feedback) and
`shared-checkout-branch-isolation.md` (commit-time HEAD contamination). Here the
hazard is purely about the **base** a parallel branch was cut from.

## First, don't confuse this with containment

"Is this branch's base still current?" (this skill) and "has this branch's work
already landed?" are different questions with different tools, and the second
has its own authority order — a MERGED PR is authoritative, `git cherry` next:

```sh
gh pr list --state all --head <branch> --json state,mergedAt   # MERGED = authoritative
git cherry main <branch>                                       # '-' = patch already upstream
```

`git merge-tree` is a **positive-containment** shortcut for that second
question, never its primary signal: a match proves the work landed, a non-match
proves nothing once the base has drifted over the same files. Everything below
uses merge-tree for the *other* direction — what tree the merge will produce —
where it is authoritative both ways. `git-plugin:git-merge-hazards` owns the
containment ladder in full.

## What this rule used to say, and why it was wrong

Until 2026-07 this rule claimed that a stale-based branch's diff showing sibling
files as deletions meant **merging it would revert that work**, and prescribed
`git diff --stat origin/main <branch>` as the gate. That diagnostic was wrong,
and the reasoning is worth keeping because two stale plan files still restate it
(`~/.claude/plans/giggly-orbiting-locket.md:63-65`,
`parallel-percolating-sunset.md:147-148` — session history, deliberately left
alone; if a future distill pass reads them next to this rule, **this section is
the tie-breaker**).

`git diff A B` is a **two-dot** diff: it compares two *tips*. Everything `main`
gained after the fork therefore always renders as `D` in that direction — that
is what a two-dot diff means, not a warning. A merge does not apply that diff:
a three-way (and GitHub's squash) merge resolves from the **merge base**, so a
file only `main` touched is taken from `main` unchanged. Deletions in the
two-dot diff are an artifact of the comparison, not a preview of the result.

Proven on PR #2240 (2026-07): `git merge-tree --write-tree` contained all four
sibling files the two-dot diff showed as deletions, and post-merge `main`
confirmed it. The old rule's own worked example (loractl Phase 4) never
demonstrated a revert — it demonstrated a two-dot diff.

The **prescription** survives unchanged: rebase or `update-branch` before
merging. Only the reason moved — from "the merge will delete things" to "the
green check is about a tree that no longer exists."

## The 5-second check — merge-base equality

Ask whether the branch's base is still `main`'s tip. That is the question a diff
cannot answer:

```sh
git fetch origin
test "$(git merge-base origin/main <branch>)" = "$(git rev-parse origin/main)" && echo "base current" || echo "STALE BASE — green CI proves nothing about post-merge main"
```

`base current` ⇒ CI ran against what the merge will produce. A stale base is not
by itself a reason to block — see Prevention for when it is cheap to leave.

## The two readings of `merge-tree` — do not conflate them

`git merge-tree --write-tree` appears in two rules with **opposite** strengths,
and mixing them up is exactly what produced the false claim above.

| Reading | Question | Authority |
|---|---|---|
| **Backward** (`~/.claude/rules/pr-merge-hazards.md` #1) | "Is this branch's content already in `main`?" | **One-way.** A match proves containment; a non-match proves nothing — once `main` drifts over the same files the trees differ for work that fully landed. |
| **Forward** (this rule) | "What tree does merging produce?" | **Authoritative both ways.** It *is* the merge — it resolves from the merge base and writes the resulting tree. |

The one-way caveat belongs to the backward reading only. **Do not import it
here**, and do not import this reading's confidence there.

`claude-plugins/scripts/check-stranded-work.sh:57-65` already keeps them
straight and carries a "do not reintroduce it here" guard on the backward
reading — read that comment before touching either rule.

```sh
# Forward reading: what will the merge actually produce?
merged=$(git merge-tree --write-tree origin/main <branch> | head -1)   # resulting tree SHA
git diff --stat "origin/main" "$merged"
```

That second command is the honest "what changes when this lands" view — it diffs
`main` against the **merged tree**, so it is three-way and shows only real
changes. Diffing `main` against the **branch tip** instead is the two-dot form
that produced the false claim.

## The cheap fix first — `gh pr update-branch` (no force-push)

When the branch is **not** history-sensitive — no stacked child depending on
its SHAs, no requirement for linear history — prefer merging main *into* the
PR branch over rebasing it:

```sh
gh pr update-branch <n> -R <owner>/<repo>
git fetch origin
test "$(git merge-base origin/main <branch>)" = "$(git rev-parse origin/main)" && echo "base current" || echo "STILL STALE"
```

This resolves the stale base with **no force-push**, so it sidesteps the whole
hazard family the rebase path carries: no `HEAD:`-refspec SHA race
(`~/.claude/rules/git-hazards.md` #7), no empty-diff auto-close, no
force-with-lease confirmation, and nothing destructive to recover from if it
goes wrong. The squash-merge collapses the extra merge commit anyway, so the
landed history is identical to the rebased version.

**`gh pr update-branch` lies in both directions — never trust its message.**
Observed 2026-07: it printed *"Cannot update PR branch due to conflicts"* twice
while actually succeeding, and once failed genuinely with a similar message.
The message is not the signal; re-run the merge-base check above and believe
that. Then let CI re-run and go green *on the new base* — that re-run is the
entire point of the exercise.

Reach for the rebase below when `update-branch` is wrong: a stacked child needs
the parent's SHAs to stay rebase-able, the repo requires linear history, or the
branch is pinned to an agent worktree and you also need to re-run its tests
there before pushing.

## The fix — rebase in the worktree, then re-verify

The agent's worktree still holds the branch, so rebase there (a fresh checkout
can't take a branch pinned to a live worktree — see the sibling rule):

```sh
WT=.claude/worktrees/agent-<id>
git -C "$WT" fetch origin
git -C "$WT" rebase origin/main         # resolve conflicts in the region siblings touched
# re-run the branch's load-bearing test IN THE WORKTREE (its own target dir):
cargo test --manifest-path "$WT/Cargo.toml" -p <crate> --test <the_guard_test>
sha=$(git -C "$WT" rev-parse HEAD)
git -C "$WT" log --oneline origin/main..HEAD          # expect exactly the branch's own commit(s)
git -C "$WT" push --force-with-lease origin "${sha}:refs/heads/<branch>"
```

Brace the SHA (`"${sha}:refs/..."`): zsh reads a bare `"$sha:refs/..."` as a
parameter-expansion modifier and silently mangles it.

Then watch the rebased PR's CI green before merging. Merge the sibling PRs
**one at a time**, rebasing the next only after the previous lands — do not
batch-merge parallel branches without rebasing each against the accumulating
main.

## Prevention

- **Serialize the merges, rebase between each.** After merging PR N, rebase
  PR N+1 onto the new main before merging it.
- **Merge-base equality is the gate.** Make the `git merge-base origin/main
  <branch>` == `git rev-parse origin/main` test the line right before every
  `gh pr merge` of a parallel/worktree-agent branch — same discipline as
  `git log --oneline origin/main..HEAD` before a push. A two-dot `git diff
  --stat` is **not** that gate; it reports every sibling merge as a deletion
  by construction, so it fires on branches that are perfectly fine.
- **Spend `update-branch` where branches actually interact.** A stale base on a
  branch genuinely disjoint from what landed (different directory, no shared
  imports, no shared config) costs a CI re-run to fix and buys little — its
  tests could not have been invalidated by work they never touch. Reserve the
  rebase pass for branches whose files, dependencies, or generated artifacts
  overlap the siblings that merged in the meantime. The old rule flattened this
  into "every later one needs a rebase pass"; it is a judgement, not a law.
- When dispatching the wave, know that only the first-to-merge is trivially
  current; budget for re-basing the interacting remainder.

## Interaction with required status checks

GitHub's "require branches to be up to date before merging" (`strict` on a
required-status-checks ruleset) is the mechanical enforcement of this rule — it
refuses a merge whose base is stale. It is deliberately **off** in
`laurigates/claude-plugins` (`strict_required_status_checks_policy = false`),
because with it on every merge marks every other open PR out-of-date, each
needing an `update-branch` plus a fresh CI run — O(N²) on a repo built around
parallel agent PRs. That trade is taken consciously: **this rule is the
judgement layer that `strict = false` leaves to the human.** Where the setting
is off, the merge-base check above is the only thing standing between a
stale-based green check and a red `main`.

## Rationale

A stale-based merge does not revert anything — it ships **unverified**. The
branch compiled and passed against its own older tree, so the PR looks fully
checked while nothing has ever built the combination that is about to become
`main`. The cost of prevention is one `git merge-base` comparison, and an
`update-branch` plus a CI re-run on the branches that actually interact; the
cost of skipping it is a `main` that goes red on somebody else's PR, where the
cause is several merges back and attributable to none of them.
