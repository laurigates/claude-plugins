## vault-frontmatter

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

---

## vault-tags

# Vault Tag Taxonomy


## Canonical Categories

| Emoji | Category | Examples |
|-------|----------|----------|
| `🛠️` | Development tools | `🛠️/neovim`, `🛠️/git`, `🛠️/terminal` |
| `💻` | Programming languages | `💻/python`, `💻/rust`, `💻/typescript` |
| `☁️` | Systems & infrastructure | `☁️/kubernetes`, `☁️/docker`, `☁️/linux` |
| `🔌` | Hardware & IoT | `🔌/esp32`, `🔌/arduino`, `🔌/electronics` |
| `🏠` | Home automation | `🏠/home-assistant`, `🏠/esphome` |
| `🎮` | Entertainment | `🎮/games`, `🎮/tabletop` |
| `🤖` | AI & ML | `🤖/comfyui`, `🤖/llm`, `🤖/ai-tools` |


### Note-Type Tags

| Tag | Meaning |
|-----|---------|
| `📝/moc` | Map of Content |
| `📝/notes` | General note |
| `📝/collection` | Resource collection |
| `📝/guide` | How-to guide |
| `📋/reference` | Quick reference material |
| `📋/commands` | Command-line reference |
| `📅/daily` | Daily note |


## Consolidation Table

When auditing reveals duplicate or drifted tags, apply these rewrites:

| Drift / Legacy | Canonical | Reason |
|----------------|-----------|--------|
| `🗺️` | `📝/moc` | Old MOC marker |
| `🔒/security` | `🔍/security` | Standardize on search emoji |
| `🎨/comfyui` | `🤖/comfyui` | ComfyUI lives under AI |
| `gaming` | `🎮/games` | Flat → emoji-prefixed |
| `neovim` (flat) | `🛠️/neovim` | Flat → emoji-prefixed |
| `softwaredevelopment` | `💻/development` | Concatenated → slash |
| `project` / `projects` | `💡/project` | Pick one plural form |
| `Hardware` (title-cased) | `🔌/hardware` | Lowercase, emoji-prefixed |


## Bare Placeholder Tags

The tags `📝`, `🌱`, `📝/🌱` are no-ops left over from unfinished template rendering. Treatment:

- If the note has **other useful tags**, remove the placeholder.
- If the note has **only** a placeholder, leave it flagged for manual review — removing would leave the note untagged, which is a different (but real) problem.


## Over-Tagging

More than 5 tags suggests the note mixes topics and should be split, or that tags are being used as keywords. Bring it down to 2–3 by asking "what single category is this note about?" — the rest go in the body as text.


## Detection

```bash

# Notes with a bare 📝 or 🌱 tag on its own line
rg -l '^\s*-\s+(📝|🌱|📝/🌱)\s*$' --glob '*.md'


# Notes with competing security prefixes
rg -l '🔒/security' --glob '*.md'
rg -l '🔍/security' --glob '*.md'


# Flat (non-emoji-prefix) tags
rg '^\s*-\s+[a-z][a-z0-9_-]+\s*$' --glob '*.md'
```


## Offline Fallback (App Closed)

The detection methodology above is unchanged — only the **data source** changes when Obsidian (and its `obsidian` CLI / live tag index) is closed. The `obsidian tags`/`tag` queries in `search-discovery` are the **live-index** path; parsing the `.md` corpus directly with the `rg` Detection snippets above is the **deterministic headless default**, and for batch/scheduled audits it is often the better choice (reproducible, free of app/index state). `vault-frontmatter` already operates this way.

Tag taxonomy is pure frontmatter — read each note's YAML block between the leading `---` fences and extract `tags` (and `aliases` / `context` where relevant); see `vault-frontmatter` for YAML-block mechanics. The consolidation and bare-placeholder passes need no running app: the `rg` snippets above read tags straight from the files.


## Edit Pattern

For each note, use `Edit` with a small `old_string` / `new_string` that touches only the affected tag lines. Preserve indentation and the rest of the frontmatter block exactly.

When renaming a tag across the whole vault, batch into one commit titled `fix(tags): consolidate 🔒/security → 🔍/security (N notes)`.


## Anti-Patterns

- Do **not** invent new categories. Use the table above; propose additions via a conventional commit if truly needed.
- Do **not** use spaces inside tag values (`AI tools` → `🤖/ai-tools`).
- Do **not** use multiple emoji in one tag (`🛠️🔌/esp32` — pick one).
- Do **not** add tags purely for search — search works on content and filenames already.

---

## vault-templates

# Templater Convention & Drift Repair


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

Before (file `work/notes/2025-03-26.md`):
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
| `Work Daily.md` | `work/notes/YYYY-MM-DD.md` | Log, Thoughts, Discoveries, Todo, Recurring reminders |


## Daily Note Structure Drift

Personal daily notes created before 2025 usually lack `## Navigation` and `## Tomorrow's Prep`. Two remediation options:

1. **Retrofit template** — add the missing sections to every old daily note. Usually not worth the diff; users rarely look at old daily notes.
2. **Leave as-is** — document the change boundary in a single commit message and let old notes age.

Default to #2 unless the user specifically asks for retrofit.


## Work Daily Note Drift

Work-namespace daily notes that contain literal `{{title}}` in the heading — fix these.


## Safety

- Never edit `Templates/*.md` when fixing leakage — templates are supposed to contain Templater syntax.
- Never run a blanket `sed -i 's/{{title}}/.../'` — always use file-specific `Edit` calls so the title derivation is correct per file.
- When you encounter `<% tp.system.prompt(...) %>`, don't guess the answer — flag for user.
