# Command Analytics Plugin

Track and analyze command and skill usage across all your Claude Code projects.

## Overview

This plugin provides transparent, automatic analytics for all commands and skills you use in Claude Code. It helps you:

- **Discover patterns** - See which commands and skills you use most
- **Identify gaps** - Find unused commands and skills
- **Track success** - Monitor success rates and identify failing operations
- **Work globally** - Analytics persist across all projects

## Features

### 🎯 Automatic Tracking

Analytics are collected automatically via hooks with zero impact on your workflow:

- **Transparent** - No manual logging required
- **Fast** - Async tracking with 5s timeout
- **Resilient** - Failures don't block your commands
- **Global** - Data stored in `~/.claude-analytics/`

### 📊 Rich Reporting

View detailed analytics with multiple commands:

- **Usage statistics** - See command/skill frequencies
- **Success rates** - Track what works (and what doesn't)
- **Recent activity** - View your latest operations
- **Unused features** - Discover commands you haven't tried

### 💾 Data Export

Export your analytics data for external analysis:

- **JSON** - Raw data export
- **CSV** - Import into spreadsheets
- **Markdown** - Generate reports

## Commands

| Command | Description |
|---------|-------------|
| `/analytics:report [filter]` | Display usage analytics (all, commands, skills, or specific name) |
| `/analytics:unused` | Show commands and skills that have never been used |
| `/analytics:export [format] [file]` | Export analytics (json, csv, markdown) |
| `/analytics:clear [--confirm]` | Reset all analytics data |

## Quick Start

### View Analytics

```bash
# Show all analytics
/analytics:report

# Show only commands
/analytics:report commands

# Show only skills
/analytics:report skills

# Show details for specific command
/analytics:report git:commit
```

### Find Unused Features

```bash
# Discover commands and skills you haven't tried
/analytics:unused
```

### Export Data

```bash
# Display as JSON
/analytics:export json

# Export to CSV file
/analytics:export csv analytics.csv

# Generate markdown report
/analytics:export markdown report.md
```

### Reset Analytics

```bash
# Clear all data (with confirmation)
/analytics:clear

# Clear without prompt
/analytics:clear --confirm
```

## Data Storage

Analytics are stored globally in your home directory:

```
~/.claude-analytics/
├── events.jsonl       # Raw event log (append-only)
└── summary.json       # Aggregated statistics (updated on each event)
```

### Data Schema

**Events (events.jsonl):**
```json
{
  "timestamp": "2026-01-10T12:34:56Z",
  "type": "command",
  "name": "git:commit",
  "args": "-m 'Fix bug'",
  "project": "/path/to/project",
  "success": true,
  "error": ""
}
```

**Summary (summary.json):**
```json
{
  "tracking_since": "2026-01-10T12:00:00Z",
  "total_invocations": 123,
  "items": {
    "git:commit": {
      "type": "command",
      "count": 45,
      "success": 40,
      "failure": 5,
      "first_used": "2026-01-10T12:00:00Z",
      "last_used": "2026-01-10T16:30:00Z"
    }
  }
}
```

## Privacy

- **Local only** - All data is stored locally in `~/.claude-analytics/`
- **No telemetry** - Nothing is sent to external services
- **Your control** - Clear data anytime with `/analytics:clear`

## How It Works

### Hook Architecture

The plugin uses a `PostToolUse` hook on the `Skill` tool:

1. **Trigger** - Every time a command/skill is invoked via the Skill tool
2. **Capture** - Hook script extracts skill name, success/failure, timestamp
3. **Store** - Data appended to `events.jsonl` and `summary.json` updated
4. **Continue** - Hook completes asynchronously, never blocks workflow

### Performance

- **Timeout** - 5s maximum (hook script runs in <100ms typically)
- **Error handling** - `continueOnError: true` prevents blocking
- **Async** - Tracking happens after command completes

## Example Output

```
📊 Command & Skill Analytics

Total invocations: 156
Tracking since: 2026-01-10T10:00:00Z

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Most Used
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📝 Commands
  45     git:commit  (40✓ 5✗)
  32     blueprint:prd  (32✓ 0✗)
  18     analytics:report  (18✓ 0✗)

🎯 Skills
  28     typescript-development  (25✓ 3✗)
  15     biome-tooling  (15✓ 0✗)
  12     bun-development  (12✓ 0✗)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Success Rates
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Overall: 94.8% (148✓ 8✗)

  Items with failures:
    git:commit: 5 failures
    typescript-development: 3 failures

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

💡 Tips:
  • /analytics:report commands   - Show only commands
  • /analytics:unused            - Find never-used commands
  • /analytics:clear             - Reset analytics data
```

## Troubleshooting

### No data being collected

1. **Check plugin is enabled:**
   ```bash
   ls ~/.claude-plugins/command-analytics-plugin
   ```

2. **Verify hook script is executable:**
   ```bash
   ls -la ~/.claude-plugins/command-analytics-plugin/scripts/track-usage.sh
   ```

3. **Check analytics directory:**
   ```bash
   ls -la ~/.claude-analytics/
   ```

### Hook timeout errors

If you see hook timeout errors:
- Analytics tracking should complete in <100ms normally
- Timeout is set to 5s for safety
- Errors don't block commands (`continueOnError: true`)

## Development

### Testing the Hook

Test the tracking script manually:

```bash
cd command-analytics-plugin

# Simulate a successful command invocation
echo '{
  "parameters": {"skill": "test:command", "args": "--test"},
  "result": "success"
}' | ./scripts/track-usage.sh

# Check analytics were recorded
cat ~/.claude-analytics/summary.json | jq '.'
```

### Debugging

Enable hook debugging in Claude Code settings to see hook execution logs.

## Contributing

Contributions welcome! See the main repository for contribution guidelines.

## License

MIT
