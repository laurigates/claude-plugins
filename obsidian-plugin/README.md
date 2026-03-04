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

**When to use**: User mentions publishing notes, Obsidian Publish workflows, or checking sync status.

**Capabilities**:
- List, add, and remove published notes
- Check Obsidian Sync status
- Batch publishing workflows

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
- Use `format=json` for machine-parseable output
- Obsidian must be running for all CLI commands

## Keywords

obsidian, vault, notes, markdown, knowledge-base, daily-notes, properties, frontmatter, publish, sync, tags, tasks, plugins, themes

## Version

1.0.0

## License

Same as Claude Code configuration
