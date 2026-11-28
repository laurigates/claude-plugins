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
| `--review-ts` | Required. Any commit newer than this is unreviewed and stops the PR, except a merge commit GitHub made through `update-branch`: two or more parents **and** committer `noreply@github.com`. The subject line does not count, and a merge commit anyone else pushed is unreviewed like any other commit. |
| `--method` | Overrides the method for every PR. Without it, each PR takes the `METHOD=` that `git-plugin/scripts/pr-merge-method.py` prints after `update-branch`: a branch that gained a merge commit squashes, and one that needed no update follows the rest of the rule table. |
| `--timeout` | Per-PR budget for CI to settle, in seconds (default 1800). |
| `--fetch-dir` | A clone to `git fetch origin` after each merge, so a conflict agent starts from current `main`. |

Per PR the script reads state and author, runs `gh pr update-branch`, waits
for the head to move off the pre-update head (unless gh reported the branch
already up-to-date), waits until every check on the head has completed and two reads agree, reads
`mergeStateStatus` (§4), applies the §6 guard (no late commit other than
GitHub's own update-branch merges, and the head unchanged since CI settled), resolves the merge method, and merges
with `--match-head-commit` and the **full 40-character** head SHA. GitHub rejects a
short SHA ("Could not coerce value to GitObjectID"). It then reads the state
back and requires `MERGED`.

Several repositories in one sweep: one `merge-chain.sh` invocation per
repository, run as background Bash. Do not dispatch one agent per repository.

## No `gh` (cloud session)

In a Claude Code cloud session the GitHub proxy refuses GraphQL and passes
REST. `gh pr view`, `gh pr update-branch`, `gh pr merge` and the §6 guard's
commit query all use GraphQL, so the script cannot run there. It probes once
before touching any PR and stops with `STATUS=ERROR`, `TYPE=CLOUD_RESTRICTED`
and every PR in `REMAINING=`. Re-running does not help; `session-survey.sh`
reports the same condition as `GH_FAIL_REASON=cloud-restricted`.

Merge the list through the GitHub MCP tools instead, one PR at a time in
`--prs` order (laurigates/comfyui-nodes, 2026-11-20: 10 PRs, each landing about
a minute after its required check finished):

1. Read the head SHA (`mcp__github__pull_request_read`, or REST
   `gh api repos/OWNER/REPO/pulls/N --jq .head.sha`).
2. `mcp__github__update_pull_request_branch` with `expectedHeadSha` set to that
   SHA, so a push since the read is refused instead of merged.
3. `mcp__github__enable_pr_auto_merge` with `mergeMethod` from
   `pr-merge-method.py`'s rule table. The tool does nothing when the PR is
   already mergeable (clean status); merge that PR with
   `mcp__github__merge_pull_request` instead.
4. Block until it lands: poll `git ls-remote origin refs/heads/main` every 10 s
   until the SHA changes from the previous merge's. There is no `gh pr checks`
   or `gh run watch` to block on, and polling `pull_request_read` adds every
   response to the context.

Gaps against `merge-chain.sh` (from that one run; unverified whether they
bite in practice):

| Gap | Effect | Partial cover |
|---|---|---|
| No §6 guard | Nothing checks for a commit pushed after review before auto-merge fires | The §6 REST commit read in the code block after this table, run before step 3. A push after that read still lands |
| A red required check | Auto-merge keeps waiting; the `ls-remote` wait times out without naming the check | The REST check-run read in the code block after this table, run on timeout |
| Update adds a merge commit | A multi-commit PR that would rebase becomes merge-synced, so the rule table squashes it | None needed: squash is the rule table's answer for a merge-synced branch. Choose `mergeMethod` after step 2, not before |

Both reads go through REST, which the proxy passes. The §6 read must print
nothing; it applies the script's exemption (two or more parents and committer
`noreply@github.com`). The check-run read also lists runs a newer run of the
same check superseded; only the latest run per name counts:

```bash
gh api 'repos/OWNER/REPO/pulls/N/commits?per_page=100' --jq '.[] | select(.commit.committer.date > "REVIEW_TS") | select((.parents | length) < 2 or .commit.committer.email != "noreply@github.com") | "\(.sha[0:8]) \(.commit.message | split("\n")[0])"'
gh api 'repos/OWNER/REPO/commits/HEAD_SHA/check-runs?per_page=100' --jq '.check_runs[] | select(.status == "completed" and (.conclusion as $c | ["success", "neutral", "skipped"] | index($c) | not)) | .name'
```

## Read the result

Each PR gets an `=== PR <n> ===` section with `STATUS=` and, unless this
script merged it, `REASON=`. The closing `=== MERGE CHAIN ===` section follows the
structured-output contract (`STATUS=OK|WARN|ERROR`, `REASON=`, `ISSUES:`) and
carries `REMAINING=`, the PRs still to merge, with the stopped PR first.

| `STATUS=` | Chain | What to do |
|---|---|---|
| `MERGED` | continues | Nothing. `REASON=auto-merge: …` means the PR had auto-merge enabled and GitHub merged it during the CI wait, so the §6 guard never ran on it; read its commits if a branch-writing bot could have pushed after your review. A PR merged during the wait **without** auto-merge is `SKIPPED` (`already_merged`). |
| `SKIPPED` | continues | Already merged or closed, a draft, release-please, Renovate, or a non-self non-bot author. A release-please PR merges via `git-plugin:release-please-pr-workflow`. A stranger's PR is a review, not a merge: `git-plugin:external-pr-trust`. `REASON=base_is_upstream_pr_head` means `--repo` is a fork and the PR's base is the head of the open upstream PR it names, so merging would push into that PR: [fork-upstream-base.md](fork-upstream-base.md). |
| `CONFLICT` | stops | Dispatch one agent for this PR: [Dispatch only on CONFLICT or CI_RED](#dispatch-only-on-conflict-or-ci_red). |
| `CI_RED` | stops | Dispatch one agent for this PR: [Dispatch only on CONFLICT or CI_RED](#dispatch-only-on-conflict-or-ci_red). `REASON=check_failed: <names>`, `ci_timeout`, `unstable` (§4: merging over red needs both checks), or `still_behind`. |
| `GUARD_LATE_COMMIT` | stops | A commit landed after your review, or the head moved after CI settled. Read the commits it names, and verify or revert them, before resuming. Recovery if any already merged: [serial-merge-chain.md](serial-merge-chain.md). |
| `DENIED` | stops | A 403 or branch protection refused the update or merge. Report it and stop: [Denials](#denials). |
| `ERROR` | stops | Fail-closed: a read failed, a state was unexpected, or a merge error was unclassified. Fix the cause named in `REASON=`. Never treat it as clean. `head_not_updated` means `update-branch` reported an update but the head never moved within `--timeout`; check the PR's head on GitHub before re-running. |

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
   §6 guard refuses it on a re-run with the old `--review-ts`: the agent's
   merge of `main` is a two-parent commit, but its committer is the agent, not
   GitHub, so it is not exempt. That stop is the backstop, not the review.
3. Re-run the script with `--prs` set to `REMAINING=` and a new `--review-ts`
   taken when that verification ended.

The other stopping statuses do not get an agent. `GUARD_LATE_COMMIT` needs a
reviewer, and `DENIED` needs the user.

## Denials

The rule, verbatim from the workflow runs this script replaces:

> If a permission or classifier denial blocks a merge command, do NOT retry it
> or route around it. Mark the PR blocked with reason 'permission denied', and
> still prepare the PRs after it (refresh, CI) as far as possible without
> merging them.

The script keeps the first half: it never retries a denied merge and never
passes `--admin`. It does not prepare the later PRs. A denial stops the chain
like every other stopping status, because a later PR may depend on the denied
one, and `REMAINING=` lists them so a re-run can pick them up once the denial
is resolved.

The PreToolUse `external-pr-merge-guard` hook reads `--repo` and `--prs` from
the command and checks every listed PR's author before the script runs, so pass
the numbers as literals; a list it cannot read is denied. Spell the script path
as an absolute path, `~/…`, `$HOME/…` or `"${CLAUDE_SKILL_DIR}/…"`; the hook
expands no other unquoted variable, so `$S/merge-chain.sh` is denied. The script repeats the
check inside as a second layer, failing closed: it merges only PRs authored by
the authenticated user (`gh api user`) or by a bot, skips a PR whose author
login cannot be read, and stops before touching any PR when its own login
cannot be read. The
`check-pr-merge-method` hook is blind to it for the same reason, so the script
asks `pr-merge-method.py` for the method itself unless `--method` is passed.
