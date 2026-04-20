---
created: 2026-04-17
modified: 2026-04-19
reviewed: 2026-04-17
name: vault-tags
description: |
  Emoji-prefixed tag taxonomy for Obsidian vaults. Use when the user asks
  to consolidate duplicate or drifted tags (e.g. `🔒/security` vs
  `🔍/security`, `gaming` vs `🎮/games`), collapse bare emoji placeholder
  tags like `📝` or `🌱`, convert flat tags to emoji-prefixed form, or
  reduce over-tagged notes down to the 2-3 canonical tags.
user-invocable: false
allowed-tools: Read, Edit, Grep, Glob
---

# Vault Tag Taxonomy

A two-level tag scheme built around emoji-prefixed categories. Consistent tagging enables reliable search (`tag:#🛠️/neovim`), Dataview queries, and MOC coverage analysis.

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

## Edit Pattern

For each note, use `Edit` with a small `old_string` / `new_string` that touches only the affected tag lines. Preserve indentation and the rest of the frontmatter block exactly.

When renaming a tag across the whole vault, batch into one commit titled `fix(tags): consolidate 🔒/security → 🔍/security (N notes)`.

## Anti-Patterns

- Do **not** invent new categories. Use the table above; propose additions via a conventional commit if truly needed.
- Do **not** use spaces inside tag values (`AI tools` → `🤖/ai-tools`).
- Do **not** use multiple emoji in one tag (`🛠️🔌/esp32` — pick one).
- Do **not** add tags purely for search — search works on content and filenames already.

## Related Skills

- **vault-frontmatter** — general YAML repair patterns
- **vault-mocs** — how tag categories relate to MOCs
- **search-discovery** — runtime tag queries via Obsidian CLI
