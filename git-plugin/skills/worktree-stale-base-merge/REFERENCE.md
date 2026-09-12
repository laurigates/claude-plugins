# Worktree Stale Base Merge - Reference

Background for the stale-base check: the superseded diagnostic this rule
replaced, the two opposite readings of `git merge-tree`, and how the rule
relates to GitHub's strict required-status-checks setting.

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
