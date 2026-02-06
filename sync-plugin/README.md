# Sync Plugin for Claude Code

A Claude Code plugin for external system synchronization, providing seamless integration between GitHub, Podio, and Obsidian for enhanced task management and daily workflow optimization.

## Overview

The sync-plugin enables bidirectional synchronization between GitHub and Podio, with special support for generating ADHD-friendly daily catch-up notes in Obsidian. It helps maintain consistency across project tracking platforms and reduces context-switching overhead.

## Features

- **Daily Catch-Up Notes**: Automatically aggregates GitHub issues, PRs, and Podio tasks into categorized, ADHD-friendly Obsidian notes
- **Bidirectional Sync**: Keep GitHub and Podio synchronized with automatic status updates and cross-references
- **Smart Categorization**: Intelligent categorization of tasks by urgency (URGENT, ACTION NEEDED, IN PROGRESS, BLOCKED, FYI)
- **Incremental Updates**: State-based tracking to fetch only new/updated items since last run
- **Multiple Sync Modes**: Full sync, selective sync, status-only, and enhancement modes

## Installation

1. Copy the `sync-plugin` directory to your Claude Code plugins location
2. Ensure the following MCP servers are configured:
   - `github` - GitHub MCP server
   - `podio-mcp` - Podio MCP server

## Skills

### `sync-daily`

Generates an ADHD-friendly daily catch-up note in Obsidian with categorized tasks from GitHub and Podio.

**Arguments:**
- `--dry-run` - Preview what would be fetched without creating the note
- `--verbose` - Show detailed progress and API responses
- `--full-refresh` - Fetch all active items (ignore incremental state)

**Examples:**
```bash
# Standard daily run (incremental)
/sync:daily

# Preview mode
/sync:daily --dry-run

# Full refresh of all active items
/sync:daily --full-refresh

# Verbose output for debugging
/sync:daily --verbose
```

**What it does:**
1. Fetches GitHub issues and PRs where you're assigned, mentioned, or need to review
2. Fetches active Podio tasks from your workspace
3. Categorizes items by urgency and action required
4. Generates a markdown note in your Obsidian vault
5. Updates state file for incremental future runs

**Output:** `~/Documents/FVH Vault/Daily Notes/YYYY-MM-DD.md`

### `sync-github-podio`

Bidirectional synchronization between GitHub and Podio for maintaining consistent project state.

**Arguments:**
- `--full-sync` - Complete bidirectional synchronization across all items
- `--selective` - Sync specific items (recent activity, specific projects, status mismatches)
- `--status-only` - Update only status information
- `--enhance` - Enrich existing linked items with additional context

**Examples:**
```bash
# Full bidirectional sync
/sync:github-podio --full-sync

# Sync only recent activity
/sync:github-podio --selective

# Update statuses only
/sync:github-podio --status-only

# Enhance existing cross-references
/sync:github-podio --enhance
```

**What it does:**
1. Discovers GitHub issues/PRs and Podio items
2. Matches items across platforms
3. Identifies status mismatches and missing links
4. Updates descriptions with cross-references
5. Harmonizes status between platforms
6. Generates synchronization report

## Configuration

### Obsidian Vault

Default configuration (can be customized in plugin.json):
```yaml
vault_path: ~/Documents/FVH Vault
daily_notes_path: ~/Documents/FVH Vault/Daily Notes
note_format: YYYY-MM-DD.md
```

### Podio Workspace

Default workspace coordinates:
```yaml
org_label: fvh
space_label: iot-workspace
app_label: datadev-kanban
```

### State Management

State files are stored in:
```
~/.config/claude-code/sync:daily-state.json
```

State tracks last run timestamps to enable incremental updates.

## Daily Catch-Up Note Structure

The generated daily note includes:

- **🔥 URGENT** - Items requiring immediate attention (PRs with changes requested, critical issues, blocking items)
- **⚡ ACTION NEEDED** - Items requiring action soon (pending reviews, assigned issues, upcoming deadlines)
- **🚧 IN PROGRESS** - Items currently being worked on (your open PRs, active issues, Podio in-progress tasks)
- **🚫 BLOCKED** - Items waiting on others (PRs awaiting review, blocked issues, on-hold tasks)
- **📋 FYI** - Informational items (low priority, mentions, CC'd items)

Each section includes:
- Checkboxes for tracking completion
- Clear status indicators
- Direct links to items
- Context about why action is needed
- Summary statistics and recommended focus order

## ADHD-Friendly Design

The plugin follows ADHD-friendly principles:

- ✅ Visual scanning with emojis and formatting
- ✅ Checkboxes for dopamine-loop task completion
- ✅ Collapsed low-priority sections to reduce overwhelm
- ✅ Clear recommended focus order
- ✅ Concise descriptions (one line per item)
- ✅ Encouraging messages for empty urgent sections
- ✅ Count indicators for progress tracking

## Status Mapping

### GitHub ↔ Podio Status Alignment

| GitHub Status | Podio Status |
|--------------|--------------|
| Open (Issue/PR) | In Progress / To Do |
| Closed | Completed / Done |
| Draft PR | In Progress |
| Merged PR | Completed |
| - | On Hold → GitHub "on-hold" label |

### Priority Mapping

| Podio Priority | GitHub Label |
|---------------|--------------|
| High | high priority |
| Medium | medium priority |
| Low | low priority |

## Error Handling

The plugin gracefully handles:

- **API Failures**: Continues with available data, notes unavailable services
- **State File Issues**: Falls back to first-run mode if state is corrupted
- **Vault Access**: Creates directories if missing, provides clear error messages
- **Rate Limiting**: Implements delays between API calls

## Performance

- **Execution Time**: < 30 seconds for typical daily run
- **Parallel Fetching**: GitHub and Podio data fetched simultaneously
- **Pagination Limits**: Configurable (default: 50 items per source)
- **Incremental Updates**: Only fetches changed items after first run

## Dependencies

### Required MCP Servers

- **github** - GitHub API integration
  - `mcp__github__get_me`
  - `mcp__github__list_issues`
  - `mcp__github__list_pull_requests`
  - `mcp__github__search_issues`
  - `mcp__github__create_issue`
  - `mcp__github__update_issue`

- **podio-mcp** - Podio API integration
  - `mcp__podio-mcp__list_items`
  - `mcp__podio-mcp__get_item_details`
  - `mcp__podio-mcp__create_item`
  - `mcp__podio-mcp__update_item`

## File Structure

```
sync-plugin/
├── .claude-plugin/
│   └── plugin.json          # Plugin metadata and configuration
├── skills/
│   ├── sync-daily/
│   │   └── SKILL.md         # Daily catch-up skill
│   └── sync-github-podio/
│       └── SKILL.md         # Bidirectional sync skill
├── agents/                  # (Reserved for future agents)
└── README.md               # This file
```

## Future Enhancements

Planned for v1.1+:

- Gmail integration via MCP server
- Google Chat integration via MCP server
- AI-powered categorization using Zen MCP
- Interactive mode for reviewing items before note creation
- Custom category definitions via config file
- Integration with Obsidian tasks plugin
- Time-blocking suggestions based on item estimates
- Progress tracking over time (trend analysis)

## Troubleshooting

### State file issues
```bash
# Reset state file to force full refresh
rm ~/.config/claude-code/sync:daily-state.json
/sync:daily --full-refresh
```

### Obsidian vault not found
Check that your vault path is correct in the plugin.json configuration.

### API rate limiting
Use `--verbose` mode to see detailed API responses and timing.

### Missing MCP servers
Verify GitHub and Podio MCP servers are properly configured in Claude Code.

## Contributing

This plugin is part of the claude-plugins repository. Contributions are welcome via pull requests.

## License

Same license as the parent repository.

## Author

lgates

## Version

1.0.0
