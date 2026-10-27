# Merge Shepherd: an Ordered PR List, Merged by a Script

Detail for [the Merge shepherd section of SKILL.md](../SKILL.md#merge-shepherd).
Open it before merging more than one already-verified PR in sequence.

## Why a script, not an agent

The loop is mechanical: update the branch, wait for CI, run the §6 guard, merge
pinned to the head, fetch. Two ad-hoc workflow runs wrote it as agent prose
instead, spending six shepherd agents on 55 PRs across 16 repositories. Each
agent re-derived the loop and the guard from prose, and one run's merge step
omitted `--match-head-commit` entirely. `scripts/merge-chain.sh` runs the
loop the same way every time, and an agent is spent only where judgement is
needed: a conflict or a red check.

## Run it

```bash
REVIEW_TS=2026-10-27T08:00:00Z   # when the last verification of these PRs ended, UTC
bash "${CLAUDE_SKILL_DIR}/scripts/merge-chain.sh" --repo OWNER/REPO --prs 219,220,227 --review-ts "$REVIEW_TS"
```

| Flag | Meaning |
|---|---|
| `--prs` | Merge order. Put a PR that changes a bot which writes to PR branches **last** (§6). |
| `--review-ts` | Required. Any non-merge commit newer than this is unreviewed and stops the PR. |
| `--method` | `squash` by default: `update-branch` adds a merge commit, so the branch squashes. |
| `--timeout` | Per-PR budget for CI to settle, in seconds (default 1800). |
| `--fetch-dir` | A clone to `git fetch origin` after each merge, so a conflict agent starts from current `main`. |

Per PR the script reads state and author, runs `gh pr update-branch`, waits
until every check on the head has completed and two reads agree, reads
`mergeStateStatus` (§4), applies the §6 guard, and merges with
`--match-head-commit` and the **full 40-character** head SHA. GitHub rejects a
short SHA ("Could not coerce value to GitObjectID"). It then reads the state
back and requires `MERGED`.

Several repositories in one sweep: one `merge-chain.sh` invocation per
repository, run as background Bash. Do not dispatch one agent per repository.

## Read the result

Each PR gets an `=== PR <n> ===` section with `STATUS=` and, unless merged,
`REASON=`. The closing `=== MERGE CHAIN ===` section follows the
structured-output contract (`STATUS=OK|WARN|ERROR`, `REASON=`, `ISSUES:`) and
carries `REMAINING=`, the PRs still to merge, with the stopped PR first.

| `STATUS=` | Chain | What to do |
|---|---|---|
| `MERGED` | continues | Nothing. |
| `SKIPPED` | continues | Already merged or closed, a draft, release-please, Renovate, or a non-self non-bot author. A stranger's PR is a review, not a merge: `git-plugin:external-pr-trust`. |
| `CONFLICT` | stops | Dispatch one agent for this PR: [Dispatch only on CONFLICT or CI_RED](#dispatch-only-on-conflict-or-ci_red). |
| `CI_RED` | stops | Dispatch one agent for this PR: [Dispatch only on CONFLICT or CI_RED](#dispatch-only-on-conflict-or-ci_red). `REASON=check_failed: <names>`, `ci_timeout`, `unstable` (§4: merging over red needs both checks), or `still_behind`. |
| `GUARD_LATE_COMMIT` | stops | A commit landed after your review, or the head moved after CI settled. Read the commits it names, and verify or revert them, before resuming. Recovery if any already merged: [serial-merge-chain.md](serial-merge-chain.md). |
| `DENIED` | stops | A 403 or branch protection refused the update or merge. Report it and stop: [Denials](#denials). |
| `ERROR` | stops | Fail-closed: a read failed, a state was unexpected, or a merge error was unclassified. Fix the cause named in `REASON=`. Never treat it as clean. |

## Dispatch only on CONFLICT or CI_RED

1. Dispatch **one** agent, for the stopped PR only. Give it the PR number, the
   `REASON=` line, and the project's conflict rules (a path-scoped rule in that
   repository, if it has one, such as union-merging append-only tables or
   regenerating build output). It brings the branch up to date by merging
   `main` into it and pushes a plain commit: never rebase, amend, or
   force-push. Resolve conflicts with `git-plugin:git-conflicts`; repair a red
   check with `git-plugin:git-fix-pr`.
2. **The resolution is unreviewed code.** Before the chain resumes, route the
   branch through `workflow-orchestration-plugin:workflow-implement-verify`'s
   `repair-round` template, one unit, with a fresh verifier. Its finding names
   the resolution commit. Do not let the script merge an unverified fix. The
   §6 guard would refuse it anyway, because the fix is newer than
   `--review-ts`.
3. Re-run the script with `--prs` set to `REMAINING=` and a new `--review-ts`
   taken when that verification ended.

The other stopping statuses do not get an agent. `GUARD_LATE_COMMIT` needs a
reviewer, and `DENIED` needs the user.

## Denials

If a permission or classifier denial blocks a merge command, do NOT retry it or
route around it. Mark the PR blocked with reason 'permission denied' and report
it. The script never retries a denied merge and never passes `--admin`.

The PreToolUse `external-pr-merge-guard` hook cannot see the PR numbers this
script merges, because they are inside the script. The script therefore applies
the hook's authorship rule itself, failing closed: it merges only PRs authored
by the authenticated user (`gh api user`) or by a bot, and it stops before
touching any PR when that login cannot be read.
