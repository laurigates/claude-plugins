---
created: 2026-04-17
modified: 2026-04-17
reviewed: 2026-04-17
name: vault-mocs
description: |
  Map-of-Content (MOC) curation for Obsidian vaults. Covers MOC
  conventions (`📝/moc` tag, section structure), coverage analysis
  (which notes are orphaned from a MOC), and when to create a new MOC
  vs. extend an existing one.
user-invocable: false
allowed-tools: Read, Edit, Write, Grep, Glob
---

# MOC Curation

A Map of Content (MOC) is a structured hub note that organizes related content via wikilinks. It's the primary navigation surface of a mature Obsidian vault — more useful than tags, more discoverable than search.

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
2. File lives in `Zettelkasten/` (personal) or `FVH/MOC/` (work).
3. Filename is `{Subject} MOC.md` — suffix, not prefix.
4. Body has a one-paragraph description, then `##` section headings, then bullet-list wikilinks.
5. Never has `id:` or other legacy frontmatter.

## Legacy MOC Fixups

| Issue | Fix |
|-------|-----|
| `tags: 🗺️` | Rewrite to `tags: [📝/moc]` |
| `tags: [🗺, 📝/moc]` | Deduplicate to `tags: [📝/moc]` |
| MOC in `FVH/z/` instead of `FVH/MOC/` | Move file |
| Uses `[[Kanban/Foo]]` path-qualified links | Rewrite to `[[Foo]]` when basename unique |

## Coverage Analysis

For each tag category (`🛠️/`, `🔌/`, `💻/`, etc.), the vault-agent `mocs.analyze_mocs` analyzer reports how many tagged notes are NOT linked from any MOC. High uncovered counts indicate:

- **Missing MOC** — the category has 10+ notes but no MOC exists.
- **Stale MOC** — the MOC exists but hasn't been updated with recent additions.
- **Tag mismatch** — notes are tagged but don't belong in the relevant MOC.

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
| Fixup tag | `fix(mocs): 🗺️ → 📝/moc on FVH MOCs` |
| Add orphans | `feat(mocs): link 12 notes into Neovim MOC` |
| Rewrite path-qualified link | `fix(mocs): unqualify [[Kanban/X]] → [[X]] across 6 MOCs` |

## Safety

- Never modify a MOC's section structure without the user's input — they reflect the user's mental model.
- When adding links, preserve the user's existing sort order (alphabetical, chronological, by-importance — look at the first section to infer).
- Don't link notes that are tagged but clearly off-topic for the MOC.

## Related Skills

- **vault-orphans** — identifies candidate notes to add to MOCs
- **vault-tags** — tag taxonomy that drives coverage analysis
- **vault-wikilinks** — link syntax and safe-rewrite rules
