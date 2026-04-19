---
created: 2026-04-17
modified: 2026-04-19
reviewed: 2026-04-17
name: vault-wikilinks
description: |
  Detect and repair broken wikilinks in an Obsidian vault. Use when the
  user asks to fix broken `[[Target]]` links, rewrite a renamed note's
  references across the vault, resolve cross-namespace ambiguity between
  Zettelkasten and FVH/z notes, unqualify `[[Kanban/X]]` path-qualified
  links, or clean up wikilinks after renaming notes.
user-invocable: false
allowed-tools: Read, Edit, Grep, Glob
---

# Wikilink Integrity

Obsidian resolves `[[Target]]` by looking for a note whose basename is `Target.md` anywhere in the vault. Links break silently when a note is renamed, moved, or was never created. Ambiguity arises when two notes share a basename.

## Link Syntax

```markdown
[[Note Name]]                      # basename resolution
[[Note Name|Alias]]                # custom display text
[[Note Name#Section heading]]      # deep link to heading
[[folder/Note Name]]               # path-qualified (usually unnecessary)
![[Image.png]]                     # embed (image, note, PDF)
```

## Resolution Rules

1. **Unqualified target** (`[[Docker]]`) resolves to any note with basename `Docker.md`. If two exist (e.g. `Zettelkasten/Docker.md` and `FVH/z/Docker.md`), Obsidian picks one non-deterministically — ambiguous.
2. **Path-qualified target** (`[[Kanban/Main]]`) resolves to `Kanban/Main.md` exactly — no basename fallback.
3. **Embeds** (`![[X]]`) follow the same resolution. Image embeds typically target files under `Files/`.

## Common Breakage Patterns

| Pattern | Fix |
|---------|-----|
| `[[AnsibleFVH]]` × many → note doesn't exist | Rewrite to `[[Ansible]]` (the actual note) |
| `[[Development MOC]]` → note was renamed | Rewrite to `[[Development Workflows and Tools MOC]]` |
| `[[Kanban/X]]` → works but path-qualified is brittle | Rewrite to `[[X]]` when basename is unique |
| `[[code]]`, `[[project]]` → never were real notes | These were inline-tag syntax errors; delete the link and leave plain text |
| `[[Gen AI  Some Idea]]` (double space) | Fix the extra whitespace in the link |

## Cross-Namespace Ambiguity

When two notes share a basename (e.g. `Docker.md` in both `Zettelkasten/` and `FVH/z/`), every `[[Docker]]` in the vault becomes ambiguous. Options:

1. **Rename one** so they stop colliding (`FVH/z/Docker.md` → keep as redirect stub; content lives in `Zettelkasten/Docker.md`).
2. **Path-qualify the links** that should resolve to the non-canonical copy: `[[FVH/z/Docker]]`.
3. **Never use bare `[[Docker]]`** going forward; always path-qualify.

The preferred pattern is #1: keep canonical content in `Zettelkasten/`, make `FVH/z/` a tiny redirect stub.

## Detection

```bash
# Build a set of note basenames
fd -e md -x basename {} .md

# Find all wikilinks
rg -o '\[\[([^\]|#]+)' --no-filename --glob '*.md'

# Broken links: pipe the above through comm(1) against the basename set
```

A more accurate scan uses the `links.analyze_links` analyzer in vault-agent, which handles aliases, sections, and embeds correctly.

## Rewriting Strategy

For a known-broken target with many references, rewrite in one commit:

```
fix(links): rewrite 44 × [[AnsibleFVH]] → [[Ansible]]
```

Use `Edit` with `replace_all=True` for the target string within each note. Don't use shell `sed` — it doesn't handle the frontmatter / codeblock boundary correctly, and Edit's per-file atomicity makes the commit review straightforward.

For small-count broken targets (1–2 references each), report them and let the user decide whether to delete the link, create the note, or redirect.

## Ambiguous-Target Handling

Never auto-rewrite an ambiguous link. Report the ambiguity with both candidates and ask the user which resolution they want:

```
[[Docker]] in Zettelkasten/Kubernetes.md → candidates:
  a) Zettelkasten/Docker.md
  b) FVH/z/Docker.md (redirect stub)
```

## Safety

- Never rewrite links inside code blocks or YAML frontmatter.
- Never auto-create missing target notes — that's a content decision, not a maintenance one.
- Preserve the alias form: `[[Ansible|my ansible]]` → `[[Ansible|my ansible]]`, not `[[Ansible]]`.

## Related Skills

- **vault-orphans** — notes with no links at all
- **vault-mocs** — structured outgoing-link hubs
- **search-discovery** — runtime link traversal via Obsidian CLI
