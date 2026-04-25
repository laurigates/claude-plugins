---
created: 2026-04-17
modified: 2026-04-25
reviewed: 2026-04-25
name: vault-templates
description: |
  Obsidian Templater conventions and drift repair. Use when the user asks
  to fix unrendered Templater markers like `<% tp.file.cursor() %>`,
  replace `{{title}}` or `{{date}}` placeholders in daily notes, clean up
  notes committed before Templater finished running, or audit daily-note
  structure drift against the canonical template.
user-invocable: false
allowed-tools: Read, Edit, Write, Grep, Glob
---

# Templater Convention & Drift Repair

## When to Use This Skill

| Use this skill when... | Use the alternative instead when... |
|---|---|
| Repairing unrendered `<% tp.file.cursor() %>` / `{{title}}` markers committed in note **bodies** | Stripping the same kind of markers inside YAML frontmatter — use `vault-frontmatter` |
| Auditing daily-note structure drift against the canonical Templater template | Creating new daily notes interactively via the running CLI — use `vault-files` |
| Fixing notes committed before Templater finished rendering | Reconnecting the cleaned-up notes into a hub afterwards — use `vault-mocs` |

Obsidian's Templater plugin renders placeholder syntax when a new note is created. When rendering fails (plugin error, user dismissal, manual copy-paste), the literal markers get committed and persist. Fixing them is mechanical.

## Unrendered Markers

| Marker | Meaning | Fix |
|--------|---------|-----|
| `<% tp.file.cursor(N) %>` | Cursor position placeholder | Strip the entire tag |
| `<% tp.file.title %>` | Filename stem | Replace with actual filename (no `.md`) |
| `<% tp.date.now("YYYY-MM-DD") %>` | Today's date | Replace with the creation date from frontmatter, or the filename date for daily notes |
| `{{title}}` | Filename stem (legacy) | Replace with filename stem |
| `{{date}}` | Today's date (legacy) | Same as above |
| `<% await tp.system.prompt(...) %>` | User prompt | Strip; requires user to refill |

## Detection

```bash
# Find any Templater leak
rg '<%\s*tp\.' --glob '*.md'
rg '\{\{title\}\}|\{\{date\}\}' --glob '*.md'
```

## Fixing `<% tp.file.cursor(1) %>`

Before:
```markdown
---
tags: [📝/notes]
---

<% tp.file.cursor(1) %>
```

After:
```markdown
---
tags: [📝/notes]
---
```

Use `Edit` with `old_string='\n\n<% tp.file.cursor(1) %>'` and `new_string=''` (or adjust for trailing whitespace) — the cursor marker never has meaningful content around it.

## Fixing `{{title}}` in daily notes

Before (file `FVH/notes/2025-03-26.md`):
```markdown
# {{title}}

## Log
```

After:
```markdown
# 2025-03-26

## Log
```

Use the filename stem (no `.md`). Don't replace `{{title}}` inside code blocks or quoted text — only in headings / body.

## Canonical Template Files

The templates themselves live in `Templates/` and should contain raw Templater syntax — never "fix" them. Only fix notes outside `Templates/`.

| Template | Produces | Sections |
|----------|----------|----------|
| `Daily.md` | `Notes/YYYY-MM-DD.md` | Quick Links, Today's Focus, Work, Personal, Tomorrow's Prep, Navigation |
| `MOC.md` | `Zettelkasten/{Subject} MOC.md` | Title heading + sections |
| `New.md` | general Zettelkasten notes | Frontmatter + body stub |
| `FVH Daily.md` | `FVH/notes/YYYY-MM-DD.md` | Log, Thoughts, Discoveries, Todo, Recurring reminders |

## Daily Note Structure Drift

Personal daily notes created before 2025 usually lack `## Navigation` and `## Tomorrow's Prep`. Two remediation options:

1. **Retrofit template** — add the missing sections to every old daily note. Usually not worth the diff; users rarely look at old daily notes.
2. **Leave as-is** — document the change boundary in a single commit message and let old notes age.

Default to #2 unless the user specifically asks for retrofit.

## FVH Daily Note Drift

7 FVH daily notes contain literal `{{title}}` in the heading — fix these.

## Safety

- Never edit `Templates/*.md` when fixing leakage — templates are supposed to contain Templater syntax.
- Never run a blanket `sed -i 's/{{title}}/.../'` — always use file-specific `Edit` calls so the title derivation is correct per file.
- When you encounter `<% tp.system.prompt(...) %>`, don't guess the answer — flag for user.

## Related Skills

- **vault-frontmatter** — YAML-level fixes
- **vault-files** — daily-note operations via Obsidian CLI
