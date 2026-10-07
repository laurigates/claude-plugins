# session-wrap — Configuration

## Lookup order

Read per-user/per-project config before doing anything:

1. `.claude/session-plugin.local.md` in the project (wins)
2. `~/.claude/session-plugin.local.md` (user-global fallback)
3. Neither exists → taskwarrior + GitHub-issue destinations only; no journal

## What the config carries

YAML frontmatter carries the journal settings (`journal`, `journal_path`,
`journal_template`, heading targets, `journal_scopes`); the markdown body
carries freeform scope-detection heuristics and the user's taskwarrior
project-naming map — read it and apply it as context. Full schema and a
worked example: [REFERENCE.md](../REFERENCE.md).
