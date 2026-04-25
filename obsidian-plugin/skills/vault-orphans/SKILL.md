---
created: 2026-04-17
modified: 2026-04-25
reviewed: 2026-04-25
name: vault-orphans
description: |
  Triage orphaned notes (zero incoming, zero outgoing wikilinks) in an
  Obsidian vault. Use when the user asks to find orphan notes, link
  disconnected notes into a MOC, distinguish expected orphans (inbox,
  daily notes) from meaningful ones, suggest archival for stale orphans,
  or reconnect isolated Zettelkasten notes to the knowledge graph.
user-invocable: false
allowed-tools: Read, Edit, Grep, Glob
---

# Orphan Triage

## When to Use This Skill

| Use this skill when... | Use the alternative instead when... |
|---|---|
| Triaging orphan notes (zero incoming, zero outgoing wikilinks) for archive vs. reconnect | Building a new MOC hub the orphans should link into — use `vault-mocs` |
| Distinguishing expected orphans (inbox, daily notes) from meaningful ones | Discovering the orphan list itself via the running CLI — use `search-discovery` |
| Suggesting archival paths for stale isolated Zettelkasten notes | Classifying or consolidating FVH/z redirect stubs — use `vault-stubs` |

An "orphan" is a note with no incoming wikilinks AND no outgoing wikilinks — disconnected from the knowledge graph. Some orphans are expected; others are the most productive places to add structure.

## Classes of Orphan

| Class | Where | Treat as |
|-------|-------|----------|
| Inbox items | `Inbox/*.md` | Expected; process via `/process-inbox` |
| Daily notes | `Notes/YYYY-MM-DD.md`, `FVH/notes/…` | Expected; they link out but rarely in |
| Standalone references | `Zettelkasten/*.md` with 0↔0 | **Meaningful** — add linkage |
| Kanban board notes | `Kanban/*.md` | Usually acceptable; boards are self-contained |
| Archive / logs | under `Archive/` subfolders | Expected; stale by design |

The vault-agent graph analyzer classifies each automatically.

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

## Related Skills

- **vault-mocs** — MOC conventions and when to create a new MOC
- **vault-wikilinks** — link syntax and safe-rewrite rules
- **search-discovery** — find-by-tag queries via Obsidian CLI
