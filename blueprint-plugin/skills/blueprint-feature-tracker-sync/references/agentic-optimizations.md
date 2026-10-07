# feature-tracker-sync — Agentic Optimizations

| Context | Command |
|---------|---------|
| Verify tracker integrity (read-only, no writes) | `bash "${CLAUDE_SKILL_DIR}/../../scripts/blueprint-tracker-check.sh" --project-dir "$(pwd)"` |
| Integrity roll-up only (two lines) | `bash "${CLAUDE_SKILL_DIR}/../../scripts/blueprint-tracker-check.sh" \| grep -E '^(STATUS\|ISSUE_COUNT)='` |
| Just the recomputed-vs-cached statistics | `bash "${CLAUDE_SKILL_DIR}/../../scripts/blueprint-tracker-check.sh" \| grep -E '^(EXPECTED\|ACTUAL)_'` |
| Sync core without writing | `bash "${CLAUDE_SKILL_DIR}/scripts/blueprint-feature-tracker-sync.sh" --project-dir "$(pwd)" --dry-run` |
| Progress summary, stdout only | `/blueprint:feature-tracker-sync --summary` |

The integrity check exits 0 on `OK`/`WARN` and 1 on `ERROR`, so it is
parallel-batch-safe and usable as a pre-commit or CI gate.
