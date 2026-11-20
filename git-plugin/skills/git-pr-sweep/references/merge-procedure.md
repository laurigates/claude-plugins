# Merge procedure

The merge stage runs in the main session. Workflow agents cannot merge: auto mode denies a
`gh pr merge` whose authorisation reaches the agent only through a workflow script, and no hook
guards `gh pr ready`, so the author gate (G2) has already decided who may be readied.

## Order of operations

| # | Actor | Action |
|---|---|---|
| M1 | main session | the review timestamp, `date -u +%Y-%m-%dT%H:%M:%SZ`, taken after the last fix push and **before** the re-list: a push landing after it is newer than it, so merge-chain.sh stops with GUARD_LATE_COMMIT |
| M2 | script | `list-sweep-prs.sh --resolve-blockers` into a fresh `roster.json`; a blocker may have merged since the review |
| M3 | script | `merge-gate.sh roster.json review.json fix-<i>.json...` into `gate.json` |
| M4 | pr-merge | only when `gate.json` has `ready` drafts: one reader per draft, then the rebuilt `plan.json` |
| M5 | main session | `gh pr ready <n> -R <owner>/<repo>` for each `plan.ready`, one literal number per call, then `gh pr view <n> -R <owner>/<repo> --json isDraft` to confirm (readying makes no commit) |
| M6 | main session | per `plan.merge` chunk, one background `merge-chain.sh` call with the M1 timestamp; before every chunk after the first, repeat M2–M3 and drop any PR that no longer passes |
| M7 | main session | read the `=== MERGE CHAIN ===` block |
| M8 | conditional | one repair on CONFLICT or CI_RED, then resume the chunk |

A timestamp taken after the re-list would leave a gap: a push between the re-list and the
timestamp is older than it, and merge-chain.sh compares commits only with `--review-ts` and the head
CI settled on, never with the head merge-gate.sh cleared. A commit dated before M1 but pushed after
the last re-list still slips through; re-gating before each chunk keeps that window to seconds.

## merge-chain.sh invocation

The script belongs to `git-plugin:git-merge-hazards` and is the only sanctioned merge loop. Call it
with literal values, never `$var` lists, because the external-PR merge guard reads `--repo` and
`--prs` from the command text and checks each listed PR:

```
bash <git-merge-hazards dir>/scripts/merge-chain.sh --repo acme/widgets --prs 12,15,19 --review-ts 2026-11-20T10:00:00Z --fetch-dir /abs/clone
```

- No `--method`: the script resolves each PR's method through `pr-merge-method.py`.
- Run it in a background Bash call (`run_in_background`), which the foreground timeout does not cut
  off, and wait for its completion notice. A PR can take up to 5560 s in the worst case, and the
  script's own `--timeout` (default 1800 s) bounds the CI wait per PR; split a chunk rather than
  raising it.
- A chunk is at most 8 PRs: the guard runs one `gh pr view` per listed PR inside its hook timeout,
  and a timeout blocks. Lower `--chunk` on `merge-gate.sh` if denials show guard timeouts.

## Reading the result

The block reports `STATUS`, `MERGED`, `SKIPPED`, `STOPPED_AT`, `REASON` and `REMAINING`.

| Stop | Response |
|---|---|
| none | next chunk |
| `CONFLICT` | one pr-fix run with a single unit (M8) |
| `CI_RED` | one pr-fix run with a single unit (M8) |
| `DENIED` | no agent; report for Lauri (the guard refused an author) |
| `GUARD_LATE_COMMIT` | no agent; report for Lauri (a commit newer than the review timestamp) |

Chunks after a stop that is not repaired stay unrun; report their PRs as `not_attempted`.

## M8: one repair per PR per sweep

Run pr-fix with one unit:

```
{id: "pr-<STOPPED_AT>", branch: <head>, head_sha: <headRefOid from gh pr view <n> --json headRefOid>,
 base: "origin/<base>",
 findings: [{id: "M1", severity: "blocker", where: "", problem: "<REASON from merge-chain.sh>",
             fix: "merge origin/<base> into the branch (no rebase, no force-push) and resolve; or fix the failing check <names>"}]}
```

Pass `skills: ["git-plugin:git-conflicts"]` for CONFLICT and `["git-plugin:git-fix-pr"]` for
CI_RED. On a PASS or REPAIRED_PASS row with a pushed head, take a new timestamp (M1), then repeat
M2–M6 for `REMAINING` only with that fix file added. A second stop on the same PR is reported, not
repaired again.

## Stacked PRs, forks and late commits

- A PR whose base is not the default branch fails G7 and is reported; retargeting the child is a
  human step (`git-plugin:git-merge-hazards`).
- In a fork or repo whose Actions are not enabled, CI stays `none` and G6 reports the PR ("no
  checks ran"): the sweep merges only on green CI, so it never hands merge-chain.sh a PR with an
  empty rollup.
- Any push after the review fails G5 or stops merge-chain.sh with GUARD_LATE_COMMIT. Repos with an
  auto-fix workflow see this often; re-run the review stage for those PRs.
