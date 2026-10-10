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

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/blueprint-feature-tracker-sync.sh" --home-dir "$HOME" --project-dir "$(pwd)"
```

## Both `features` shapes

The helper accepts both shapes of the `features` collection and writes the
shape it read back unchanged (#2867). `FEATURES_SHAPE=` reports which one it
found, with the same vocabulary as `blueprint-plugin/scripts/blueprint-tracker-check.sh`:

| `FEATURES_SHAPE=` | Shape | Feature records |
|---|---|---|
| `object` | Keyed by FR id, as `schemas/feature-tracker.schema.json` declares: an FR category holds a nested `features` object of FR sub-features | Every status-bearing object reached through `features` collections; an FR category without its own `status` is not counted |
| `array` | A flat list of records carrying `id` + `status` | Each status-bearing item, plus any status-bearing nested `features` |
| `absent` | No `features` key, or `null` | None; the stats are all zero |

`FEATURES_TOTAL=` and every `STAT_*` count the same record set, so
`COMPLETION_PERCENTAGE=` is never computed over a different denominator than
the one reported.

## Failure contract

Any `features` value that is neither an object, an array nor absent (a string, a
number), and any `jq` step that fails, ends the run with `STATUS=ERROR`, a
`REASON=` naming the cause (`malformed_features`, `jq_failed`, `write_failed`),
an `ERROR` issue, and exit `1`. The tracker is not rewritten. `STATUS=OK` always
comes with populated `STAT_*` fields.
