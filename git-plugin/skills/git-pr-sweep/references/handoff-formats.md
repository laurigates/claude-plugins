# Hand-off formats

Every stage reads files the main session wrote and writes files the next stage reads. The JSON
comes from scripts or is a Workflow return written verbatim; nothing is edited by hand. Each script's
header holds the authoritative schema; this page is the map between them.

## Files in `<work>/`

| File | Written by | Read by |
|---|---|---|
| `roster.json` | `list-sweep-prs.sh --resolve-blockers` | every script; pr-merge `roster` arg |
| `review-plan.json` | `plan-review-runs.sh` | pr-review args, one `runs[i]` per run |
| `review-<i>.json`, `verify-<k>.json` | pr-review returns | `merge-review.sh` |
| `review.json` | `merge-review.sh` | `review-to-units.sh`, `merge-gate.sh` |
| `units.json` | `review-to-units.sh --chunk 3` | pr-fix args, one `runs[i]` per run |
| `fix-<i>.json` | pr-fix returns | `merge-gate.sh` (several files, later wins) |
| `gate.json` | `merge-gate.sh` | pr-merge `plan` arg |
| `plan.json` | pr-merge return, or `gate.json` when no draft is ready | Step 4 of the merge stage |

`<work>` is `<root>/tmp/pr-sweep/` when `tmp/` is git-ignored in the clone, otherwise the session
scratchpad. Never commit these files.

## roster.json (`list-sweep-prs.sh`)

```
{repo, default_branch, self, fetched, pages, truncated, max_prs, blockers_resolved,
 counts:{prs, drafts, ready_candidates, wip, skipped, reviewable, fixable, ci_red, ci_truncated},
 prs:[{number, title, url, is_draft, author, author_kind: self|bot|external, author_association,
       head, head_sha, base, base_is_default, cross_repo, labels,
       additions, deletions, changed_files, diff_lines,
       wip, wip_markers, draft_class, draft_status:{section_present, blockers:[{url, state?}]},
       ci: red|pending|green|none, ci_failed, ci_truncated, merge_state, review_decision,
       sweep_skip: release_please|renovate|cross_repo_head|null,
       policy:{review, review_block, fix, fix_block}}]}
```

The PR body is never emitted, so it never reaches an agent prompt; only pr-merge's readers read it,
for one ready draft each, as data.

## review-plan.json (`plan-review-runs.sh`)

```
{repo, default_branch, limits:{max_prs: 6, max_groups: 4, max_per_group: 3,
                               small_lines: 150, small_files: 6, group_lines: 300},
 runs:[{prs:[{number, title, url, head, head_sha, base, is_draft, diff_lines, changed_files,
              author_kind, draft_class}], groups:[[number]]}],
 not_reviewed:[{number, reason}]}
```

pr-review args for run `i`: `{repo, root, prs: runs[i].prs, groups: runs[i].groups}` plus the
optional `worktrees`, `context`, `decided`, `lensBrief`, `verifyCap`. `author_kind` in each row picks
the verifier mode: `self`/`bot` run in a worktree, anything else (or none) reads only.

## pr-review return, and review.json (`merge-review.sh`)

```
{repo, mode: full|verify-only, status: reviewed|partial|unreviewed,
 prs:[{number, head_sha, status, lensesFailed:[lens],
       open:[{id, severity: blocker|major|minor, where, problem, fix, evidence, lens,
              verdict: confirmed|partially}],
       refuted:[...], unverified:[claim + pr], verifierFailed:[key], stats}],
 stats}
```

`review.json` is `{repo, runs:[{mode, status}], prs:[...]}` with the same rows. A verify-only run
updates a full-run row only when `head_sha` matches; its `open`/`refuted` are appended and its
`unverified`/`verifierFailed` replace the old ones. Status, recomputed for every row:
`unreviewed` when both lenses died, `partial` when one lens died or a finding is unverified or behind
a dead verifier, otherwise `reviewed`.

A verify-only re-run is one per review run: `claims` = that run's `unverified` rows (each carries
`pr`) and `prs` = that run's rows for those PRs, written to `verify-<i>.json`. Pooling claims across
runs can exceed the 6-PR cap and abort.

## units.json (`review-to-units.sh`) and pr-fix

`review.prs[n].open[]` is pr-fix's `units[].findings[]` unchanged.

```
{repo, chunk, units_total,
 runs:[[{id: "pr-<n>", branch, head_sha, base: "origin/<base>", issues: [], brief, gates: [], findings}]],
 excluded:[{number, reason, open_count}]}
```

pr-fix return (repair-round's shape): `{rows:[{unit, branch, status, fix, verdicts}],
finalisePlan:[{unit, branch, head_sha, pr_body_note}], pushed:[{unit, branch, status, detail}] | null}`.
`finalisePlan` entries also carry `base_sha` (the reviewed head) and `commits` (the fixer's and
repairer's commits); Finalise pushes a tip only when the remote is still at `base_sha` and exactly
those commits follow it. `merge-gate.sh` accepts one or several of these files, keyed on the
`pr-<n>` unit id.

## gate.json (`merge-gate.sh`) and plan.json (pr-merge)

```
{repo, passed:[n], ready:[n], merge:[[n]],
 report:[{number, url, is_draft, gate, reason, failed:[gate], open_count,
          fix_block, findings:[{id, severity, where, problem}]}]}
```

pr-merge adds `held:[{number, reason, conditions}]` and `verdicts`, removes held drafts from
`passed`, `ready` and `merge`, rebuilds the chunks, and reports each held draft with gate
`draft_prose`. Each `merge` chunk is pasted as a literal `--prs` list.

## Standalone stages

| Invocation | Needs | Runs |
|---|---|---|
| `--stage review` | `owner/repo`, `--root` | roster, plan, prefetch, pr-review, merge-review |
| `--stage fix --review FILE` | a `review.json` | roster (fresh, for the head check), units, pr-fix |
| `--stage merge --review FILE [--fix FILE...]` | a `review.json` | roster, gate, pr-merge, ready, merge-chain |

`--stage merge` without `--review` gates against `{"prs":[]}`: every PR fails the review gate, so
nothing merges. That is deliberate: "no open findings" cannot be shown without a review.
