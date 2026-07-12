## vault-wikilinks

# Wikilink Integrity


## Link Syntax

```markdown
[[Note Name]]                      # basename resolution
[[Note Name|Alias]]                # custom display text
[[Note Name#Section heading]]      # deep link to heading
[[folder/Note Name]]               # path-qualified (usually unnecessary)
![[Image.png]]                     # embed (image, note, PDF)
```


## Resolution Rules

1. **Unqualified target** (`[[Docker]]`) resolves to any note with basename `Docker.md`. If two exist (e.g. `Zettelkasten/Docker.md` and `work/z/Docker.md`), Obsidian picks one non-deterministically — ambiguous.
2. **Path-qualified target** (`[[Kanban/Main]]`) resolves to `Kanban/Main.md` exactly — no basename fallback.
3. **Embeds** (`![[X]]`) follow the same resolution. Image embeds typically target files under `Files/`.


## Common Breakage Patterns

| Pattern | Fix |
|---------|-----|
| `[[OldTopic]]` × many → note doesn't exist | Rewrite to `[[Topic]]` (the actual note) |
| `[[Development MOC]]` → note was renamed | Rewrite to `[[Development Workflows and Tools MOC]]` |
| `[[Kanban/X]]` → works but path-qualified is brittle | Rewrite to `[[X]]` when basename is unique |
| `[[code]]`, `[[project]]` → never were real notes | These were inline-tag syntax errors; delete the link and leave plain text |
| `[[Gen AI  Some Idea]]` (double space) | Fix the extra whitespace in the link |


## Cross-Namespace Ambiguity

When two notes share a basename (e.g. `Docker.md` in both `Zettelkasten/` and `work/z/`), every `[[Docker]]` in the vault becomes ambiguous. Options:

1. **Rename one** so they stop colliding (`work/z/Docker.md` → keep as redirect stub; content lives in `Zettelkasten/Docker.md`).
2. **Path-qualify the links** that should resolve to the non-canonical copy: `[[work/z/Docker]]`.
3. **Never use bare `[[Docker]]`** going forward; always path-qualify.

The preferred pattern is #1: keep canonical content in `Zettelkasten/`, make `work/z/` a tiny redirect stub.


## Detection

```bash

# Build a set of note basenames
fd -e md -x basename {} .md


# Find all wikilinks
rg -o '\[\[([^\]|#]+)' --no-filename --glob '*.md'


# Broken links: pipe the above through comm(1) against the basename set
```

A more accurate scan uses the `links.analyze_links` analyzer in vault-agent, which handles aliases, sections, and embeds correctly.


## Offline Fallback (App Closed)

The detection methodology above is unchanged — only the **data source** changes when Obsidian (and its `obsidian` CLI / live link index) is closed. The `obsidian` CLI and `vault-agent` analyzers are the **live-index** path; parsing the `.md` corpus directly with the `rg`/`fd` Detection snippet above is the **deterministic headless default**, and for batch/scheduled audits it is often the better choice (reproducible, free of app/index state). `vault-frontmatter` already operates this way.

Parse the corpus directly:

- **Frontmatter** — read each note's YAML block between the leading `---` fences; extract `tags`, `aliases`, `context`. See `vault-frontmatter` for YAML-block mechanics.
- **Wikilinks** — match `[[Target]]`, `[[Target|Alias]]`, `[[Target#Heading]]`, `[[folder/Target]]`, and `![[embed]]`. Resolve each target to a note by **basename**, then **relative path**, then **alias** (from frontmatter), all **case-insensitive**. Resolve `![[embed]]` against attachments as well as notes — the attachment folder is per-vault configurable, so read it from `.obsidian/app.json` (`attachmentFolderPath`) and fall back to the vault root / `Files/` only when that key is unset.

A link is **broken** when its target resolves to no note after the basename → relpath → alias (case-insensitive) cascade — embeds against attachments included. A target is **ambiguous** when its basename matches 2+ notes (the cross-namespace case above). Feed the Detection snippet's output through this resolution cascade to reproduce the `unresolved` audit headlessly.


## Rewriting Strategy

For a known-broken target with many references, rewrite in one commit:

```
fix(links): rewrite 44 × [[OldTopic]] → [[Topic]]
```

Use `Edit` with `replace_all=True` for the target string within each note. Don't use shell `sed` — it doesn't handle the frontmatter / codeblock boundary correctly, and Edit's per-file atomicity makes the commit review straightforward.

For small-count broken targets (1–2 references each), report them and let the user decide whether to delete the link, create the note, or redirect.


## Ambiguous-Target Handling

Never auto-rewrite an ambiguous link. Report the ambiguity with both candidates and report to the orchestrator which resolution they want:

```
[[Docker]] in Zettelkasten/Kubernetes.md → candidates:
  a) Zettelkasten/Docker.md
  b) work/z/Docker.md (redirect stub)
```


## Safety

- Never rewrite links inside code blocks or YAML frontmatter.
- Never auto-create missing target notes — that's a content decision, not a maintenance one.
- Preserve the alias form: `[[Ansible|my ansible]]` → `[[Ansible|my ansible]]`, not `[[Ansible]]`.

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
