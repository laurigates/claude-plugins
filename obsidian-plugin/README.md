# Obsidian Plugin

Obsidian CLI operations plugin for Claude Code, providing expert knowledge for managing Obsidian vaults via the official command line interface (v1.12.4+).

## Overview

This plugin bundles all Obsidian CLI-related skills for managing knowledge bases, including:
- File and folder CRUD operations with daily note management
- Full-text search, tag operations, and link graph traversal
- YAML frontmatter property management
- Task listing, creation, and completion
- Plugin and theme management with developer tools
- Obsidian Publish and Sync workflows

## Prerequisites

- Obsidian desktop v1.12.4+ installed
- CLI enabled in **Settings → General → Command line interface**
- Obsidian must be running (CLI communicates with the running instance)

## Skills Included

### Vault Files
**File**: `skills/vault-files/SKILL.md`

Core file and folder operations plus daily note management.

**When to use**: User mentions reading, creating, editing, moving, or deleting Obsidian notes, listing vault files/folders, or daily note operations.

**Capabilities**:
- File listing with folder filtering and counts
- Note CRUD (read, create, append, prepend, move, delete)
- Daily note operations (open, read, append, prepend, date-specific)
- Template-based note creation

---

### Search & Discovery
**File**: `skills/search-discovery/SKILL.md`

Full-text search, tag management, and link graph exploration.

**When to use**: User wants to search vault content, explore tags, traverse links/backlinks, or find orphaned/unresolved notes.

**Capabilities**:
- Full-text and property-based search
- Tag listing, filtering by tag, bulk tag renaming
- Outgoing links and backlink traversal
- Orphan and unresolved link detection

---

### Properties
**File**: `skills/properties/SKILL.md`

YAML frontmatter property management.

**When to use**: User mentions frontmatter, properties, metadata, note status, aliases, or custom fields.

**Capabilities**:
- Read all properties from notes
- Set typed properties (text, date, tags, number, boolean)
- Remove properties
- Alias management

---

### Tasks
**File**: `skills/tasks/SKILL.md`

Task management across the vault.

**When to use**: User mentions tasks, todos, checklists, or completing items in Obsidian.

**Capabilities**:
- List all open tasks
- Create tasks in specific notes
- Mark tasks complete

---

### Plugins & Themes
**File**: `skills/plugins-themes/SKILL.md`

Plugin lifecycle and theme management with developer tools.

**When to use**: User mentions Obsidian plugins, themes, plugin development, or running JavaScript in the Obsidian runtime.

**Capabilities**:
- List, enable, disable, and reload plugins
- Theme listing and switching
- JavaScript eval in Obsidian runtime
- Screenshot capture

---

### Publish & Sync
**File**: `skills/publish-sync/SKILL.md`

Obsidian Publish and Sync service management.

**When to use**: User mentions publishing notes, Obsidian Publish workflows, checking sync status, or recovering sync-deleted files.

**Capabilities**:
- Publish site info, list/add/remove published notes, change set, open published page
- Sync pause/resume, status & usage, sync-deleted file listing
- Cross-links to `file-history` for per-file sync version restore

---

### Bases
**File**: `skills/bases/SKILL.md`

Query and create entries in Obsidian Bases — the database-over-notes feature.

**When to use**: User mentions Obsidian Bases, `.base` files, querying notes as a database, base views, or structured note queries.

**Capabilities**:
- List `.base` files and their views
- Query a view as JSON / CSV / TSV / Markdown / paths
- Create new entries directly into a base view

---

### Command Palette
**File**: `skills/command-palette/SKILL.md`

Run any Obsidian command (built-in or plugin-registered) and inspect hotkeys.

**When to use**: User wants to trigger a command they would normally pick from the command palette, enumerate plugin-registered commands, or look up a hotkey.

**Capabilities**:
- List, filter, and execute commands by ID
- List and look up hotkey bindings
- Discover plugin-registered commands

---

### File History
**File**: `skills/file-history/SKILL.md`

Diff and restore previous versions from File Recovery and Sync history. Critical safety net for agentic edits.

**When to use**: User mentions undo, restoring a previous version, file recovery, version history, or comparing what changed.

**Capabilities**:
- `diff` across local + sync versions, with `from`/`to` and source filter
- Local File Recovery list, read, and restore
- Sync version list, read, restore, and deleted-files recovery

---

### Dev Tools
**File**: `skills/dev-tools/SKILL.md`

Developer commands for plugin and theme development — DevTools, Chrome DevTools Protocol, eval, captured console/error buffers, CSS and DOM inspection, mobile emulation, and screenshots.

**When to use**: User is developing a plugin or theme, debugging the Obsidian app, or needs to introspect the running renderer state.

**Capabilities**:
- Toggle DevTools, attach/detach CDP debugger, run CDP methods
- Run JavaScript via `eval`, inspect captured console / errors
- Query CSS rules with source location and DOM elements
- Mobile emulation toggle and screenshots

---

### Workspaces
**File**: `skills/workspaces/SKILL.md`

Inspect and manage the Obsidian editor workspace, tabs, recents, and saved layouts.

**When to use**: User asks what's open in Obsidian, wants to switch to a saved layout, save the current layout, or open files into specific tabs/groups.

**Capabilities**:
- Workspace tree, open tabs, recently opened files
- Save / load / delete named workspaces (Workspaces core plugin)
- Open files or non-file views (graph, file explorer) into specific tab groups

---

### Vault Management
**File**: `skills/vault-management/SKILL.md`

Inspect the active vault, enumerate known vaults, and target commands at a specific vault.

**When to use**: User asks about vault info (path, file count, size), works across multiple vaults, or wants to run a command against a non-active vault.

**Capabilities**:
- Active vault info (`name`, `path`, `files`, `folders`, `size`)
- List known vaults with paths
- Multi-vault `vault=<name>` global prefix

---

### Templates
**File**: `skills/templates/SKILL.md`

List, read, and insert templates from the core Templates plugin, with variable resolution.

**When to use**: User mentions Obsidian templates, the Templates plugin, or template variable resolution (`{{date}}`, `{{time}}`, `{{title}}`).

**Capabilities**:
- List all templates and previews (raw or resolved)
- Insert template into the active editor
- Cross-link to `vault-files create … template=…` for new-note creation

---

### Bookmarks
**File**: `skills/bookmarks/SKILL.md`

List and add Obsidian bookmarks — files, folders, headings/blocks, saved searches, and external URLs.

**When to use**: User mentions Obsidian bookmarks, starring/saving notes for quick access, or scripted bookmark creation.

**Capabilities**:
- List bookmarks with type metadata
- Bookmark files, folders, headings (`subpath=#H`), blocks (`subpath=^id`), searches, and URLs
- Bulk-bookmark patterns from base queries

---

## Keeping Skills Current

A scheduled GitHub workflow (`.github/workflows/obsidian-cli-changelog.yml`) fetches the upstream Obsidian CLI documentation weekly, hashes its content, and — when the hash changes — opens a draft PR with proposed skill updates. State is tracked in `.obsidian-cli-version-check.json` at the repo root.

Run on demand with: **Actions → Plugin: Obsidian CLI changelog review → Run workflow**.

---

## Vault Maintenance Skills (offline, file-level)

The skills above wrap the Obsidian CLI and require a running Obsidian instance. The following operate directly on markdown files — useful for bulk maintenance passes and scheduled jobs. They power [`vault-agent`](../vault-agent/).

### Vault Frontmatter
**File**: `skills/vault-frontmatter/SKILL.md` — Offline YAML repair: strip legacy `id:`, clean null tags, remove Templater leakage.

### Vault Tags
**File**: `skills/vault-tags/SKILL.md` — Emoji-prefixed tag taxonomy, consolidation table for near-duplicates.

### Vault Wikilinks
**File**: `skills/vault-wikilinks/SKILL.md` — Broken wikilink repair, cross-namespace ambiguity handling.

### Vault Orphans
**File**: `skills/vault-orphans/SKILL.md` — Orphan note triage heuristics.

### Vault Stubs
**File**: `skills/vault-stubs/SKILL.md` — FVH/z redirect-stub pattern (for vaults using the LakuVault work-namespace convention).

### Vault MOCs
**File**: `skills/vault-mocs/SKILL.md` — Map-of-Content curation, convention drift repair.

### Vault Templates
**File**: `skills/vault-templates/SKILL.md` — Templater convention reference, drift repair.

## Installation

```bash
# In your project
claude plugins add /path/to/obsidian-plugin

# Or globally
claude plugins add --global /path/to/obsidian-plugin
```

## Key Conventions

- Paths are vault-relative — use `folder/note.md`, not absolute paths
- `create` omits `.md` (added automatically), `move` requires it
- Flags are bare words (`overwrite`, `open`, `newtab`, `permanent`, `inline`, `total`); the universal `--copy` flag is the only `--`-prefixed one
- `file=<name>` resolves like a wikilink; `path=<full/path.md>` is exact
- Most commands default to the active file when no target is specified
- Use `format=json` for machine-parseable output
- Multi-vault: prefix `vault=<name>` before the command (see `vault-management`)
- Obsidian must be running for all CLI commands

## Keywords

obsidian, vault, notes, markdown, knowledge-base, daily-notes, properties, frontmatter, publish, sync, tags, tasks, plugins, themes

## Version

1.0.0

## License

Same as Claude Code configuration
