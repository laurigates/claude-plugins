---
created: 2026-05-11
modified: 2026-11-24
reviewed: 2026-07-29
---

# `gh --json` Field Names

Unscoped on purpose: these traps fire on a `gh` **command**, which no `paths:`
glob can see (`.claude/rules/context-engineering.md`).

An invalid `--json` field name exits 1 at *runtime* and dumps the full available
field list — so don't guess: read that list, or `gh pr help json-fields` /
`gh <cmd> --help`. Common field sets per command: `git-plugin:gh-cli-agentic`.
Worked examples and the incidents behind each trap:
[`docs/rules/gh-json-fields.md`](../../docs/rules/gh-json-fields.md).

## The `merged` mistake

There is no `merged` field on a PR. Use `--json state --jq '.state == "MERGED"'`
or `mergedAt` (ISO 8601, `null` when not merged).

| Want to know | Correct field | Merged | Open | Closed-without-merge |
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
| Is the repo archived? | `archived` on PR/issue object | `gh repo view --json isArchived` |
| Issue type | `issueType` | `issueType.name` (object, not string) |
| Has Pages enabled? | `hasPages` on PR/issue | `gh repo view --json hasPagesEnabled` |
| Base repository | `baseRepository` on a PR | `baseRefRepositoryNameWithOwner` or query separately |

The schema is **camelCase**, and PR/issue objects don't carry every property of
their parent repository.

## CI check fields

There is no flat `conclusion`, `checksStatus` or `checkRuns` field on a PR.
Checks live in **`statusCheckRollup`**, one entry per check with its own
`conclusion`, `status` and `name`. `conclusion` is `null` while a check runs,
and `SKIPPED` / `NEUTRAL` are not failures, so a naive `all(. == "SUCCESS")`
reports red on a pending or skipped job. For pass/fail alone,
`gh pr checks <n> --required` exits non-zero on any failure or pending check.

## Polling a PR

A merged PR reports `mergeStateStatus=UNKNOWN` and `mergeable=UNKNOWN` forever,
so a loop that waits for `mergeStateStatus` to leave `UNKNOWN` never exits once
anything merges the PR. **Give every PR poll a terminal-state escape
(`state=MERGED`/`CLOSED`) and a wall-clock deadline.**

Do not gate on a hardcoded check count: path-filtered workflows give the same
repo 7 checks on one PR and 5 on another. Poll until the count is
stable across two consecutive reads, with nothing pending. `git-plugin:git-merge-hazards`
waits and merges through its `scripts/merge-chain.sh`, which applies that rule
([stacked-chain-push.md](../../git-plugin/skills/git-merge-hazards/references/stacked-chain-push.md)).

## Default list cap: pass `--limit` when counting or verifying state

`gh issue list` / `gh pr list` return **30 items** by default, so a state check
over a larger set reads items 31+ as absent. Pass `--limit` above the expected
count. `gh issue view <N>` is authoritative when a list disagrees.

**`--state closed` includes merged PRs**, so on a busy repo a large `--limit` is
spent almost entirely on them. For closed-**unmerged** PRs, query the smaller
set directly: `gh pr list --head <branch> --state all`, or
`gh search prs --repo <o>/<r> --state closed --merged=false`.

## Search qualifiers: `head:` is exact-match, not a prefix

`gh pr list --search "head:feat/wo-"` matches only a branch literally named
`feat/wo-` and silently returns zero. For a prefix, list `--json headRefName`
and filter with `startswith` in `jq`. The `--head <branch>` flag is an
exact-branch filter and is correct for one known branch.

## Related

- `.claude/rules/github-metadata-hygiene.md` (parent `laurigates/CLAUDE.md`) — when to query PR metadata at all
- `git-plugin:gh-cli-agentic` — common `--json` field sets and agent-facing `gh` recipes
