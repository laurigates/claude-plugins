# session-distill — Command Forms

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Distill collector (recipe candidates + hot files + process groupings) | `bash "${CLAUDE_SKILL_DIR}/../../scripts/distill-survey.sh" --session-id "${CLAUDE_SESSION_ID}"` |
| Distill qualify signal (counts only) | `bash "${CLAUDE_SKILL_DIR}/../../scripts/distill-survey.sh" --session-id "${CLAUDE_SESSION_ID}" --summary` |
| Session diff summary | `git log --stat --oneline --max-count=10` |
| Recent commits | `git log --oneline --max-count=20` |
| List justfile recipes | `just --list` |
| Dump justfile as JSON | `just --dump --dump-format json` |
| Find rules | Glob `.claude/rules/*.md` |
| Batch-read all rules | Glob then Read all results in one response |
