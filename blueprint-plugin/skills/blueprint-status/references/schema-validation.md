# blueprint-status — Schema Validation Background (Steps 2a, 2b)

Why the schema checks run here and what they cover.

## Step 2a — why status validates the manifest

Every consumer of the manifest degrades gracefully on bad input, which is
correct at runtime but makes a **typo indistinguishable from an intentional
omission** — `autonomy_levle: 3` reads as level 0, `adr_dris: [...]` reads as
unconfigured, and nothing says a word. Status is the read-only diagnostic
that already parses the whole manifest, so the schema check belongs here:

## Step 2a — what the schema closes

It validates against
[`blueprint-plugin/schemas/manifest.schema.json`](../../../schemas/manifest.schema.json)
and emits the structured `STATUS=` / `ISSUE_COUNT=` convention. Blocks with a
fixed key set (`automation`, `validation`, `structure`, `project`,
`workspaces`, `id_registry`, and the root) are closed, so an unknown key is an
error naming the typo and its JSON pointer; `task_registry`,
`custom_overrides`, and the `generated` / `documents` / `github_issues` maps
stay open because their keys are user or registry data.

## Step 2b — why the tracker is validated

`schemas/feature-tracker.schema.json` describes the tracker's shape, but
until the schema reconciliation nothing applied it — the file was consulted
by humans and by `get-validation-config.sh`'s enum read, and no run ever
validated a tracker against it. The same engine as Step 2a does both:
