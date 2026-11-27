# Merge-Over-Red Triage

Read this before judging a red check on a PR you mean to merge over red
(SKILL.md § 4). Run the steps in order: each one can turn a red check into
"no signal" or "fixed by updating", and the two conditions in § 4 are only
meaningful for the checks that survive.

## 1. Did the job start at all?

```bash
gh api repos/<o>/<r>/actions/jobs/<job-id> --jq '.steps|length'
```

Zero steps means the job never ran, so the check carries no signal about the
diff. Read the annotation for the reason:

```bash
gh api repos/<o>/<r>/check-runs/<job-id>/annotations --jq '.[].message'
```

A billing block reads *"The job was not started because recent account
payments have failed or your spending limit needs to be increased."* or names
an Actions budget. `github-actions-plugin:actions-billing-usage` covers both
wordings. Re-run the job once the block lifts, then judge the new run.

These checks look like real failures in `gh pr checks`, and when `main` ran
before the block they pass there, which points at the diff. In a bulk review
of 57 bot PRs (2026-11-25), 53 failing checks had zero steps.

## 2. Is the PR behind its base?

```bash
gh api repos/<o>/<r>/compare/<default>...<head-branch> --jq .behind_by
```

A PR behind `main` can fail checks that `main` already passes, because it
tests the old base. When `behind_by` is above 0, run `gh pr update-branch <n>`
and judge the fresh run. In the same review, 22 PRs were 1–15 commits behind
and their "Tests (Python)" failures went green after an update.

## 3. Judge each check name by its latest entry

After a re-run, `statusCheckRollup` can still list the earlier attempt's
`FAILURE` or `CANCELLED` entry beside the new `SUCCESS`. Keep the entry with
the latest `completedAt` per name:

```bash
gh pr view <n> --json statusCheckRollup --jq '.statusCheckRollup | group_by(.name // .context) | map(max_by(.completedAt // "")) | .[] | select((.conclusion // .state) != "SUCCESS") | {name: (.name // .context), conclusion: (.conclusion // .state)}'
```

`SKIPPED` and `NEUTRAL` are not failures; filter them out if they appear.

## 4. The two conditions

What remains red goes through SKILL.md § 4: the diff cannot break the check
(`--json files`), **and** the same check already fails on `main` in a recent
run (check `createdAt`).

**Fallback when `main` has no recent run of that workflow.** Re-run `main`'s
latest run and read the job:

```bash
gh run list --workflow <file> --branch <default> -L 1 --json databaseId,event,createdAt
gh run rerun <run-id>
```

Before re-running, grep the workflow file for publish, release or deploy steps
(`grep -nEi 'publish|release|deploy' .github/workflows/<file>`): a re-run of a
push-event run repeats them. In the 2026-11-25 review, a re-run of `main`'s
months-old run showed `cargo audit` failing on `main` too, which put the
failure on a newly published advisory rather than the PR.
