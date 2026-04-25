---
created: 2026-04-17
modified: 2026-04-25
reviewed: 2026-04-25
name: vault-frontmatter
description: |
  Offline maintenance of YAML frontmatter in Obsidian notes. Use when the
  user asks to strip legacy `id:` fields, add missing frontmatter blocks,
  remove null tag values, clean up unrendered Templater markers like
  `{{title}}` or `<% tp.file.cursor() %>`, fix bare emoji placeholder tags,
  or add `context: fvh` to FVH notes in bulk.
user-invocable: false
allowed-tools: Read, Edit, Write, Grep, Glob
---

# Vault Frontmatter Maintenance

## When to Use This Skill

| Use this skill when... | Use the alternative instead when... |
|---|---|
| Bulk-stripping legacy `id:` fields or null `tags:` entries across many `.md` files offline | Setting a single property on one live note via the running CLI — use `properties` |
| Cleaning up unrendered `{{title}}` / `<% tp.file.cursor() %>` placeholders inside YAML | Repairing those markers in note **body** text — use `vault-templates` |
| Adding missing frontmatter blocks to notes that lack one | Consolidating the actual tag values once the YAML structure is sound — use `vault-tags` |

Offline, file-level repair of YAML frontmatter. Complements the `properties` skill (which uses the Obsidian CLI) by operating on .md files directly — safe for bulk mechanical passes.

## When to Use

- Stripping the legacy `id:` field from a batch of notes
- Removing unrendered Templater markers (`<% tp.file.cursor() %>`, `{{title}}`)
- Cleaning up `null` entries inside `tags:` lists
- Adding missing frontmatter blocks to notes that lack one
- Ensuring FVH notes carry `context: fvh`
- Normalizing tag case / pluralization drift

## Canonical Frontmatter Shape

```yaml
---
tags:
  - 🛠️/neovim       # emoji-prefixed category tag
  - 📝/notes         # note-type tag
context: fvh         # FVH notes only
---
```

Rules:
1. No `id:` field — removed from all current templates.
2. 2–3 tags per note; every tag either `emoji/subcategory` or a bare note-type like `📝/moc`.
3. No bare emoji placeholders (`📝`, `🌱`, `📝/🌱`) — they indicate the tag was never specified.
4. No `null` tag values — YAML must be valid.
5. FVH/* notes carry `context: fvh`; personal notes omit the field.

## Detection Patterns

| Issue | Grep pattern | Notes |
|-------|--------------|-------|
| Legacy `id:` | `^id:` inside frontmatter block | Strip entire line |
| Bare placeholder tag | YAML tag value exactly `📝`, `🌱`, or `📝/🌱` | Remove if note has other useful tags; else leave |
| Null tag | YAML tag value literally `null` | Remove list entry |
| Templater leak | `<% tp\.` or `\{\{title\}\}` or `\{\{date\}\}` | Replace `{{title}}` with filename stem; strip `<% tp.* %>` |
| Corrupt emoji | Tag contains Unicode replacement char `\ufffd` | Flag for manual fix — don't guess |
| Missing FVH context | File under `FVH/` without `context: fvh` | Add the line |

## Edit Recipes

### Strip legacy id
Before:
```yaml
---
id: 20240118235900
tags: [🛠️/neovim]
---
```
After:
```yaml
---
tags: [🛠️/neovim]
---
```

### Remove bare placeholder (keeping useful tags)
Before:
```yaml
tags:
  - 📝
  - 🛠️/ansible
```
After:
```yaml
tags:
  - 🛠️/ansible
```

### Legacy MOC tag → current
Before:
```yaml
tags:
  - 🗺️
```
After:
```yaml
tags:
  - 📝/moc
```

## Edit Pattern

Use `Edit` with small targeted `old_string` / `new_string` replacements that preserve exact indentation. Never rewrite whole files when a line edit suffices — it minimizes the commit diff and makes reviews easy.

For bulk fixes across many files, drive from a script that emits one `Edit` call per file rather than running `sed` in `Bash`. The commit-per-category pattern (`fix(tags): strip bare 📝 from 639 notes`) relies on keeping all edits in one logical batch.

## Safety

- Never write to `.obsidian/`, `.claude/`, `.git/`, `Files/`. The safety hook enforces this.
- Never add frontmatter to daily notes in `Notes/` or `FVH/notes/` without verifying — they often don't need any.
- When in doubt about what a placeholder tag meant, leave the note unchanged and report it rather than guess.

## Related Skills

- **properties** — runtime property ops via Obsidian CLI (requires running Obsidian)
- **vault-tags** — tag taxonomy consolidation rules
- **vault-templates** — Templater convention reference
