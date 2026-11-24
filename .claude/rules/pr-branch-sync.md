---
created: 2026-06-18
modified: 2026-11-24
reviewed: 2026-07-04
---

# PR-Branch Sync

Before building **further** on a branch that already has a PR — especially on an
*additional in-session request* that seems related to earlier work — confirm the
branch is still **live and in sync** with the remote. The failure this prevents:
a multi-request session keeps committing onto a PR branch after that branch's
reality changed underneath it.

Unscoped on purpose: the hazard fires on `git commit`/`git push`, which no
`paths:` glob can see. This is the *remote* sibling of
`agent-coworker-detection.md`: that rule asks "is another agent editing my
working tree?"; this one asks "did the branch I'm building on merge or drift?".

## The three drifts

| Drift | What happened | Symptom if unguarded |
|-------|---------------|----------------------|
| **Stale PR branch** | An earlier request opened a PR; it merged; a later request keeps committing here | New work never reaches a PR |
| **Branch drift** | A teammate, another agent, or a CI auto-fix pushed since last sync | Rejected push, or a needless conflict |
| **Unseen reviews** | Review comments / `CHANGES_REQUESTED` landed | Unrelated work piles on top of unaddressed feedback |

## The guard trio (all in `git-plugin`)

| Layer | Mechanism | Fires |
|-------|-----------|-------|
| **Advisory** | `/git:pr-sync-check` skill — read-only, fetches, emits a `VERDICT` | Before building on a PR branch |
| **Automatic** | `check-branch-sync-on-push.sh` PreToolUse hook — nudges (`ask`, never a hard deny) before `git commit`/`git push` when behind or the PR merged/closed | Before the mutating command |
| **Resume** | `git-drift-probe.sh` SessionStart probe → `drift-aggregator` nudge | Session start / resume |

Opt out of the hook with `CLAUDE_HOOKS_DISABLE_BRANCH_SYNC=1`; tune its TTL with
`CLAUDE_HOOKS_BRANCH_SYNC_TTL` (seconds, default 300).

## Verdict vocabulary

| Verdict | Action |
|---------|--------|
| `in_sync` | Proceed |
| `behind` | Reconcile (`git pull --rebase`) before adding commits — **except** after a rebase, where the remote commits are your own rewritten history and a pull would re-introduce them |
| `pr_merged` | Branch off the updated default; do **not** add commits to the merged branch |
| `pr_closed` | Confirm the branch is still where the work belongs |
| `changes_requested` | Summarise the outstanding threads and recommend the user run `/git:pr-feedback` (it is `disable-model-invocation`, so the model cannot reach it) |
| `no_pr` / `no_remote` | Nothing to guard against; proceed |

A `--force-with-lease=<branch>:<sha>` push against the freshly-fetched tip
silences the hook's `behind` nudge; a bare `--force-with-lease` does not (#2672).
The hook mechanics (refspec-destination parsing, the lease rule), the field-name
discipline and the `/git:pr-watch` subscription path are in
[`docs/rules/pr-branch-sync.md`](../../docs/rules/pr-branch-sync.md).

## Gated siblings are recommended, never delegated to

Seven `git-plugin` skills carry `disable-model-invocation: true` (`git-api-pr`,
`git-commit-push-pr`, `git-derive-docs`, `git-issue`, `git-maintain`,
`git-pr-feedback`, `git-upstream-pr`). A catalog-present skill that tells the
agent to "address it via `/git:pr-feedback`" fails **silently** — the delegation
is prose, so there is no tool call to refuse. Write the recommendation form
instead ("summarise the thread and recommend the user run `/git:pr-feedback`");
`scripts/check-delegation-reachability.sh` is the guard, and since #2483 it
audits every marketplace skill rather than only `git-plugin`.

## Related

- `.claude/rules/agent-coworker-detection.md` — local-checkout sibling (uncommitted-file collisions)
- `.claude/rules/gh-json-fields.md` — `state`/`mergedAt`/`statusCheckRollup`, the `merged`-field trap
- `.claude/rules/parallel-safe-queries.md` — `--json` + `jq`, exit-0-on-empty
- `git-plugin:git-pr-sync-check` — the advisory check and its `VERDICT` block
