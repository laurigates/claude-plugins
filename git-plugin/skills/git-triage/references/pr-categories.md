# PR Categories and Systematic Failures

Moved verbatim from `SKILL.md` Step 4. Read when interpreting `PR_<n>_CATEGORY`, an `uncategorized` PR, or `SYSTEMATIC_FAILURE_*` groups.

### Step 4: Read each PR's category (skip if `--type issues`)

The script already categorized every PR in Step 1 — read `PR_<n>_CATEGORY`
straight from its output. The category is a **pure first-match** over the enum
fields (the script owns this deterministic table, top to bottom):

| Category | Criteria |
|----------|----------|
| `draft` | `isDraft` is true |
| `needs-fix` | Any check in `statusCheckRollup` has `conclusion: FAILURE` |
| `needs-rebase` | `mergeStateStatus` in `BEHIND`, `DIRTY`; OR `mergeable` is `CONFLICTING` |
| `changes-requested` | `reviewDecision` is `CHANGES_REQUESTED` |
| `ready-to-merge` | `mergeable: MERGEABLE` AND `mergeStateStatus` in `CLEAN`/`HAS_HOOKS`/`UNSTABLE` AND `reviewDecision: APPROVED` AND not draft |
| `awaiting-review` | `reviewDecision` is `REVIEW_REQUIRED` or null AND no failing check |
| `stale` | `age > --days-stale-pr` AND none of the above trigger |

If a PR comes back as `uncategorized` (e.g. `mergeStateStatus`/`mergeable`
both `UNKNOWN`), trigger a fresh view and re-run the script, or inspect:
```bash
gh pr view <n> --repo $REPO --json mergeable,mergeStateStatus
```

**Systematic failures.** When ≥2 bot-authored `needs-fix` PRs share an
identical failing-check signature, the script groups them under
`SYSTEMATIC_FAILURE_<k>_SIGNATURE` (the sorted `|`-joined failed check names)
and `SYSTEMATIC_FAILURE_<k>_PRS` (the PR list); `SYSTEMATIC_FAILURE_COUNT`
holds the number of groups. These almost always have **one** shared root
cause — e.g. Dependabot can't update `bun.lock`, so every npm-bump PR fails
the `bun install --frozen-lockfile` step *before* lint/typecheck/tests run, and
"Lint FAILURE / Type Check FAILURE" is misleading (nothing was linted). For
each group, read the install step's log once before assuming code defects:
```bash
gh pr checks <n> --repo $REPO --json name,state,conclusion,detailsUrl
gh run view <run-id> --repo $REPO --log-failed
```
Diagnose the shared cause once and present a single grouped row (Step 6) /
blocker (Step 8) instead of N independent `needs-fix` PRs.

For bot PRs whose checks may belong to a pre-rebase SHA, and for pin PRs that
smuggle a minor bump, see [REFERENCE.md](../REFERENCE.md).
