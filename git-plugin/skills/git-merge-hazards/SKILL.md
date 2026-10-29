---
name: git-merge-hazards
description: Traps in GitHub's merge machinery. Use when merging a PR, merging a stacked or serial PR chain, auditing whether a branch really landed, or merging over red CI.
allowed-tools: Read, Grep, Glob, Bash(gh pr *), Bash(gh issue *), Bash(gh api *), Bash(git cherry *), Bash(git merge-tree *), Bash(git rev-parse *), Bash(git rev-list *), Bash(git log *), Bash(git reflog *), Bash(git rebase *), Bash(git merge *), Bash(git checkout *), Bash(git worktree *), Bash(git diff *), Bash(git add *), Bash(git commit *), Bash(git -C *), Bash(git merge-base *), Bash(grep *), Bash(awk *), Bash(jq *), Bash(git push *), Bash(git fetch *), Bash(git cat-file *), Bash(sleep *), Bash(just *), Bash(bash *), TodoWrite
created: 2026-08-19
modified: 2026-10-28
reviewed: 2026-08-21
---

# Git Merge Hazards

## When to Use This Skill

| Use this skill when... | Use something else when... |
|---|---|
| Merging a PR, or proving a branch landed | The PR's green CI ran against an older `main` → `git-plugin:worktree-stale-base-merge` |
| Deciding whether a red PR can merge (§4) | Deciding whether a red AI-review check is a real finding → `github-actions-plugin:ai-review-max-turns` |
| Merging an ad-hoc stacked chain (§2, §3) | Release-please PRs are piling up or conflicting → `git-plugin:release-please-pr-workflow` |

The numbered sections mirror the `~/.claude/rules/pr-merge-hazards.md` rule;
differences: [references/sync-notes.md](references/sync-notes.md).

Six traps in GitHub's merge machinery, one law: "PR merged" says nothing about
*content* — and a red check is not proof of failure. Sibling: `git-plugin:git-local-hazards` (local git).

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
  Its REVIEW bucket measured ~90% false positives (#2268), so a REVIEW line is a
  question to settle with `gh pr list --state all --head <branch>`, not a verdict.
- A non-match is "review", **not** proof of unmerged — don't force the count to zero.

## 2. Merging a stacked base auto-CLOSES the child PR

When PR B is based on PR A's branch, merging A and deleting its branch
auto-closes B (GitHub does **not** retarget it), and a closed PR whose base
branch is gone **cannot be reopened**.

- **Check the base first** (skill-only): `gh pr view <base> --json state,mergeStateStatus,mergeable` before retargeting. Proceed only when `state` is `OPEN` and `mergeable` is `MERGEABLE`; the `mergeStateStatus` values and the `UNKNOWN` wait are in [references/no-force-push-stack.md](references/no-force-push-stack.md#check-the-base-first).
- **Fix — order matters**: retarget the child **first**, while the base PR is open:
  1. `gh pr edit <child> --base main`
  2. `gh pr merge <base> --<method> --delete-branch` (method: `pr-merge-method.py`)
  3. `git rebase --onto origin/main <old-base-tip> <child-branch>` (drops the
     base's commits) + `git push --force-with-lease`
  4. merge the child.
- **No-force alternative (skill-only, preferred when the child builds only on its base)**: merge `main` into the child with no force-push, after a classification that decides whether `-X ours` is lossless. Recipe: [references/no-force-push-stack.md](references/no-force-push-stack.md). The rebase path in the Fix steps is the fallback.
- **Delta-apply (skill-only)** when the child forked from an older base head, or an independent PR shares its files: [references/delta-apply-stack.md](references/delta-apply-stack.md).
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

`gh pr update-branch` and a retarget (`gh pr edit --base`) re-run
`pull_request` workflows, so a branch-writing bot's post-review commits merge
unread. Before each merge, refuse any post-review commit but GitHub's
update-branch merge (2+ parents, committer `noreply@github.com`); your own
`main` merge holds an unreviewed resolution. Pin `--match-head-commit <sha>`; a
PR changing that bot goes last. See [references/serial-merge-chain.md](references/serial-merge-chain.md).

## Merge shepherd

For an ordered PR list run `scripts/merge-chain.sh`. Dispatch one agent only on
`STATUS=CONFLICT`/`CI_RED`; its fix is unreviewed code, so route it through
`workflow-orchestration-plugin:workflow-implement-verify`'s `repair-round`
before resuming: [references/merge-shepherd.md](references/merge-shepherd.md).

## Agentic Optimizations

| Context | Command |
|---|---|
| Did the branch land? (§1, authoritative) | `gh pr list --state all --head <branch> --json number,state,mergedAt` |
| Can a red PR merge? (§4) | `gh pr view <n> --json mergeStateStatus,mergeable` — `UNSTABLE` merges, `BLOCKED` refuses |
| Merge-over-red evidence (§4) | `gh pr view <n> --json files --jq '.files[].path'` and `gh run list --branch main --workflow <wf> -L 1 --json conclusion,createdAt` |
| Before a force-push (§3) | `git log --oneline origin/main..<sha>` — exactly the child's commits |
| Who closed an issue (§5) | `gh issue view <n> --json closedByPullRequestsReferences,closedAt` |
