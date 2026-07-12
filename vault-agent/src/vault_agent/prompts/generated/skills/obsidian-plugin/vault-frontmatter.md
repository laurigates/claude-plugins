# Vault Frontmatter Maintenance


## Canonical Frontmatter Shape

```yaml
---
tags:
  - 🛠️/neovim       # emoji-prefixed category tag
  - 📝/notes         # note-type tag
context: work        # work-namespace notes only
---
```

Rules:
1. No `id:` field — removed from all current templates.
2. 2–3 tags per note; every tag either `emoji/subcategory` or a bare note-type like `📝/moc`.
3. No bare emoji placeholders (`📝`, `🌱`, `📝/🌱`) — they indicate the tag was never specified.
4. No `null` tag values — YAML must be valid.
5. Work-namespace notes (e.g. under `work/`) carry `context: work`; personal notes omit the field.


## Detection Patterns

| Issue | Grep pattern | Notes |
|-------|--------------|-------|
| Legacy `id:` | `^id:` inside frontmatter block | Strip entire line |
| Bare placeholder tag | YAML tag value exactly `📝`, `🌱`, or `📝/🌱` | Remove if note has other useful tags; else leave |
| Null tag | YAML tag value literally `null` | Remove list entry |
| Templater leak | `<% tp\.` or `\{\{title\}\}` or `\{\{date\}\}` | Replace `{{title}}` with filename stem; strip `<% tp.* %>` |
| Corrupt emoji | Tag contains Unicode replacement char `\ufffd` | Flag for manual fix — don't guess |
| Missing work context | File under the work namespace (e.g. `work/`) without `context: work` | Add the line |


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
- Never add frontmatter to daily notes in `Notes/` or `work/notes/` without verifying — they often don't need any.
- When in doubt about what a placeholder tag meant, leave the note unchanged and report it rather than guess.