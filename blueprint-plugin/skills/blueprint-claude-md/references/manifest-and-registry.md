# blueprint-claude-md — Manifest and Task Registry

The bookkeeping every run records before its report. Entry point:
[`../SKILL.md`](../SKILL.md) § Step 9.

## Update the manifest

- Record CLAUDE.md generation/update
- Track which PRDs contributed
- Update timestamp

## Update the task registry

Update the task registry entry in `docs/blueprint/manifest.json`:

```bash
jq --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '.task_registry["claude-md"].last_completed_at = $now |
   .task_registry["claude-md"].last_result = "success" |
   .task_registry["claude-md"].stats.runs_total = ((.task_registry["claude-md"].stats.runs_total // 0) + 1)' \
  docs/blueprint/manifest.json > tmp.json && mv tmp.json docs/blueprint/manifest.json
```
