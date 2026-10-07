# feature-tracker-sync — Generate Summary (`--summary`)

The `jq` program that renders the read-only progress report.

```bash
jq -r '
  "# Work Overview: \(.project)\n\n" +
  "## Current Phase: \(.current_phase // "Not set")\n\n" +
  "**Progress**: \(.statistics.complete)/\(.statistics.total_features) features (\(.statistics.completion_percentage)%)\n\n" +
  "### In Progress\n" +
  (if (.tasks.in_progress | length) == 0 then "- (none)\n" else (.tasks.in_progress | map("- \(.description) [\(.id)]") | join("\n")) + "\n" end) +
  "\n### Pending\n" +
  (if (.tasks.pending | length) == 0 then "- (none)\n" else (.tasks.pending | map("- \(.description) [\(.id)]") | join("\n")) + "\n" end) +
  "\n### Recently Completed\n" +
  (if (.tasks.completed | length) == 0 then "- (none)\n" else (.tasks.completed | map("- \(.description) [\(.id)]") | join("\n")) + "\n" end) +
  "\n## Phase Status\n" +
  (.phases | map("- \(.name): \(.status)") | join("\n"))
' docs/blueprint/feature-tracker.json
```
