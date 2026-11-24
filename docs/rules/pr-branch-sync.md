# PR-Branch Sync: hook mechanics and related paths

The always-loaded rule [`.claude/rules/pr-branch-sync.md`](../../.claude/rules/pr-branch-sync.md)
keeps the drifts, the guard trio and the verdict table. This page holds how
`check-branch-sync-on-push.sh` decides `behind` after a rebase, which branch it
evaluates, the field-name discipline and the watch path, moved here verbatim on
2026-11-24 so they no longer load on every turn.

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
