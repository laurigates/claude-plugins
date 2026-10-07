# story-audit — Step 7 Task-Registry Update

```bash
jq --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
   --arg result "${AUDIT_RESULT:-success}" \
   --argjson stories "${STORY_COUNT:-0}" \
   --argjson gaps "${TIER1_GAP_COUNT:-0}" \
   '.task_registry["story-audit"].last_completed_at = $now |
    .task_registry["story-audit"].last_result = $result |
    .task_registry["story-audit"].stats.runs_total = ((.task_registry["story-audit"].stats.runs_total // 0) + 1) |
    .task_registry["story-audit"].stats.items_processed = $stories |
    .task_registry["story-audit"].stats.tier1_gaps = $gaps' \
   docs/blueprint/manifest.json > docs/blueprint/manifest.json.tmp \
   && mv docs/blueprint/manifest.json.tmp docs/blueprint/manifest.json
```

Where `AUDIT_RESULT` is `"success"`, `"{N} drift entries"`, or `"failed: {reason}"`.
