# session-end — Passes

## The passes

| Pass | Skill | Captures |
|---|---|---|
| Wrap | `session-plugin:session-wrap` | Loose threads → taskwarrior, optional journal, GitHub issues, upstream issue/PR candidates |
| Distill | `session-plugin:session-distill` | Durable learnings → rules, skill updates, justfile recipes, process/methodology (script+recipe or project-local `.claude/skills/`) |
| Feedback | `feedback-plugin:feedback-session` | Notable plugin/skill interactions → GitHub issues on claude-plugins |
| Taskwarrior sync | (inline, no sub-skill) | Close done tasks, update statuses, add follow-ups no open PR/issue already tracks; uses stable UUIDs |
| Blueprint tracker-sync | `blueprint-plugin:blueprint-feature-tracker-sync` | Drain closed WO-linked tasks from tracker `tasks.pending` → `tasks.completed` (`--drain-wave`) |
