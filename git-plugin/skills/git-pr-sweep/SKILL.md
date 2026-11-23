---
name: git-pr-sweep
description: "Review, fix, then merge one repo's open PRs incl. ready drafts, as three runnable stages. Use when sweeping a repo's whole PR queue to merge."
args: "<owner/repo> [--stage review|fix|merge|all] [--root PATH] [--review FILE] [--fix FILE...] [--dry-run]"
argument-hint: "owner/repo [--stage all] [--root /abs/clone] [--dry-run]"
allowed-tools: Bash(bash ${CLAUDE_SKILL_DIR}/scripts/list-sweep-prs.sh *), Bash(bash ${CLAUDE_SKILL_DIR}/scripts/plan-review-runs.sh *), Bash(bash ${CLAUDE_SKILL_DIR}/scripts/prefetch-heads.sh *), Bash(bash ${CLAUDE_SKILL_DIR}/scripts/merge-review.sh *), Bash(bash ${CLAUDE_SKILL_DIR}/scripts/review-to-units.sh *), Bash(bash ${CLAUDE_SKILL_DIR}/scripts/merge-gate.sh *), Bash(bash ${CLAUDE_SKILL_DIR}/scripts/prune-worktrees.sh *), Bash(bash ${CLAUDE_SKILL_DIR}/../git-merge-hazards/scripts/merge-chain.sh *), Bash(gh pr ready *), Bash(gh pr view *), Bash(gh pr list *), Bash(date -u *), Read, Write, Workflow, Skill
created: 2026-11-20
modified: 2026-11-23
reviewed: 2026-11-20
---

# /git:pr-sweep

Review one repository's open PRs, fix confirmed findings on the PRs' own branches, then ready and
merge what passes every gate. Scripts decide every count and gate; only the main session readies and merges.

## When to Use This Skill

| Use this skill when... | Use another skill instead when... |
|---|---|
| Taking a repo's PR queue, ready drafts included, through review, fix and merge | Grooming the backlog with no code changes → `git-plugin:git-triage` |
| Merging only what a fresh review found clean | Human review threads on one PR → recommend the user run `/git:pr-feedback` |
| | Merging a known PR chain → `git-plugin:git-merge-hazards` |

## Context

- Current checkout: !`git log --max-count=1 --oneline`
- Current branch: !`git branch --show-current`

## Parameters

Parse these from `$ARGUMENTS`:

| Argument | Default | Meaning |
|---|---|---|
| `<owner/repo>` | `git-plugin:git-repo-detection` | The one repository swept; a github.com URL works too |
| `--stage review\|fix\|merge\|all` | `all` | `all` runs the stages in order, stopping when one leaves nothing for the next |
| `--root PATH` | current checkout | Absolute path of a clone whose `origin` is the repo |
| `--review FILE` | none | `review.json`; required by `--stage fix`; `--stage merge` without it merges nothing |
| `--fix FILE...` | none | `fix-<i>.json` files, for `--stage merge` |
| `--dry-run` | off | Stop before pr-fix, `gh pr ready` and `merge-chain.sh`; print the plan |

`<work>` is `<root>/tmp/pr-sweep/` when `tmp/` is git-ignored there, else the session scratchpad.
Outside `<root>`'s repository, pass `worktrees: "<root>/.claude/worktrees"` in every Workflow's args. Formats: [references/handoff-formats.md](references/handoff-formats.md).

## Execution

Execute this PR sweep one stage at a time, reading each script's summary before going on.

### Step 1: Guard the clone and list the PRs (every stage)

1. Invoke `git-plugin:git-coworker-check` on `<root>`; stop if another agent is active there.
2. List open PRs, drafts included, classified by script:

   ```bash
   bash ${CLAUDE_SKILL_DIR}/scripts/list-sweep-prs.sh --resolve-blockers --out <work>/roster.json <owner> <repo>
   ```

   Show the counts; `TRUNCATED=true` (the 500-PR ceiling) goes in the final report.

### Step 2: Review (`--stage review|all`)

1. Plan the runs (small PRs share a finder pair):

   ```bash
   bash ${CLAUDE_SKILL_DIR}/scripts/plan-review-runs.sh --out <work>/review-plan.json <work>/roster.json
   ```

2. Fetch every head and base once, so no agent fetches:

   ```bash
   bash ${CLAUDE_SKILL_DIR}/scripts/prefetch-heads.sh --root <root> <work>/roster.json
   ```

   On `MISSING=` PRs re-run Step 1; still missing → report them unreviewed and re-plan without them.
3. For each `runs[i]`, in order, adapt `workflows/pr-review.workflow.js` and run it with args `{repo, root,
   prs: runs[i].prs, groups: runs[i].groups, context, decided}`. Write each return verbatim to
   `<work>/review-<i>.json`.
4. For each `review-<i>.json` with `unverified` rows, re-run the template once with `claims` = that
   run's unverified rows and `prs` = those PRs' rows from `review-plan.json` `runs[i].prs`; write
   `<work>/verify-<i>.json`.
5. Join every file written, review files first:

   ```bash
   bash ${CLAUDE_SKILL_DIR}/scripts/merge-review.sh --out <work>/review.json <work>/review-1.json <work>/review-2.json <work>/verify-1.json
   ```

### Step 3: Fix (`--stage fix|all`)

1. Turn confirmed findings into units; every PR that must not be fixed is excluded with its reason:

   ```bash
   bash ${CLAUDE_SKILL_DIR}/scripts/review-to-units.sh --chunk 3 --out <work>/units.json <work>/roster.json <work>/review.json
   ```

2. For each `runs[i]`, in order (the next run must see this one's push), adapt
   `workflows/pr-fix.workflow.js` and run it with args `{repo, root, base: "origin/<default>",
   units: runs[i], gates, setup, skills: ["git-plugin:git-commit-workflow"], decisions, trailer}`.
   `gates` are the repo's test and lint commands; `decisions` relay Lauri's choices as given.
   Write each return to `<work>/fix-<i>.json`.
3. Before re-dispatching a FAILED or UNVERIFIED unit fresh, clear what it left
   ([references/fix-redispatch.md](references/fix-redispatch.md)), then
   `gh pr list -R <owner>/<repo> --head <branch> --state all --json number,state,headRefOid`.

### Step 4: Merge (`--stage merge|all`)

Main session only, in order; stop handling: [references/merge-procedure.md](references/merge-procedure.md).

1. Take the review timestamp first, before the re-list, so a later push stops merge-chain.sh:
   `date -u +%Y-%m-%dT%H:%M:%SZ`.
2. Re-list fresh (a blocker may have merged mid-sweep): repeat Step 1.2.
3. Gate every PR:

   ```bash
   bash ${CLAUDE_SKILL_DIR}/scripts/merge-gate.sh --out <work>/gate.json <work>/roster.json <work>/review.json <work>/fix-1.json <work>/fix-2.json
   ```

4. If `gate.json` has `ready` drafts, adapt `workflows/pr-merge.workflow.js`, run it with args
   `{repo, plan: gate.json, roster: roster.json}`, write `<work>/plan.json`; else `plan.json` is `gate.json`.
5. For each draft in `plan.ready`, one literal number per call:
   `gh pr ready 12 -R <owner>/<repo>`, then confirm with `gh pr view 12 -R <owner>/<repo> --json isDraft`.
6. For each `plan.merge` chunk, in a background Bash call, `--repo` and `--prs` as literals; before
   each later chunk, repeat steps 2–3 and drop PRs that no longer pass:

   ```bash
   bash ${CLAUDE_SKILL_DIR}/../git-merge-hazards/scripts/merge-chain.sh --repo <owner>/<repo> --prs 12,15,19 --review-ts <ts> --fetch-dir <root>
   ```

7. Read the `=== MERGE CHAIN ===` block. A CONFLICT or CI_RED stop gets one pr-fix run for that PR,
   then steps 1–6 for `REMAINING`; DENIED and GUARD_LATE_COMMIT are reported for Lauri.

## Draft handling

| draft_class | Reviewed | Fixed | Readied and merged |
|---|---|---|---|
| `not_draft` | yes | yes | when G1–G7 pass |
| `ready_candidate` | yes | yes | when G1–G8 pass and pr-merge's reader finds no unmet `## Draft status` condition |
| `blocked`, `blockers_unresolved` | yes | yes | no; reported with each blocker not MERGED |
| `wip`, `no_section`, `no_blocker_urls` | yes | no | no; surfaced with findings and reason |

WIP markers, gates and per-kind policy (release-please, Renovate, external authors): [references/draft-gates.md](references/draft-gates.md).

## Workflow harness (template)

`workflows/pr-review.workflow.js`, `workflows/pr-fix.workflow.js` and `workflows/pr-merge.workflow.js`
ship beside this skill. **Each is a TEMPLATE to adapt, not a script to run verbatim.** Read it, then
rewrite it for the work in front of you.

**Adapt freely:** the lens and reader prompt wording, `lensBrief`, `verifyCap`, `decided[]`, the
repo's gates, setup and trailer, and the merge chunk size.

**Agent budget (pr-review.workflow.js):** 15 — 2 finders per group over `GROUPS.slice(0, 4)` plus 7 verifiers over `toVerify.slice(0, 7)`.

**Agent budget (pr-fix.workflow.js):** 13 — per unit over `UNITS.slice(0, 3)` a fixer, a verifier, and on `fix-needed` a repairer and a re-verifier, plus 1 finalise.

**Agent budget (pr-merge.workflow.js):** 8 — one reader per ready draft over `READY.slice(0, 8)`.

**Preserve across any adaptation:** (a) every loop bound comes from a script (planner groups,
`review-to-units.sh` units, `merge-gate.sh` ready drafts), with literal slices in the fan-outs and an
abort over a cap, never a truncation; (b) the closed enums: refute-by-default
`confirmed|partially|refuted` (an unreproduced confirmation is a dead verifier), `pass|fix-needed|reject`,
and `ready|hold` where only a consistent `ready` clears a draft; (c) Rank is pr-review's barrier, Finalise is pr-fix's (push order on one remote), the plan rebuild is pr-merge's;
(d) pr-fix's `rr-shared` region stays byte-identical with repair-round's, minus its stage helpers
(`scripts/tests/test-pr-sweep-workflows.sh`).

Never `Workflow({resumeFromRunId})` to retry a few failed worktree agents — a resume re-runs agents
that already succeeded and opens duplicate PRs (#1868). Re-dispatch the failed units fresh and
sequentially after checking `gh pr list --head <branch> --state all --json number,state`.

Push, PR creation, and GitHub mutations happen **only** in the single sequential finalise stage,
never inside a fanned-out agent.

**Skip the harness when:** the repo has one open PR (review and fix inline), or `plan.ready` is empty.

## Post-actions

1. Print one row per PR: number, stage reached, outcome or first failing gate and `reason`, link;
   PRs in chunks a stop left unrun are `not_attempted`. Under a row with `findings`, list them and
   its `fix_block`: the only place a Renovate, external or unreadyable draft's findings surface.
2. File a GitHub issue in the swept repo for each follow-up.
3. Run `bash ${CLAUDE_SKILL_DIR}/scripts/prune-worktrees.sh --root <root>` and list its
   `WORKTREE_<i>=` lines in the report. Remove none: a peer session can hold the same names.
