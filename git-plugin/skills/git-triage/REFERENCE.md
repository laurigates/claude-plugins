# git-triage: Reference

Supplementary patterns for `/git:triage`, loaded on demand. The workflow itself
is in [SKILL.md](SKILL.md).

| Reference | Read it when |
|-----------|--------------|
| [references/issue-triage-workflow.md](references/issue-triage-workflow.md) | Adapting the multi-repository issue-triage workflow template |
| [references/pr-categories.md](references/pr-categories.md) | Reading `PR_<n>_CATEGORY` and systematic-failure groups |
| [references/report-template.md](references/report-template.md) | Writing the queue and backlog report |
| [references/guarded-writes.md](references/guarded-writes.md) | Closing issues or merging PRs with `--auto-close` / `--auto-merge` |
| [references/commands.md](references/commands.md) | Compact `gh` commands per category |

## REST fallback

`git-triage.sh` tries GraphQL first (`gh issue list`, `gh pr list`,
`gh api graphql`). When a call fails with the proxy's "GraphQL is not available"
403, which every Claude Code cloud session returns, the rest of the run uses the
REST API (issue #3362):

| Data | REST source |
|------|-------------|
| Issues | `repos/{o}/{r}/issues`, with entries that carry `pull_request` removed |
| PRs | `repos/{o}/{r}/pulls` |
| `MERGEABLE` / `MERGE_STATE` | `pulls/{n}` `mergeable` and `mergeable_state`, upper-cased |
| `REVIEW` | `pulls/{n}/reviews`: `CHANGES_REQUESTED` if any reviewer's latest decisive review requests changes, else `APPROVED` if any approved, else `null`. Approximated, because GraphQL's `reviewDecision` also applies branch protection's required-review rule |
| `WORST_CHECK` | `commits/{sha}/check-runs` (first 100) plus `commits/{sha}/status` |
| `ISSUES_TOTAL` / `PRS_TOTAL` | `search/issues` `total_count` for `is:issue is:open` and `is:pr is:open` |
| `SUBISSUES` | The issue's `sub_issues_summary` |
| `MERGED_PRS` | None cheap: reads `unknown`, so `CLOSE_CANDIDATE` rests on checkboxes and sub-issues |

Lists are walked with an explicit `&per_page=100&page=N` loop that stops on a
short page. `gh api --paginate` is not used: it follows the `Link` header, whose
`repositories/{id}` paths the proxy rejects. The fallback adds
`GRAPHQL_BLOCKED=true`, `REST_FALLBACK_UNKNOWN=MERGED_PRS|none`, and
`REST_FALLBACK_APPROXIMATED=REVIEW|none`; a run where GraphQL answers emits none
of them. Each PR costs four extra REST calls. `GIT_TRIAGE_REST_PER_PAGE`
overrides the page size for tests.

## Per-issue progress keys

`git-triage.sh` emits four progress keys for every fetched issue (issue #2904).
They answer "is this open issue already finished?" without a `gh pr view` per
reference.

| Key | Value | Source |
|-----|-------|--------|
| `ISSUE_<n>_CHECKBOXES` | `<done>/<total>`; `0/0` when the body has no task list | The issue body that `gh issue list` already fetched |
| `ISSUE_<n>_SUBISSUES` | `<completed>/<total>`, or `unknown` | `subIssuesSummary { total completed }` |
| `ISSUE_<n>_MERGED_PRS` | `<owner/repo>#<num>[*],…`, `none`, or `unknown` | `timelineItems` cross-reference and Development-link events |
| `ISSUE_<n>_CLOSE_CANDIDATE` | `true` / `false` | Derived from the three keys in this table |

### Checkbox parsing

A box is a list item (`-`, `*`, `+`, or `1.`/`1)`) whose text starts with
`[ ]`, `[x]`, or `[X]`. Boxes inside a fenced code block (a ```` ``` ```` or
`~~~` fence, closed by a fence of the same character at least as long with
nothing after it, so a ```` ```bash ```` line inside a fence is content) are not
counted, so a body that quotes a checklist template does not read as progress.
Boxes inside HTML comments (`<!-- -->`, typically issue-template boilerplate)
are not counted either. A `[ ]` in running text is not a box.

### The progress query

One GraphQL query, paginated by hand at up to 50 issues per page, stops once it
has covered `--batch` issues. It walks the open issues newest-created first,
which is the order `gh issue list` uses. Per issue it asks for
`subIssuesSummary { total completed }` and the last 100 `timelineItems` of type
`CROSS_REFERENCED_EVENT`, `CONNECTED_EVENT`, and `DISCONNECTED_EVENT`. For each
pull request it reads `number`, `state`, `mergedAt`, and
`repository { nameWithOwner }`, and for a cross-reference it also reads
`willCloseTarget`. The walk is capped at 20 pages (1000 issues); with
`--batch` above 1000, later issues read `SUBISSUES`/`MERGED_PRS=unknown`.

- **Merged only.** A PR is listed when `mergedAt` is set or `state` is
  `MERGED`. Open and closed-unmerged PRs are left out, even when they would
  close the issue.
- **Cross-repo included.** Each entry carries its own `owner/repo`, so a PR in
  another repository that references the issue is listed too.
- **`*` marks a closing link.** That is a cross-reference with
  `willCloseTarget: true` (a closing keyword such as `Closes #N`), or a
  Development-sidebar `ConnectedEvent` that no later `DisconnectedEvent` undid.
- **`unknown`, never zero.** When the query fails, returns errors (for example,
  on a GitHub Enterprise Server without sub-issues), or does not include an
  issue (including one past the 1000-issue cap), that issue's `SUBISSUES` and `MERGED_PRS` read `unknown`. The script
  still exits 0, and `CHECKBOXES` is computed as usual.

Tests feed canned page responses through `GIT_TRIAGE_PROGRESS_FIXTURE` (one or
more GraphQL response objects in one file). `GIT_TRIAGE_NO_FETCH=1` skips the
query.

### Reading `CLOSE_CANDIDATE`

`CLOSE_CANDIDATE=true` when all checkboxes are ticked (with at least one box),
all sub-issues are complete (with at least one sub-issue), or any merged PR
carries `*`. It is a hint to verify, never an auto-close: a ticked checklist can
be out of date, and a closing PR can merge into a non-default branch.

A merged PR **without** `*` does not set it. Such PRs often only reference the
issue, typically because their review filed it as a follow-up. Treat them as
evidence: read what the PR changed before calling the issue `implemented`.

## Bot dependency PRs

### Re-read CI by head SHA after a bot rebase

Renovate and Dependabot rebase by force-pushing. The PR's check list can keep
showing the run from the **pre-rebase** SHA, so a PR reads red (or green) for a
commit that is no longer its head. Before categorizing a bot PR as `needs-fix`,
confirm the run belongs to the current tip:

```bash
gh pr view <n> --repo $REPO --json headRefOid,headRefName --jq '"\(.headRefOid) \(.headRefName)"'
gh run list --repo $REPO --branch <headRefName> --json headSha,workflowName,conclusion,createdAt --jq '.[] | select(.headSha == "<headRefOid>")'
```

If no run exists for the current head SHA, CI has not run on it yet. Trigger it
(for example with an empty commit, if the repo allows pushes to bot branches)
instead of reporting the stale result.

### A pin PR can smuggle a minor bump

With Renovate `rangeStrategy: "pin"` plus `group:allNonMajor`, a
"chore(deps): pin dependencies" PR pins each package to whatever the registry
resolves today. That can be a **newer minor** than `main` currently locks, so a
PR titled as a no-op pin carries a real upgrade.

The tell is the failure mode. A pin PR that fails the frozen-lockfile install
is the lockfile trap described in SKILL.md Step 4. A pin PR that installs
cleanly and then fails type checking or tests has probably pulled in a breaking
minor (observed: a React flow library's 12.10 to 12.11 bump changed a callback's
generic signature).

Split it rather than fixing the upgrade inside the pin PR:

1. In the pin PR, pin the offending package back to the version `main` resolves.
2. Add a `renovate.json` guard that holds it there, referencing a tracking issue:

   ```json
   {
     "packageRules": [
       {
         "matchPackageNames": ["<pkg>"],
         "allowedVersions": "<x.y.z",
         "description": "Hold until #<issue>: <why the upgrade breaks>"
       }
     ]
   }
   ```

3. Open the tracking issue for the upgrade. When the guard is removed, Renovate
   proposes the bump as its own PR, where the breakage can be reviewed on its own.
