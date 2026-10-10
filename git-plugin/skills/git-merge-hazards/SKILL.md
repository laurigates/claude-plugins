---
name: git-merge-hazards
description: Traps in GitHub's merge machinery. Use when merging a PR, merging a stacked or serial PR chain, auditing whether a branch really landed, or merging over red CI.
allowed-tools: Read, Grep, Glob, Bash(gh pr *), Bash(gh issue *), Bash(gh api *), Bash(git cherry *), Bash(git merge-tree *), Bash(git rev-parse *), Bash(git log *), Bash(git reflog *), Bash(git rebase *), Bash(git push *), Bash(git fetch *), Bash(just *), Bash(bash *), TodoWrite
created: 2026-08-19
modified: 2026-10-09
reviewed: 2026-08-21
---

# Git Merge Hazards

## When to Use This Skill

| Use this skill when... | Use something else when... |
|---|---|
| Merging a PR, or proving a branch landed | The PR's green CI ran against an older `main` → `git-plugin:worktree-stale-base-merge` |
| Deciding whether a red PR can merge (§4) | Deciding whether a red AI-review check is a real finding → `github-actions-plugin:ai-review-max-turns` |
| Merging an ad-hoc stacked chain (§2, §3) | Release-please PRs are piling up or conflicting → `git-plugin:release-please-pr-workflow` |

The numbered sections are the verbatim text of the promoted
`~/.claude/rules/pr-merge-hazards.md` rule.

Notes that are *not* part of that body:

- The `## Agentic Optimizations` table is this skill's own command index;
  leave it out when syncing with `pr-merge-hazards.md`.
- §3 and §5's follow-on subsections moved verbatim into `references/`; they
  are still rule text when syncing.
- §6 and §4's merge-endpoint pointer are skill-only, not in `pr-merge-hazards.md`.

- Two gates — §1's merged-ness authority order and §4 (minus its skill-only
  merge-endpoint pointer) — are also reproduced verbatim in the `pr-merge-hazards.md` stub, because they are
  read *while* the decision is being made. Edit both copies together.
- §1 overlaps `git-plugin:deadbranch` Step 1.5, which carries the same three
  signals scoped to branch cleanup.
- §2 and §3 describe **ad-hoc** chains — PRs whose base is another PR's branch.
  A stack **registered with GitHub** (`gh stack`) retargets its upper PRs
  itself on merge, so the auto-close hazard and the manual retarget/rebase
  ordering do not apply there. See `git-plugin:git-stacked-prs`.
- The two encoded recipes cited in §1 and §2 are the author's own (a
  `just -g` recipe in `laurigates/dotfiles`, and a sweep script in
  `laurigates/claude-plugins`), not commands a plugin consumer already has.
  Read the authority ladder in §1 as the instruction; the recipe is a
  convenience, and its REVIEW bucket measured ~90% false positives (#2268).

Six traps in GitHub's merge machinery, one law: "PR merged" says nothing about
*content* — and a red check is not proof of failure. Each: the trap, the
5-second check, the fix. Sibling: `git-plugin:git-local-hazards` (local git).

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

Read [references/stacked-chain-push.md](references/stacked-chain-push.md) before any force-push or merge in a stacked-PR chain. It carries the push-by-SHA refspec form (braced variable, full `refs/heads/` refname, the zsh word-modifier table), the empty-diff auto-close, the mergeability and CI-registration races, the pre-push check, and auto-close recovery.

## 4. A red PR may still be mergeable — `UNSTABLE` is not `BLOCKED`

`mergeStateStatus` separates **required** failing checks (`BLOCKED` — merge
refused) from merely-present ones (`UNSTABLE` — plain `gh pr merge` works), so
`--admin` on an `UNSTABLE` PR takes a privilege you didn't need. Read it first.

Merging over red needs **two** checks: `--json files` (config/docs can't break
a compile) **and** the same check already failing on `main`. Either alone is a
guess — and a stale-green `main` lies, so check `createdAt` (2026-07: a "green"
run was 21 days old; main hadn't compiled for three weeks).

A `500` from the merge call may be GitHub, not the PR: run the stale-SHA control in
[references/merge-endpoint-failures.md](references/merge-endpoint-failures.md) before changing the PR.

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

The trap is wider than negation: plain past tense, a markdown-linked cross-repo reference, and a keyword you are only *quoting* all match too. Before merging a PR whose body mentions issue numbers, read [references/closing-keyword-cases.md](references/closing-keyword-cases.md) for those cases, the audit-with-a-control procedure, and the incidents.

## 6. A serial merge chain merges commits nobody verified

`gh pr update-branch` re-runs every `pull_request` workflow, so a bot that
writes to PR branches can push after your review; its commits pass CI and merge
unread. Before each merge, refuse any non-merge commit newer than your review
timestamp, and merge with `--match-head-commit <sha>`. A PR that changes such a
bot goes last in the chain. Guard snippet, the `gh --jq --arg` trap and
recovery: [references/serial-merge-chain.md](references/serial-merge-chain.md).

## Agentic Optimizations

| Context | Command |
|---|---|
| Did the branch land? (§1, authoritative) | `gh pr list --state all --head <branch> --json number,state,mergedAt` |
| Can a red PR merge? (§4) | `gh pr view <n> --json mergeStateStatus,mergeable` — `UNSTABLE` merges, `BLOCKED` refuses |
| Merge-over-red evidence (§4) | `gh pr view <n> --json files --jq '.files[].path'` and `gh run list --branch main --workflow <wf> -L 1 --json conclusion,createdAt` |
| Before a force-push (§3) | `git log --oneline origin/main..<sha>` — exactly the child's commits |
| Who closed an issue (§5) | `gh issue view <n> --json closedByPullRequestsReferences,closedAt` |
| Commits a PR gained after review (§6) | `gh pr view <n> --json commits`, filtered with `jq --arg` on `committedDate` |
