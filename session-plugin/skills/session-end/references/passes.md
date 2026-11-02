# session-end — Passes

## The passes

| Pass | Skill | Captures |
|---|---|---|
| Wrap | `session-plugin:session-wrap --orchestrated` | Loose threads → taskwarrior, optional journal, GitHub issues, upstream issue/PR candidates |
| Distill | `session-plugin:session-distill --orchestrated` | Durable learnings → rules, skill updates, justfile recipes, process/methodology (script+recipe or project-local `.claude/skills/`) |
| Feedback | `feedback-plugin:feedback-session --confirmed` | Notable plugin/skill interactions → GitHub issues on claude-plugins |
| Taskwarrior sync | (inline, no sub-skill) | Session-linked tasks only: annotate, close with evidence, add follow-ups no open PR/issue already tracks; stable UUIDs. The untouched backlog gets one report line, never a walk |
| Blueprint tracker-sync | `blueprint-plugin:blueprint-feature-tracker-sync` | Drain closed WO-linked tasks from tracker `tasks.pending` → `tasks.completed` (`--drain-wave`) |
