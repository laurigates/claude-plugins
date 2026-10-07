# feature-tracker-sync — The Deterministic Sync Core (Full Sync Step 0)

## Source of truth

**Note**: As of v1.1.0, feature-tracker.json is the single source of truth for progress tracking. The `tasks` section replaces work-overview.md.

## What `blueprint-feature-tracker-sync.sh` owns

Run the helper. It owns the mechanical core: taskwarrior-sidecar marker
detection (`SIDECAR=`), tracker existence/validity, the implementation-evidence
backfill (file-existence + `git log` commit dedupe), status inference via the
fixed decision table WITH the never-downgrade guard (`EVIDENCE_FLIPPED=`,
`status_inferred` issues), and the statistics rollup (`STAT_*`,
`COMPLETION_PERCENTAGE=`). It writes the backfilled tracker in place:
