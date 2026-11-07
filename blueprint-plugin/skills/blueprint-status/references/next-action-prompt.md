# blueprint-status — Next-Action Prompt (Step 8)

The AskUserQuestion option list for Step 8. Skipped under `--report-only`.
The selection-to-command map stays in `SKILL.md` Step 8.

## Which options to include

Build options dynamically from the state found in Steps 2-6:

- If upgrade available → Include "Upgrade to v{latest}"
- If modified content → Include "Sync generated content"
- If stale content → Include "Regenerate skills"
- If PRDs exist but no generated skills → Include "Generate skills from PRDs"
- If skills exist but no commands → Include "Generate workflow commands"
- If CLAUDE.md stale → Include "Update CLAUDE.md"
- If feature tracker exists but stale → Include "Sync feature tracker"
- If ADRs have potential issues → Include "Validate ADRs"
- If documents without IDs → Include "Sync document IDs"
- If orphan documents/issues → Include "Link documents to GitHub"
- If overdue tasks exist → Include "Run overdue maintenance tasks"
- Always include "Continue development" and "I'm done"

## Option list

   ```
   question: "What would you like to do?"
   options:
     # Dynamic - include based on state detected above
     - label: "Upgrade to v{latest}" (if upgrade available)
       description: "Upgrade blueprint format to latest version"
     - label: "Sync generated content" (if modified)
       description: "Review changes to generated skills/commands"
     - label: "Regenerate from PRDs" (if stale)
       description: "Update generated content from changed PRDs"
     - label: "Generate rules from PRDs" (if PRDs exist, no rules)
       description: "Extract project-specific rules from your PRDs"
     - label: "Update CLAUDE.md" (if stale or missing)
       description: "Regenerate project overview document"
     - label: "Sync feature tracker" (if feature tracker stale)
       description: "Synchronize tracker with TODO.md"
     - label: "Validate ADRs" (if ADR issues detected)
       description: "Check ADR relationships, conflicts, and missing links"
     - label: "Sync document IDs" (if documents without IDs)
       description: "Assign IDs to all documents missing them"
     - label: "Link documents to GitHub" (if orphans exist)
       description: "Create/link GitHub issues for orphan documents"
     - label: "Run overdue tasks ({N} due)" (if overdue tasks exist)
       description: "Execute overdue maintenance tasks"
     # Always include these:
     - label: "Continue development"
       description: "Run /project:continue to work on next task"
     - label: "I'm done for now"
       description: "Exit status check"
   ```
