---
allowed-tools: Read, Write, Edit, TodoWrite, mcp__podio-mcp__list_items, mcp__podio-mcp__create_item, mcp__podio-mcp__update_item, mcp__podio-mcp__get_item_details, mcp__github__list_issues, mcp__github__create_issue, mcp__github__update_issue, mcp__github__list_pull_requests, mcp__github__search_issues, mcp__graphiti-memory__add_memory
argument-hint: [--full-sync|--selective|--status-only|--enhance]
description: Bidirectional synchronization between GitHub and Podio
---

# Information Dissemination Command

Cross-platform information synchronization between GitHub and Podio for consistent project tracking and task management.

## Configuration

### Default Podio Workspace
```yaml
org_label: fvh
space_label: iot-workspace
app_label: datadev-kanban
```

**Note:** All Podio-MCP operations now require explicit workspace coordinates. The above defaults are used when not specified otherwise.

## Synchronization Workflow

### Phase 1: Discovery & Assessment

- Query Podio for active items and recent updates using `mcp__podio-mcp__list_items` with coordinates `org_label="fvh", space_label="iot-workspace", app_label="datadev-kanban"`
- Fetch GitHub issues and pull requests using `mcp__github__list_issues` and `mcp__github__list_pull_requests`
- Identify synchronization opportunities by matching:
  - Issue titles/descriptions with Podio item titles/descriptions
  - GitHub issue numbers referenced in Podio items
  - Common keywords and project tags
  - Status alignment opportunities

### Phase 2: Bidirectional Synchronization Analysis

- **GitHub → Podio Direction:**

  - Check for GitHub issues without corresponding Podio items
  - Identify status mismatches (GitHub closed but Podio in progress)
  - Find PR links that should be added to Podio item descriptions
  - Detect completion status updates from GitHub that need Podio reflection

- **Podio → GitHub Direction:**
  - Check for Podio items without corresponding GitHub issues
  - Identify Podio status changes that should update GitHub issues
  - Find Podio assignments that should be reflected in GitHub
  - Detect priority changes that need GitHub label updates

### Phase 3: Information Enhancement

- **Enrich Podio Items:**

  - Add GitHub issue/PR links to descriptions using `mcp__podio-mcp__update_item` with workspace coordinates
  - Include recent commit summaries and PR status updates
  - Update status based on GitHub issue/PR state
  - Add relevant GitHub milestone information
  - Include code review feedback summaries

- **Enrich GitHub Issues:**
  - Add Podio item links to issue descriptions using `mcp__github__update_issue`
  - Include project context from Podio epic/project fields
  - Add business context and stakeholder information
  - Update labels based on Podio status and priority
  - Cross-reference related Podio tasks

### Phase 4: Status Harmonization

- **Status Mapping Rules:**

  - GitHub Open ↔ Podio "In Progress" or "To Do"
  - GitHub Closed ↔ Podio "Completed" or "Done"
  - GitHub Draft PR ↔ Podio "In Progress"
  - GitHub Merged PR ↔ Podio "Completed"
  - Podio "On Hold" → GitHub issue with "on-hold" label

- **Priority Alignment:**
  - Map Podio priority levels to GitHub labels (high, medium, low priority)
  - Update GitHub milestones based on Podio epic assignments
  - Sync assignee information between platforms

### Phase 5: Documentation Generation

- Generate a synchronization summary for logging to Obsidian
- Create cross-reference documentation showing:
  - Which GitHub issues correspond to which Podio items
  - Status alignment outcomes
  - Information enhancement actions taken
  - Any conflicts or manual review needed

## Synchronization Modes

### Full Sync Mode

```
Run complete bidirectional synchronization across all active items and issues
```

### Selective Sync Mode

```
Synchronize specific items based on:
- Recent activity (last 7 days)
- Specific project or epic
- Status mismatches only
- New items without cross-platform links
```

### Status-Only Mode

```
Update only status information without modifying descriptions or creating new items
```

### Enhancement Mode

```
Focus on enriching existing linked items with additional context and information
```

## Implementation Steps

1. **Discovery Phase:**

   - Use `mcp__podio-mcp__list_items` with workspace coordinates (`org_label="fvh", space_label="iot-workspace", app_label="datadev-kanban"`) and appropriate filters
   - Use `mcp__github__list_issues` and `mcp__github__search_issues` for comprehensive coverage
   - Build correlation matrix between platforms

2. **Analysis Phase:**

   - Compare titles, descriptions, and metadata
   - Identify status mismatches and missing links
   - Prioritize synchronization actions by impact and urgency

3. **Synchronization Phase:**

   - Execute updates using `mcp__podio-mcp__update_item` (with workspace coordinates) and `mcp__github__update_issue`
   - Create new items/issues where appropriate using `mcp__podio-mcp__create_item` (with workspace coordinates) and `mcp__github__create_issue`
   - Add cross-platform references and context

4. **Validation Phase:**

   - Verify successful updates on both platforms
   - Check for any synchronization conflicts
   - Generate summary report of actions taken

5. **Documentation Phase:**
   - Log synchronization results to appropriate Obsidian note
   - Update cross-reference documentation
   - Store synchronization metadata for future runs

## Error Handling

- **Rate Limiting:** Implement delays between API calls to respect platform limits
- **Conflict Resolution:** Prompt for manual review when automatic resolution isn't clear
- **Rollback Capability:** Track changes for potential rollback if issues arise
- **Validation Checks:** Verify data integrity after synchronization operations

## Memory Integration

- Store synchronization patterns and outcomes using `mcp__graphiti-memory__add_memory`
- Learn from successful synchronization strategies
- Remember user preferences for conflict resolution
- Track platform-specific formatting and linking patterns

## User Interaction Points

- **Conflict Resolution:** Present options when status or information conflicts exist
- **Scope Selection:** Allow user to specify which items/issues to synchronize
- **Approval Gates:** Request confirmation for bulk operations or significant changes
- **Progress Updates:** Provide real-time feedback during synchronization process

## Success Metrics

- Number of items synchronized successfully
- Status alignment improvements
- Information enhancement completeness
- Reduction in manual cross-platform updates needed
- User satisfaction with synchronization accuracy

## TODO: WIP: assimilate the findings here to this command

⏺ Here's the streamlined workflow for updating PR, ticket, and issues:

Steps for Cross-Platform Task Updates

1. Create GitHub PR with comprehensive description including:


    - Summary of changes
    - Reference to Podio ticket using autolink format (#TICKET-XXX)
    - Closes #X statements for issues being resolved (enables auto-close on merge)
    - Test plan and implementation notes

2. Update Podio ticket with status update:


    - Add prominent status section at top of description
    - Link to the GitHub PR
    - List completed items with checkmarks
    - Indicate next phase/steps
    - Preserve original ticket structure and formatting

3. Link GitHub issues in both places:


    - In Podio: Convert issue references to clickable GitHub links
    - In PR: Add Closes #X for each issue completed by the PR

This creates a bidirectional reference system where:

- Podio tracks high-level project status with links to implementation
- GitHub PR automatically closes related issues on merge
- All platforms stay synchronized with current status
