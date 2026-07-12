## vault-mocs

# MOC Curation


## Canonical MOC Shape

```markdown
---
tags: [📝/moc]
---


# Neovim MOC

Central hub for Neovim configuration, plugins, and workflows.


## Core

- [[Neovim]] — base configuration
- [[Lazy.nvim]] — plugin management


## Plugins

- [[nvim-treesitter]]
- [[Mason LSP]]


## Keybindings and Workflow

- [[Neovim Keybindings]]
- [[Neovim Session Management]]
```

Rules:
1. Tag is **exactly** `📝/moc` — not `🗺️` (legacy), not `MOC` (flat), not `📝/MOC` (wrong case).
2. File lives in `Zettelkasten/` (personal) or `work/MOC/` (work).
3. Filename is `{Subject} MOC.md` — suffix, not prefix.
4. Body has a one-paragraph description, then `##` section headings, then bullet-list wikilinks.
5. Never has `id:` or other legacy frontmatter.


## Legacy MOC Fixups

| Issue | Fix |
|-------|-----|
| `tags: 🗺️` | Rewrite to `tags: [📝/moc]` |
| `tags: [🗺, 📝/moc]` | Deduplicate to `tags: [📝/moc]` |
| MOC in `work/z/` instead of `work/MOC/` | Move file |
| Uses `[[Kanban/Foo]]` path-qualified links | Rewrite to `[[Foo]]` when basename unique |


## Coverage Analysis

For each tag category (`🛠️/`, `🔌/`, `💻/`, etc.), the vault-agent `mocs.analyze_mocs` analyzer reports how many tagged notes are NOT linked from any MOC. High uncovered counts indicate:

- **Missing MOC** — the category has 10+ notes but no MOC exists.
- **Stale MOC** — the MOC exists but hasn't been updated with recent additions.
- **Tag mismatch** — notes are tagged but don't belong in the relevant MOC.


## Offline Fallback (App Closed)

The detection methodology above is unchanged — only the **data source** changes when Obsidian (and its `obsidian` CLI / live link index) is closed. The `obsidian` CLI and `vault-agent` analyzers are the **live-index** path; parsing the `.md` corpus directly with Glob/Grep is the **deterministic headless default**, and for batch/scheduled audits it is often the better choice (reproducible, free of app/index state). `vault-frontmatter` already operates this way.

Parse the corpus directly:

- **Frontmatter** — read each note's YAML block between the leading `---` fences; extract `tags`, `aliases`, `context`. See `vault-frontmatter` for YAML-block mechanics.
- **Wikilinks** — match `[[Target]]`, `[[Target|Alias]]`, `[[Target#Heading]]`, `[[folder/Target]]`, and `![[embed]]`. Resolve each target to a note by **basename**, then **relative path**, then **alias** (from frontmatter), all **case-insensitive**. Resolve `![[embed]]` against attachments as well as notes — the attachment folder is per-vault configurable, so read it from `.obsidian/app.json` (`attachmentFolderPath`) and fall back to the vault root / `Files/` only when that key is unset.

Coverage analysis offline: for each tag category, count notes whose parsed frontmatter `tags` place them in the category but which no `📝/moc`-tagged note links to (via the resolution cascade). That is the same uncovered count `mocs.analyze_mocs` produces from the live index.


## Creating a New MOC

Thresholds (heuristic):
- ≥ 10 tagged notes in the category AND
- No existing MOC covers them AND
- Notes share enough subject to belong in one hub

If all three hold, create `Zettelkasten/{Category} MOC.md`:

```markdown
---
tags: [📝/moc]
---


# {Category} MOC

{One-paragraph framing of the category.}


## {Section}

- [[Note1]]
- [[Note2]]
```

Pick 2–4 `##` sections that reflect natural groupings within the notes — don't force a deep hierarchy.


## Extending an Existing MOC

When the analyzer reports orphaned notes that belong in an existing MOC:

1. Read the MOC and find the most appropriate `##` section (or create a new one if 3+ notes fit a new grouping).
2. Add wikilinks one per bullet, alphabetical within the section.
3. Keep descriptions brief — one short phrase per link at most.

Don't add a "See also" or "Random" section as a dumping ground. If a note doesn't fit any section, reconsider whether it belongs in this MOC at all.


## Never Do

- **Don't create nested MOCs** (MOC of MOCs) unless the vault has 20+ MOCs that justify a top-level index.
- **Don't dataview-generate MOC content** in place of hand-curated links. Dataview is fine for supplementary sections ("Recent notes in this category"), but the primary content should be hand-picked.
- **Don't add the `📝/moc` tag to a note that isn't actually a MOC** — it pollutes MOC inventories.
- **Don't rename existing MOCs** without updating every link (use `vault-wikilinks` rewrite patterns).


## Commit Messages

| Action | Commit |
|--------|--------|
| New MOC | `feat(mocs): add {Category} MOC covering N notes` |
| Fixup tag | `fix(mocs): 🗺️ → 📝/moc on work MOCs` |
| Add orphans | `feat(mocs): link 12 notes into Neovim MOC` |
| Rewrite path-qualified link | `fix(mocs): unqualify [[Kanban/X]] → [[X]] across 6 MOCs` |


## Safety

- Never modify a MOC's section structure without the user's input — they reflect the user's mental model.
- When adding links, preserve the user's existing sort order (alphabetical, chronological, by-importance — look at the first section to infer).
- Don't link notes that are tagged but clearly off-topic for the MOC.

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

## vault-orphans

# Orphan Triage


## Classes of Orphan

| Class | Where | Treat as |
|-------|-------|----------|
| Inbox items | `Inbox/*.md` | Expected; process via `/process-inbox` |
| Daily notes | `Notes/YYYY-MM-DD.md`, `work/notes/…` | Expected; they link out but rarely in |
| Standalone references | `Zettelkasten/*.md` with 0↔0 | **Meaningful** — add linkage |
| Kanban board notes | `Kanban/*.md` | Usually acceptable; boards are self-contained |
| Archive / logs | under `Archive/` subfolders | Expected; stale by design |

The vault-agent graph analyzer classifies each automatically.


## Offline Fallback (App Closed)

The detection methodology above is unchanged — only the **data source** changes when Obsidian (and its `obsidian` CLI / live link index) is closed. The `obsidian` CLI and `vault-agent` analyzers are the **live-index** path; parsing the `.md` corpus directly with Glob/Grep is the **deterministic headless default**, and for batch/scheduled audits it is often the better choice (reproducible, free of app/index state). `vault-frontmatter` already operates this way.

Parse the corpus directly:

- **Frontmatter** — read each note's YAML block between the leading `---` fences; extract `tags`, `aliases`, `context`. See `vault-frontmatter` for YAML-block mechanics.
- **Wikilinks** — match `[[Target]]`, `[[Target|Alias]]`, `[[Target#Heading]]`, `[[folder/Target]]`, and `![[embed]]`. Resolve each target to a note by **basename**, then **relative path**, then **alias** (from frontmatter), all **case-insensitive**. Resolve `![[embed]]` against attachments as well as notes — the attachment folder is per-vault configurable, so read it from `.obsidian/app.json` (`attachmentFolderPath`) and fall back to the vault root / `Files/` only when that key is unset.

Build the link graph from the resolved wikilinks: a note is an orphan when no resolved link targets it (zero incoming) **and** it emits no link that resolves (zero outgoing). The class table above (Inbox / daily / Archive) is path-derived and works identically offline.


## Triage Workflow

For each meaningful orphan:

1. **Read the note** — is the content still relevant, or is this old/dead content?
2. **Identify its primary category** — by tag (e.g., `🛠️/neovim` → Neovim MOC) or by title.
3. **Pick ONE action:**
   - **Link from a MOC** — add `[[Note]]` to the appropriate MOC under the right section
   - **Add an inbound link** from a closely related note
   - **Archive** — move to an `Archive/` subfolder if no longer useful
   - **Delete** — only if empty or entirely superseded


## Never Do

- **Don't add dummy links** like "See also: [[Random]]" just to take the note off the orphan list. That's link pollution.
- **Don't create a new MOC** just to absorb one orphan — see `vault-mocs` for thresholds.
- **Don't assume empty = orphan** — some orphans have substantive content that simply wasn't linked.


## Linking Heuristics

When adding a note to a MOC, match on:

1. **Primary tag category** — a note tagged `🛠️/neovim` belongs in the Neovim MOC.
2. **Content topic** — read the first paragraph; pick the MOC that covers that subject.
3. **Existing cluster** — if notes `A`, `B`, `C` all link to each other but none link from a MOC, add the whole cluster to the MOC under one section heading.


## MOC Section Placement

MOCs typically have sections like `## Core Concepts`, `## Tools`, `## Specific Configurations`. Pick the most specific section that fits; create a new `## Something` section only if 3+ notes fall under the same new heading.


## Batch Pattern

Never modify 100+ MOC links in one commit — that's unreviewable. Use one commit per MOC:

```
feat(mocs): link 12 orphaned CLI tool notes into new CLI Tools MOC
```


## Safety

- If a note is substantive and the user's writing style suggests it was important, lean toward linking rather than deleting.
- If tags are contradictory or missing, link to a broader MOC rather than guessing a specific one.
- Preserve any existing heading structure in the MOC when inserting links.
