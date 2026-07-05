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
| **Automatic** | `check-branch-sync-on-push.sh` PreToolUse hook — nudges (`permissionDecision: "ask"`, never a hard deny) before `git commit`/`git push` when behind or PR merged/closed; cached per session+branch with a TTL | Mid-session, before the mutating command |
| **Resume** | `git-drift-probe.sh` SessionStart probe → consolidated `drift-aggregator` nudge | At session start / resume |

Opt out of the hook with `CLAUDE_HOOKS_DISABLE_BRANCH_SYNC=1`; tune its TTL with
`CLAUDE_HOOKS_BRANCH_SYNC_TTL` (seconds, default 300).

## Verdict vocabulary

`/git:pr-sync-check` (and the probe/hook) speak one shared vocabulary:

| Verdict | Action |
|---------|--------|
| `in_sync` | Proceed |
| `behind` | Reconcile (`git pull --rebase`) before adding commits |
| `pr_merged` | Branch off the updated default; do **not** add commits to the merged branch |
| `pr_closed` | Confirm the branch is still where the work belongs |
| `changes_requested` | Address review via `/git:pr-feedback` first |
| `no_pr` / `no_remote` | Nothing to guard against; proceed |

## Field-name discipline

PR state is read from the `state` enum (`MERGED`/`OPEN`/`CLOSED`) and `mergedAt`
timestamp — **never** a `merged` field (`.claude/rules/gh-json-fields.md`). CI
status comes from `statusCheckRollup`. All `gh`/`git` queries use `--json` + `jq`
and exit 0 on empty input so they stay parallel-safe
(`.claude/rules/parallel-safe-queries.md`).

## Watching instead of polling

To *react* to reviews/CI as they arrive (rather than checking before each build),
`/git:pr-watch` wraps the native `subscribe_pr_activity` MCP tool and delegates
reactions to `/git:pr-feedback` (threads) and `/git:fix-pr` (CI). Subscription is
primarily a remote/web capability (`.claude/rules/sandbox-guidance.md`).

## Related

- `.claude/rules/agent-coworker-detection.md` — local-checkout sibling (uncommitted-file collisions)
- `.claude/rules/gh-json-fields.md` — `state`/`mergedAt`/`statusCheckRollup`, the `merged`-field trap
- `.claude/rules/parallel-safe-queries.md` — `--json` + `jq`, exit-0-on-empty
- `.claude/rules/structured-script-output.md` — the `=== … ===` / `STATUS=` / `VERDICT=` block the script emits
- `git-plugin:git-pr-feedback` — the react-to-review-threads engine
