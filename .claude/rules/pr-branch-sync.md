---
created: 2026-06-18
modified: 2026-06-18
reviewed: 2026-07-04
---

# PR-Branch Sync

Before building **further** on a branch that already has a PR — especially on an
*additional in-session request* that seems related to earlier work — confirm the
branch is still **live and in sync** with the remote. The failure this prevents:
a multi-request session keeps committing onto a PR branch after that branch's
reality changed underneath it.

This is the *remote* sibling of `agent-coworker-detection.md` (which covers
*local-checkout* coworker collisions on uncommitted files). That rule asks "is
another agent editing my working tree?"; this one asks "did the branch I'm
building on merge or drift on the remote?".

## The three drifts

| Drift | What happened | Symptom if unguarded |
|-------|---------------|----------------------|
| **Stale PR branch** | An earlier request opened a PR; it merged; a later request keeps committing here | New work never reaches a PR — it sits on a merged dead-end branch |
| **Branch drift** | A teammate, another agent, or a CI auto-fix pushed to the branch since last sync | Rejected push, or a needless conflict, because the local tip is behind `origin/<branch>` |
| **Unseen reviews** | Review comments / `CHANGES_REQUESTED` landed | Unrelated work piles on top of unaddressed feedback |

## The guard trio (all in `git-plugin`)

| Layer | Mechanism | Fires |
|-------|-----------|-------|
| **Advisory** | `/git:pr-sync-check` skill — read-only, fetches, emits a `VERDICT` | On demand / as a precondition before building on a PR branch |
| **Automatic** | `check-branch-sync-on-push.sh` PreToolUse hook — nudges (`permissionDecision: "ask"`, never a hard deny) before `git commit`/`git push` when behind or PR merged/closed; reads the push **refspec destination** rather than HEAD, and does not treat a lease-pinned force-push as `behind` (below); cached per session+branch with a TTL | Mid-session, before the mutating command |
| **Resume** | `git-drift-probe.sh` SessionStart probe → consolidated `drift-aggregator` nudge | At session start / resume |

Opt out of the hook with `CLAUDE_HOOKS_DISABLE_BRANCH_SYNC=1`; tune its TTL with
`CLAUDE_HOOKS_BRANCH_SYNC_TTL` (seconds, default 300).

## Verdict vocabulary

`/git:pr-sync-check` (and the probe/hook) speak one shared vocabulary:

| Verdict | Action |
|---------|--------|
| `in_sync` | Proceed |
| `behind` | Reconcile (`git pull --rebase`) before adding commits — **except** after a rebase, where the remote commits are your own rewritten history (below) |
| `pr_merged` | Branch off the updated default; do **not** add commits to the merged branch |
| `pr_closed` | Confirm the branch is still where the work belongs |
| `changes_requested` | Summarise the outstanding threads and recommend the user run `/git:pr-feedback` (it is `disable-model-invocation`, so the model cannot reach it) before piling on unrelated work |
| `no_pr` / `no_remote` | Nothing to guard against; proceed |

## `behind` after a rebase is not a coworker push (#2672)

A rebase makes the remote tip unreachable from the local tip by construction:
the branch's own pre-rebase commit was rewritten, and any base commits that were
squash-merged upstream are dropped. `rev-list --count <local>..origin/<branch>`
then reports a positive **behind** count even though nobody else pushed — and
`git pull --rebase` would *re-introduce* the commits the rebase removed. Two
rules keep the hook honest here:

| Situation | Hook behaviour |
|-----------|----------------|
| `--force-with-lease=<branch>:<sha>` where `<sha>` is the freshly-fetched `origin/<branch>` tip | **Silent.** The lease itself refuses the push if anyone pushed in between, so the behind-count is provably your own history. |
| Any other force-push (`--force`, bare `--force-with-lease`, a stale lease SHA) | Nudges, but worded "N remote commit(s) … are not in the commit you are pushing (expected after a rebase)" — no "someone pushed" claim, no `git pull --rebase` advice. |
| Plain `git push` / `git commit` while behind | Unchanged: "someone (a teammate, another agent, or a CI auto-fix) pushed … Reconcile first (git pull --rebase)". |

A **bare** `--force-with-lease` deliberately does *not* suppress: it leases
against the remote-tracking ref that the hook's own `git fetch` has just
advanced, so a coworker's push would be laundered into the lease. Only the
explicit `<ref>:<sha>` form is self-verifying.

The same issue fixed the branch the hook evaluates: for a push it now resolves
the **refspec destination** (`<sha>:refs/heads/<other>`), not `symbolic-ref
HEAD`. The push-by-SHA protocol in `git-plugin:git-merge-hazards` §3 writes a
branch other than the checked-out one, and a HEAD-based read either compared the
wrong branch or (from `main`) skipped the check entirely.

The hook sees the command as **written**, not as the shell expands it, so the
refspec destination is adopted only when it is an unambiguous, literal branch
name. A multi-refspec push (`git push origin main feature`) or a destination
still carrying a shell metacharacter (`git push -u origin $(git branch
--show-current)` — this plugin's own documented push idiom, which arrives as the
token `$(git`) falls back to HEAD. Adopting such a token verbatim would silence
the guard entirely: there is no ref to fetch, no `origin/<token>` so the behind
count is 0, and no PR to look up.

## Field-name discipline

PR state is read from the `state` enum (`MERGED`/`OPEN`/`CLOSED`) and `mergedAt`
timestamp — **never** a `merged` field (`.claude/rules/gh-json-fields.md`). CI
status comes from `statusCheckRollup`. All `gh`/`git` queries use `--json` + `jq`
and exit 0 on empty input so they stay parallel-safe
(`.claude/rules/parallel-safe-queries.md`).

## Watching instead of polling

To *react* to reviews/CI as they arrive (rather than checking before each build),
`/git:pr-watch` wraps the native `subscribe_pr_activity` MCP tool. The two
branches are **not** symmetric: CI failures are fixed via `/git:fix-pr`, which
the model can invoke; review threads are summarised and handed to the user with
a recommendation to run `/git:pr-feedback`, which carries
`disable-model-invocation: true` and is therefore unreachable from the model
(#2442). Subscription is primarily a remote/web capability
(`.claude/rules/sandbox-guidance.md`).

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
- `.claude/rules/structured-script-output.md` — the `=== … ===` / `STATUS=` / `VERDICT=` block the script emits
- `git-plugin:git-pr-feedback` — the react-to-review-threads engine
