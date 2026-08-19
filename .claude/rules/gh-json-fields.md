---
created: 2026-05-11
modified: 2026-07-29
reviewed: 2026-07-29
---

# `gh --json` Field Names

An invalid `--json` field name exits 1 at *runtime* and dumps the full available
field list — so don't guess: read that list, or `gh pr help json-fields` /
`gh <cmd> --help`. Common field sets per command: `git-plugin:gh-cli-agentic`.

## The `merged` mistake

The single most-common mistake is asking for a field called `merged`:

```
# Wrong — there is no `merged` field on the PR JSON object
gh pr view 42 --json number,merged --jq '.merged'
# → Exit 1: Unknown JSON field: "merged"

# Right
gh pr view 42 --json state --jq '.state == "MERGED"'
```

PR merge state lives on the `state` field (a string enum) or the
`mergedAt` field (an ISO 8601 timestamp, or `null` when not merged).

## PR state reference

| Want to know | Correct field | Value when merged | Value when open | Value when closed-without-merge |
|---|---|---|---|---|
| State enum | `state` | `"MERGED"` | `"OPEN"` | `"CLOSED"` |
| When merged (or null) | `mergedAt` | ISO 8601 string | `null` | `null` |
| When closed (or null) | `closedAt` | ISO 8601 string | `null` | ISO 8601 string |
| Merge commit SHA | `mergeCommit.oid` | full SHA | `null` | `null` |
| Mergeable now? | `mergeable` | n/a | `MERGEABLE` / `CONFLICTING` / `UNKNOWN` | n/a |
| Auto-merge enabled? | `autoMergeRequest` | n/a | object or `null` | n/a |

## Other commonly-mistaken field names

| Want | You might try | Correct field |
|---|---|---|
| Is the issue closed? | `closed` (boolean) | `state` (`"OPEN"` / `"CLOSED"`) |
| When was the issue closed? | `closed_at` (snake_case) | `closedAt` (camelCase) |
| Is the repo archived? | `archived` on PR/issue object | Query repo separately: `gh repo view --json isArchived` |
| Issue type | `issueType` | `issueType.name` (object, not string) |
| Has Pages enabled? | `hasPages` on PR/issue | Query repo: `gh repo view --json hasPagesEnabled` |
| Base repository | `baseRepository` on a PR | `baseRefRepositoryNameWithOwner` or query separately |

The unifying theme, which generalises past this list: GitHub's GraphQL schema is
**camelCase**, not snake_case, and PR/issue objects don't carry every property of
their parent repository.

## CI check fields

There is no flat `conclusion`, `checksStatus`, or `checkRuns` field on a PR.
Check status lives in **`statusCheckRollup`**, an array of one entry per check,
each with its own `conclusion`, `status`, `name`, `detailsUrl`, etc.

| Want to know | You might try | Correct field on PR |
|---|---|---|
| Are all checks passing? | `--json conclusion` | `--json statusCheckRollup --jq '[.statusCheckRollup[].conclusion] \| all(. == "SUCCESS")'` |
| Are all checks complete? | `--json checksStatus` | `--json statusCheckRollup --jq '[.statusCheckRollup[].status] \| all(. == "COMPLETED")'` |
| Which checks failed? | `--json conclusion,name` | `--json statusCheckRollup --jq '.statusCheckRollup[] \| select(.conclusion == "FAILURE") \| .name'` |
| Conclusion of one specific check | (no flat field) | `--json statusCheckRollup --jq '.statusCheckRollup[] \| select(.name == "test") \| .conclusion'` |

`conclusion` is `null` while a check is still running, and `SKIPPED` / `NEUTRAL`
are *not* failures — so a naive `all(. == "SUCCESS")` reports red on a PR that is
merely pending or has a skipped job. When you only need the pass/fail signal,
`gh pr checks <n> --required` exits non-zero on any failure or pending check.

## Polling a PR: `mergeStateStatus` never settles on a merged PR

A wait-for-CI loop written as *"poll until `mergeStateStatus` leaves `UNKNOWN`"*
**never exits if the PR merges while you wait** — a merged PR keeps reporting
`mergeStateStatus=UNKNOWN` and `mergeable=UNKNOWN` forever. In a repo where
automation can merge a PR out from under you (release-please auto-merge), that
is not a corner case.

```bash
# Wrong — spins forever once the PR is merged by anything but this loop
until ms=$(gh pr view "$N" -R "$R" --json mergeStateStatus --jq .mergeStateStatus); [ "$ms" != "UNKNOWN" ]; do sleep 10; done

# Right — MERGED is also a terminal state
until s=$(gh pr view "$N" -R "$R" --json state,mergeStateStatus --jq '"\(.state)|\(.mergeStateStatus)"'); \
      [ "${s%%|*}" = "MERGED" ] || [ "${s##*|}" != "UNKNOWN" ]; do sleep 20; done
```

**Always give a PR poll a terminal-state escape (`state=MERGED`/`CLOSED`) and a
wall-clock deadline.** Observed 2026-07-30: two such loops burned a 6m40s and a
10m timeout, one because the PR had already merged, the other per the next trap.

### Gating on an expected check *count* is brittle

The companion advice "wait for nothing-pending **and** at least N checks" (see
`git-plugin:git-merge-hazards`, which carries the CI check-*registration*
race) guards a real race — zero-pending is trivially true before jobs
register. But a hardcoded `N` breaks on **path-filtered** workflows: the same
repo yields 7 checks for a PR touching `*-plugin/**` and 5 for one touching
only `.claude/rules/**`, so `-ge 6` waits forever on a perfectly green PR.

Derive the expectation instead of hardcoding it — poll until the check count is
**stable across two consecutive reads** with nothing pending, and bound the
whole loop with a deadline.

## Default list cap: pass `--limit` when counting or verifying state

`gh issue list` / `gh pr list` default to **30 items**. When the intent is to
*count* or *verify the state of* a known set (not just eyeball the top of the
queue), the default silently truncates: a repo with 39 open issues returns only
30, so issues numbered beyond the page read as "absent" and look closed. Pass an
explicit `--limit` above the expected count (with `--json` for machine reads):

```bash
# Wrong — default 30; items 31+ silently missing, look "closed"
gh issue list --state open --json number --jq 'map(select(.number == 1392))'

# Right — explicit limit above the expected count
gh issue list --state open --limit 100 --json number,state
```

Symptom signature: a state check reports an issue closed/missing, but
`gh issue view <N>` shows it OPEN — the list was paginated, the direct view is
authoritative.

### `--state closed` includes MERGED PRs — so a big `--limit` still may not reach

The cap bites hardest where you least expect it, because **`gh pr list --state
closed` returns merged PRs too** (merged *is* a closed state). On a busy repo the
merged PRs vastly outnumber the closed-unmerged ones, so a generous-looking
`--limit` is spent almost entirely on them:

```bash
# Looks thorough; on a 2000-PR repo this reaches back only ~3 weeks, because
# nearly all 400 are merged PRs. Closed-unmerged PRs from months ago: invisible.
gh pr list --state closed --limit 400 --json number,mergedAt --jq '[.[] | select(.mergedAt == null)]'
```

Observed (claude-plugins, 2026-07): this returned **4** closed-unmerged PRs;
querying the same repo branch-by-branch found **11 more** that the page never
reached. The result reads as a complete answer, not a truncated one.

When you need closed-**unmerged** PRs specifically, don't paginate the closed
list and filter — query the smaller set directly, or drive the query off
something bounded (the branch list, `--search`):

```bash
gh pr list --head <branch> --state all --json number,state,mergedAt   # per-branch: exact
gh search prs --repo <o>/<r> --state closed --merged=false --limit 100
```

## Search qualifiers: `head:` is exact-match, not a prefix

`gh pr list --search "head:<X>"` (and the underlying GitHub search `head:`
qualifier) matches PRs whose head branch is **exactly** `<X>` — it is **not** a
prefix/glob match. So `gh pr list --search "head:feat/wo-"` matches a branch
literally named `feat/wo-` (usually none), returning **zero** — not "every
`feat/wo-*` branch". The failure is silent: the command succeeds, the count is
just wrong, and any budget/threshold keyed on that count never fires.

```bash
# Wrong — reads as "PRs on feat/wo-* branches"; actually matches the exact name feat/wo-
COUNT=$(gh pr list --state all --search "head:feat/wo- created:>=$TODAY" --json number --jq 'length')  # ~always 0

# Right — enumerate head branches and prefix-filter in jq
COUNT=$(gh pr list --state all --limit 200 --json headRefName,createdAt \
  --jq --arg d "$TODAY" '[.[] | select(.headRefName | startswith("feat/wo-")) | select(.createdAt | startswith($d))] | length')
```

Note `gh pr list --head "<branch>"` (the flag, not the search qualifier) **is**
an exact-branch filter and is correct for "PRs on this one branch". Reserve the
`--search "head:"` form for a known full branch name; reach for `--json
headRefName` + `startswith` whenever you mean a **prefix**.

## Related

- `.claude/rules/github-metadata-hygiene.md` (parent
  `laurigates/CLAUDE.md`) — when to query PR metadata at all
- `git-plugin:gh-cli-agentic` — common `--json` field sets and agent-facing `gh` recipes
