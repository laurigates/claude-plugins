# blueprint-upgrade — Non-Interactive Defaults (`--non-interactive` / `-y`)

Read this file only when `$NONINTERACTIVE` is `true`. Use these answers without prompting, and record each one in `upgrade_history[].changes` as "auto-selected in non-interactive mode":

| Decision point | Step | Default | Rationale |
|---|---|---|---|
| Remove deprecated generated commands | 3 | "Yes, remove" | Matches "Recommended" option; the files are known-obsolete |
| Task-registry scheduling mode | 3a | "Prompt before running" | Safest; preserves pre-existing behaviour for all tasks |
| Upgrade confirmation | 5 | "Yes, upgrade now" | The flag is explicit consent; skip the confirmation gate |
| Enable document detection (v1.x→v2.0) | 7f | "No, keep manual commands only" | Additive feature; do not silently change behaviour in batch mode |
| Migrate root documentation (v1.x→v2.0) | 7g | "No, leave in root" | Least destructive; moving root docs is reversible but surprising |
| Post-upgrade next action | 11 | Skip — report and exit | The caller is responsible for follow-up in a batch context |
| Modification preservation (v2.x→v3.0, `migrations/v2.x-to-v3.0.md`) | 6 | "Keep modifications" | Never discard user-edited content in batch mode, and never "Cancel migration" silently |

A migration step that needs a prompt this table does not list aborts the upgrade (see the Parameters section of `SKILL.md`).
