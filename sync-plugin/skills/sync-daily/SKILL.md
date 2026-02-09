---
model: opus
created: 2025-12-16
modified: 2025-12-16
reviewed: 2025-12-16
allowed-tools: Read, Write, Edit, TodoWrite, mcp__github__list_issues, mcp__github__list_pull_requests, mcp__github__search_issues, mcp__github__get_me, Bash
argument-hint: [--dry-run|--verbose|--full-refresh]
description: Daily catch-up command that aggregates GitHub items into an ADHD-friendly Obsidian note
name: sync-daily
---

# Daily Catch-Up Command

Aggregates action items from GitHub into a categorized daily summary optimized for ADHD-friendly workflow.

## Configuration

### Obsidian Vault Location
```yaml
vault_path: ~/Documents/FVH Vault
daily_notes_path: ~/Documents/FVH Vault/Daily Notes
note_format: YYYY-MM-DD.md
```

### State File
```yaml
state_file: ~/.config/claude-code/sync:daily-state.json
```

## Command Modes

### Default Mode
Fetches new items since last run and creates daily note with categorized summary.

### Dry Run Mode (`--dry-run`)
Displays what would be fetched without creating the note or updating state.

### Verbose Mode (`--verbose`)
Shows detailed progress and API responses during execution.

### Full Refresh Mode (`--full-refresh`)
Ignores last run timestamp and fetches all active items (useful for first run or after issues).

## Implementation Workflow

### Step 1: Initialize and Load State

1. **Check for state file** at `~/.config/claude-code/sync:daily-state.json`
2. **Load last run timestamp** if exists, otherwise treat as first run
3. **Determine time filter** for API queries:
   - If `--full-refresh`: No time filter (fetch all active items)
   - If state exists: Filter by items updated since last run
   - If first run: Fetch items from last 7 days

**State File Schema:**
```json
{
  "lastRun": "2025-11-12T08:30:00Z",
  "lastSuccessfulRun": "2025-11-12T08:30:00Z",
  "github": {
    "lastIssueUpdate": "2025-11-12T08:30:00Z",
    "lastPRUpdate": "2025-11-12T08:30:00Z"
  }
}
```

### Step 2: Fetch GitHub Items

Use the GitHub MCP server to fetch items needing attention:

1. **Get authenticated user** via `mcp__github__get_me` to determine username
2. **Fetch assigned issues** using `mcp__github__search_issues`:
   - Query: `is:issue is:open assignee:@me sort:updated-desc`
   - Filter by updated since last run if applicable
3. **Fetch PRs needing review** using `mcp__github__search_issues`:
   - Query: `is:pr is:open review-requested:@me sort:updated-desc`
4. **Fetch PRs authored by user** using `mcp__github__search_issues`:
   - Query: `is:pr is:open author:@me sort:updated-desc`
5. **Fetch mentioned items** using `mcp__github__search_issues`:
   - Query: `is:open mentions:@me sort:updated-desc`

**Data to Extract:**
- Issue/PR number and title
- Repository name
- Status (open, draft, review requested, changes requested)
- Labels (priority, bug, feature, etc.)
- Updated timestamp
- URL for quick access
- Comments count (indicates activity)

### Step 3: Categorize Items

Apply categorization logic to all fetched items:

#### Category Definitions

**URGENT** - Requires immediate attention:
- GitHub PRs with "changes requested" status
- GitHub issues labeled with "critical" or "urgent"
- Any item blocking others (check for "blocked by" or "blocking" keywords)
- Items with past-due dates

**ACTION NEEDED** - Requires action soon:
- GitHub PRs awaiting your review
- GitHub issues assigned to you without recent activity (>3 days)
- GitHub mentions in open issues/PRs
- Items with due dates within next 3 days

**IN PROGRESS** - Currently being worked on:
- GitHub PRs you authored that are open
- GitHub issues you're actively working on (recent activity <3 days)

**BLOCKED** - Waiting on someone else:
- GitHub PRs awaiting other reviewers (not you)
- GitHub issues with "blocked" label
- Items with "waiting for" keywords in description

**FYI** - Informational, low priority:
- GitHub issues where you're mentioned but not assigned
- GitHub PRs where you're CC'd but not primary reviewer
- Items with no labels indicating urgency

#### Categorization Algorithm

```
For each item:
  1. Check for blocking/blocked status → BLOCKED
  2. Check for urgent labels/keywords → URGENT
  3. Check for past-due or due within 3 days → URGENT or ACTION NEEDED
  4. Check if you're actively working on it → IN PROGRESS
  5. Check if action is required from you → ACTION NEEDED
  6. Default → FYI
```

### Step 4: Generate Obsidian Note

Create a markdown note with ADHD-friendly formatting:

**File Location:** `~/Documents/FVH Vault/Daily Notes/YYYY-MM-DD.md`

**Note Structure:**

```markdown
# Daily Catch-Up - [Day of Week], [Month DD, YYYY]

> Generated at [HH:MM AM/PM] | [X] items | [Y] require action

## 🔥 URGENT ([count])

[If empty: "✅ No urgent items - great!"]

- [ ] **[Repo/Project]** [Title] ([Type])
  - 📍 Status: [status]
  - 🔗 [Link]
  - 💬 [Why urgent: blocking, changes requested, etc.]

## ⚡ ACTION NEEDED ([count])

[If empty: "✅ No immediate actions required"]

- [ ] **[Repo/Project]** [Title] ([Type])
  - 📍 Status: [status]
  - 🔗 [Link]
  - 💡 [What's needed: review, response, work, etc.]

## 🚧 IN PROGRESS ([count])

[If empty: "No items currently in progress"]

- [ ] **[Repo/Project]** [Title] ([Type])
  - 📍 Status: [status]
  - 🔗 [Link]
  - ⏱️ Last updated: [relative time]

## 🚫 BLOCKED ([count])

[If empty: "✅ No blocked items"]

- [ ] **[Repo/Project]** [Title] ([Type])
  - 📍 Status: [status]
  - 🔗 [Link]
  - ⛔ Waiting on: [blocker description]

## 📋 FYI ([count])

[Collapsed by default in Obsidian]

<details>
<summary>Show [count] informational items</summary>

- **[Repo/Project]** [Title] ([Type])
  - 📍 [status] | 🔗 [Link]

</details>

---

## 📊 Summary Statistics

- **Total Items:** [count]
- **Urgent:** [count] 🔥
- **Action Needed:** [count] ⚡
- **In Progress:** [count] 🚧
- **Blocked:** [count] 🚫
- **FYI:** [count] 📋

## 🎯 Recommended Focus Order

1. 🔥 Start with URGENT items (highest impact)
2. ⚡ Move to ACTION NEEDED (prevent future urgency)
3. 🚧 Continue IN PROGRESS items (maintain momentum)
4. 🚫 Follow up on BLOCKED items (unblock if possible)
5. 📋 Review FYI items when time permits

name: sync-daily
---

*Last fetch: [timestamp] | State saved to `~/.config/claude-code/sync:daily-state.json`*
```

**ADHD-Friendly Formatting Guidelines:**

- ✅ Use checkboxes for actionable items (creates dopamine loop)
- ✅ Use emojis for quick visual scanning
- ✅ Bold project names for easy identification
- ✅ Collapse FYI section to reduce overwhelm
- ✅ Provide clear recommended focus order
- ✅ Keep descriptions concise (one line per item)
- ✅ Use relative time ("2 hours ago") for recent items
- ✅ Show counts in section headers for progress tracking
- ✅ Include encouraging messages for empty urgent sections

### Step 5: Update State File

After successful execution:

1. **Update state file** with current timestamp:
   ```json
   {
     "lastRun": "[current_timestamp]",
     "lastSuccessfulRun": "[current_timestamp]",
     "github": {
       "lastIssueUpdate": "[current_timestamp]",
       "lastPRUpdate": "[current_timestamp]"
     }
   }
   ```
2. **Create state directory** if it doesn't exist: `~/.config/claude-code/`
3. **Set file permissions** to 600 (user read/write only)

### Step 6: Display Summary

Show concise summary in terminal:

```
✅ Daily Catch-Up Complete!

📁 Note created: ~/Documents/FVH Vault/Daily Notes/2025-11-12.md

📊 Summary:
   🔥 URGENT: 2 items
   ⚡ ACTION NEEDED: 5 items
   🚧 IN PROGRESS: 3 items
   🚫 BLOCKED: 1 item
   📋 FYI: 4 items

🎯 Recommended: Start with URGENT items

⏱️  Next run: Use /sync:daily to refresh
```

## Error Handling

### API Failures

- **GitHub API fails**: Display error, preserve current state, suggest retry

### State File Issues

- **State file corrupted**: Treat as first run, backup corrupted file
- **State file unreadable**: Treat as first run
- **Can't write state**: Warn user, command succeeds but next run will re-fetch

### Obsidian Vault Issues

- **Vault path doesn't exist**: Create directory or fail with clear error
- **Can't write note**: Fail with clear error and path suggestion
- **Daily Notes folder missing**: Create it automatically

## Performance Optimization

- **Minimal data**: Only fetch fields needed for categorization
- **Pagination**: Limit to first 50 items per source (configurable)
- **Caching**: Use state file to avoid re-fetching unchanged items

## Usage Examples

```bash
# Standard daily run (incremental fetch since last run)
/sync:daily

# See what would be fetched without creating note
/sync:daily --dry-run

# Full refresh of all active items (ignore last run time)
/sync:daily --full-refresh

# Verbose mode for debugging
/sync:daily --verbose

# Combination: dry run with verbose output
/sync:daily --dry-run --verbose
```

## Success Criteria

- ✅ Command executes in <30 seconds
- ✅ Fetches new items since last run correctly
- ✅ Categorizes items accurately (>90% accuracy)
- ✅ Creates well-formatted Obsidian note
- ✅ Updates state file successfully
- ✅ Handles API failures gracefully
- ✅ Provides clear, actionable summary
- ✅ Reduces decision paralysis and context-switching

## Future Enhancements (v1.1+)

- Gmail integration via MCP server (when available)
- Google Chat integration via MCP server (when available)
- AI-powered categorization using Zen MCP
- Interactive mode for reviewing items before note creation
- Custom category definitions via config file
- Integration with Obsidian tasks plugin
- Time-blocking suggestions based on item estimates
- Progress tracking over time (trend analysis)
