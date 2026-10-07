# feature-tracker-sync — AskUserQuestion Prompts (Full Sync Steps 5, 11)

## Step 5 — discrepancies

If discrepancies found (use AskUserQuestion):
```
question: "Found {N} discrepancies. How should they be resolved?"
options:
  - label: "Update tracker from TODO.md"
    description: "Trust TODO.md, update tracker to match"
  - label: "Update TODO.md from tracker"
    description: "Trust the tracker, update TODO.md to match"
  - label: "Review each discrepancy"
    description: "Show each discrepancy and decide individually"
  - label: "Skip - don't resolve discrepancies"
    description: "Report discrepancies but don't change anything"
```

## Step 11 — next action

Use AskUserQuestion:
```
question: "Sync complete. What would you like to do next?"
options:
  - label: "View detailed status"
    description: "Run /blueprint:feature-tracker-status for full breakdown"
  - label: "Continue development"
    description: "Run /project:continue to work on next task"
  - label: "I'm done"
    description: "Exit sync"
```
