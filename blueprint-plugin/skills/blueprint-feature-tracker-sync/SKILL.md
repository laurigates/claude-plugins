---
created: 2026-01-02
modified: 2026-10-09
reviewed: 2026-07-27
description: Sync feature tracker with TODO.md, taskwarrior sidecars, and PRDs. Use when reconciling TODO.md vs tracker, draining WO entries, or recalculating stats.
allowed-tools: Read, Write, Bash, Glob, AskUserQuestion
model: sonnet
name: blueprint-feature-tracker-sync
---

Synchronize the feature tracker JSON with TODO.md and manage task progress.

## When to Use This Skill

| Use this skill when... | Use blueprint-feature-tracker-status instead when... |
|---|---|
| You're reconciling TODO.md checkboxes with the tracker | You want a read-only view of completion stats |
| You're draining WO entries from a taskwarrior sidecar (`--drain-wave`) | You want PRD coverage or ready-to-start lists |
| You're recalculating completion statistics after work | Use feature-tracking instead for low-level FR-code edits |
| You want a markdown progress summary via `--summary` | You need a quick "where are we?" snapshot without writes |

**Usage**: `/blueprint:feature-tracker-sync [--summary] [--drain-wave WO-A,WO-B,...] [--evidence-files <list>] [--evidence <text>]`

**Flags**:
| Flag | Description |
|------|-------------|
| `--summary` | Generate human-readable markdown summary (stdout only, no file) |
| `--drain-wave WO-A,WO-B,...` | Sidecar mode: drain a comma-separated list of completed WOs from `tasks.pending` into `tasks.completed`, then flip any FRs whose `implementing_wos` are now all closed |
| `--evidence-files <list>` | Comma-separated list of files (one per WO) holding the evidence string for `--drain-wave`. Pairs positionally with the WO list |
| `--evidence <text>` | Inline evidence string (single WO only). Use when the text is short and free of single quotes |

---

## Interaction Mode

Before any closing `AskUserQuestion` menu, resolve the automation config:

```bash
bash "${CLAUDE_SKILL_DIR}/../../scripts/get-automation-config.sh"
```

Under `EFFECTIVE_INTERACTION_MODE=quiet`, read [references/interaction-mode.md](references/interaction-mode.md) before skipping any menu; otherwise stay fully interactive.

## Mode Selection (run first)

Decide which mode applies before any work:

1. If `--summary` is present, run **Mode: Generate Summary** and exit.
2. If `--drain-wave` is present, run **Mode: Taskwarrior Sidecar Drain** and exit.
3. Otherwise, run sidecar detection (Step 0 below). If a sidecar is detected and
   `TODO.md` is absent, prefer **Sidecar Drain** semantics for any user-facing
   completion prompts; otherwise run **Mode: Full Sync (Default)**.

---

## Mode: Generate Summary (`--summary`)

When `--summary` is provided, generate a human-readable progress report without modifying any files:

Run the `jq` program in [references/summary-mode.md](references/summary-mode.md).

For a sample of the rendered output, see [REFERENCE.md](REFERENCE.md#work-overview-summary-output---summary).

**Exit** after displaying summary.

## Mode: Full Sync (Default)

### Step 0: Run the deterministic core

Run the helper ([what it owns](references/sync-core.md)); it writes the backfilled tracker in place:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/blueprint-feature-tracker-sync.sh" --home-dir "$HOME" --project-dir "$(pwd)"
```

Parse `STATUS=` and `ISSUES:` from the output. `STATUS=ERROR` means the tracker
is missing (`tracker_missing` → report "Feature tracking not enabled; run
`/blueprint:init`"), invalid JSON, or unprocessable: report `REASON=` and stop
([shapes](references/sync-core.md#both-features-shapes)). `SIDECAR=true` means the taskwarrior-sidecar
convention is in use — also probe for live taskwarrior linkage (any task with a
`bpid` matching a project blueprint ID) via the parallel-safe `export | jq`
idiom (`task bpid.any: status:any export | jq 'length'`, never `task list`; see
`.claude/rules/parallel-safe-queries.md`). When a sidecar is in play, skip the
`TODO.md` reconciliation steps (Steps 4–5, 8) — there is no authoritative TODO
file — and route any WO closures to **Mode: Taskwarrior Sidecar Drain**.

Each `status_inferred` issue is a feature the evidence flipped up from
`not_started` (the guard never lowers a higher status); surface these under
"Inferred from evidence" in the Step 9 report. For the canonical merge `jq` and
test-evidence patterns, see [REFERENCE.md](REFERENCE.md#evidence-backfill-jq-recipe).

### Step 4: Detect discrepancies

Look for inconsistencies:
- Feature marked `complete` in tracker but unchecked in TODO.md
- Feature checked in TODO.md but not `complete` in tracker
- Feature in `tasks.in_progress` but tracker says `complete`
- PRD status doesn't match feature implementation status
- Feature marked `not_started` but Step 0 inferred shipped code (a `status_inferred` issue; confirm via Step 5)

### Step 5: Ask user about discrepancies

If discrepancies are found, ask how to resolve them with the Step 5 prompt in [references/prompts.md](references/prompts.md) (tracker from TODO.md / TODO.md from tracker / review each / skip).

### Step 6: Recalculate statistics

The feature-level counts and completion percentage are already in the Step 0
script output (`STAT_COMPLETE`/`STAT_PARTIAL`/`STAT_IN_PROGRESS`/`STAT_NOT_STARTED`/`STAT_BLOCKED`,
`COMPLETION_PERCENTAGE`). After any discrepancy resolutions from Step 5 change a
status, re-derive phase status from the contained features:
  - `complete` if all features complete
  - `in_progress` if any feature in_progress
  - `partial` if some complete, some not
  - `not_started` if no features started

### Step 6a: Resolve portfolio links (v3.3.0+, root blueprints only)

Run only when the manifest at the root has `workspaces.role == "root"` AND the
feature-tracker contains any feature with a non-empty `implemented_by` array.
Skip this step entirely otherwise.

For the child-status rollup table, the `workspaces` summary shape, and the
unresolved-entry warnings, see
[REFERENCE.md](REFERENCE.md#portfolio-link-resolution-v330-root-blueprints-only).

### Step 7: Update feature-tracker.json

- Apply resolved discrepancies
- Update `statistics` section
- Update `last_updated` to today's date
- Update PRD status if features changed
- Update `current_phase` to first incomplete phase

### Step 7a: Verify tracker integrity (deterministic)

Sync **writes** the tracker; this step **verifies** what was written. Run it after
every write path (Full Sync Step 7 and Sidecar Drain Step 5) — nothing else
detects a tracker that drifted by any other route, so the drift compounds
silently:

```bash
bash "${CLAUDE_SKILL_DIR}/../../scripts/blueprint-tracker-check.sh" --project-dir "$(pwd)"
```

Parse `STATUS=` and the `ISSUES:` rows. `statistics` is a **cache** of the
features collection, so `statistics_divergence` rows (which carry
`FIELD=`/`EXPECTED=`/`ACTUAL=`) mean every downstream "N% complete" figure quoted
from this file is wrong — fix the cache in the same run, then re-run the check.

For the per-`TYPE=` response table (`statistics_divergence`,
`feature_status_near_miss`, `feature_status_unknown`,
`task_feature_disagreement`, `fr_cited_not_minted`, `doc_status_stale`,
`dead_statistics_bucket` / `duplicate_timestamp_field`), the manifest
`validation` conventions, and the features-vs-tasks duplicate caveat, see
[REFERENCE.md](REFERENCE.md#tracker-integrity-issue-types).

### Step 8: Update TODO.md (if exists)

- Ensure checkbox states match feature status
- `[x]` for `complete` features
- `[ ]` for `not_started` features
- Note partial completion in task text if needed

### Step 9: Output sync report

Print: statistics block (total/complete/partial/in_progress/not_started/blocked + completion %), current phase, phase-status list, active tasks list, "Changes Made" (status flips, TODO checkboxes touched), "Inferred from evidence" (Step 0 `status_inferred` flips with their commit SHAs), and "Unresolved Discrepancies" if any were skipped. See [REFERENCE.md](REFERENCE.md#sync-report-template) for the full report template.

### Step 10: Update task registry

Update the `task_registry["feature-tracker-sync"]` entry in
`docs/blueprint/manifest.json` — `last_completed_at`, `last_result`,
`context.last_todo_hash`, and the `stats` counters. For the `jq` recipe, see
[REFERENCE.md](REFERENCE.md#task-registry-update-jq-recipe).

### Step 11: Prompt for next action

Ask with the Step 11 prompt in [references/prompts.md](references/prompts.md).

---

## Mode: Taskwarrior Sidecar Drain (`--drain-wave`)

Drain one or more completed WOs from `tasks.pending` into `tasks.completed`,
sourcing evidence from taskwarrior annotations (or from named files / an
inline string), then flip any FR-level entries whose implementing WOs are
now all closed.

Follow Steps 1–6 and the single-WO short form in [references/sidecar-drain.md](references/sidecar-drain.md): line up evidence per WO, source it from taskwarrior with `task … export | jq` (never `task list`), drain `tasks.pending` → `tasks.completed` one WO at a time, flip FRs whose `implementing_wos` are all closed (never downgrade a `complete` FR), recalculate statistics and run Full Sync Step 7a, then report. Refuse the run when the WO list and `--evidence-files` lengths disagree.

---

## Agentic Optimizations

Read-only integrity checks, a dry run of the sync core, and the stdout-only summary: [references/agentic-optimizations.md](references/agentic-optimizations.md).

## Direct Edits, Recipes & Sample Output

For ad-hoc tracker surgery (`jq` recipes for adding to `in_progress`, completing tasks, queueing pending work), the evidence-backfill / task-registry / FR-status-flip `jq` recipes, the portfolio-link rollup rules, the tracker-integrity issue-type responses, and the sync / summary / drain report samples, see [REFERENCE.md](REFERENCE.md).

## Related

Skills and rules that pair with `--drain-wave` (`taskwarrior-plugin:task-done`, `task-coordinate`, `session-plugin:session-end`, `parallel-safe-queries.md`): [references/sidecar-drain.md](references/sidecar-drain.md).
