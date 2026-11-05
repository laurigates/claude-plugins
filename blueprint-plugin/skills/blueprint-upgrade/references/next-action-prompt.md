# blueprint-upgrade — Next-Action Prompt (Step 11)

Skipped when `$NONINTERACTIVE` is `true`.

   Otherwise, use AskUserQuestion:
   ```
   question: "Upgrade complete. What would you like to do next?"
   options:
     - label: "Check status (Recommended)"
       description: "Run /blueprint:status to see updated configuration"
     - label: "Regenerate rules from PRDs"
       description: "Update generated rules with new tracking"
     - label: "Update CLAUDE.md"
       description: "Reflect new architecture in project docs"
     - label: "Commit changes"
       description: "Stage and commit the migration"
   ```

   **Based on selection:**
   - "Check status" → Run `/blueprint:status`
   - "Regenerate rules" → Run `/blueprint:generate-rules`
   - "Update CLAUDE.md" → Run `/blueprint:claude-md`
   - "Commit changes" → Run `/git:commit` with migration message
