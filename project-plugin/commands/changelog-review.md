---
model: opus
description: Review Claude Code changelog for changes impacting plugins
args: [--full] [--since <version>] [--update]
allowed-tools: Bash(git log *), Bash(git diff *), Read, Write, Edit, Glob, Grep, WebFetch, TodoWrite
argument-hint: --full | --since 2.0.0 | --update
created: 2026-01-14
modified: 2026-01-14
reviewed: 2026-01-14
---

# /changelog:review

Analyze Claude Code changelog to identify changes that impact plugin development. Tracks which versions have been reviewed to avoid redundant checks.

## Usage

- `/changelog:review` - Review changes since last check
- `/changelog:review --full` - Review entire changelog
- `/changelog:review --since 2.0.0` - Review changes since specific version
- `/changelog:review --update` - Just update version tracking without report

## Phase 1: Load Current State

### 1.1 Read Version Tracking File

```bash
cat .claude-code-version-check.json 2>/dev/null || echo '{"lastCheckedVersion": "0.0.0"}'
```

Store the `lastCheckedVersion` for comparison.

### 1.2 Handle Arguments

| Argument | Behavior |
|----------|----------|
| (none) | Use lastCheckedVersion as baseline |
| `--full` | Review all versions from changelog |
| `--since X.Y.Z` | Use specified version as baseline |
| `--update` | Skip analysis, just update tracking |

## Phase 2: Fetch Changelog

### 2.1 Fetch Current Changelog

Use WebFetch to retrieve:
```
https://raw.githubusercontent.com/anthropics/claude-code/refs/heads/main/CHANGELOG.md
```

Prompt for analysis:
> Extract all version numbers and their release content. For each version, identify:
> 1. Features (new capabilities)
> 2. Bug fixes
> 3. Breaking changes
> 4. Deprecations
> Focus on changes related to: hooks, skills, commands, agents, permissions, MCP servers, SDK, and plugin development.

### 2.2 Extract Version Numbers

Parse the changelog to identify all version numbers following semantic versioning (X.Y.Z).

## Phase 3: Filter Relevant Changes

### 3.1 Identify New Versions

Compare versions in changelog against the baseline version.
List all versions that are newer than baseline.

### 3.2 Categorize by Impact

For each new version, classify changes:

**High Impact** (requires action):
- Breaking changes to hooks, skills, or commands
- Security fixes affecting permissions
- Deprecated features now removed
- Schema changes for tool inputs/outputs

**Medium Impact** (review recommended):
- New hook events (SessionEnd, SubagentStart, etc.)
- New frontmatter fields (context, agent)
- New permission wildcard patterns
- SDK improvements

**Low Impact** (informational):
- Bug fixes
- Performance improvements
- IDE-specific features

### 3.3 Map to Plugins

For each relevant change, identify affected plugins:

| Change Area | Affected Plugins |
|-------------|------------------|
| Hooks | hooks-plugin, configure-plugin |
| Skills/Commands | All plugins |
| Agents | agents-plugin, agent-patterns-plugin |
| MCP | agent-patterns-plugin |
| Permissions | configure-plugin |
| Git | git-plugin |
| Testing | testing-plugin |

## Phase 4: Generate Report

### 4.1 Create Analysis Report

Structure the report:

```markdown
# Claude Code Changelog Review

**Review Date**: [today's date]
**Versions Reviewed**: [baseline] → [latest]
**Last Check**: [previous date and version]

## Summary

| Category | Count |
|----------|-------|
| New versions | X |
| High-impact changes | X |
| Medium-impact changes | X |
| Action items | X |

## High-Impact Changes

[For each high-impact change:]

### [vX.Y.Z] Change Title

- **Type**: Breaking Change / Security / Deprecation
- **Affected**: plugin1, plugin2
- **Action**: What needs to be done

## Medium-Impact Changes

[For each medium-impact change:]

### [vX.Y.Z] Change Title

- **Type**: New Feature / Enhancement
- **Opportunity**: How plugins could benefit
- **Consider for**: plugin1, plugin2

## Recommended Actions

### Immediate (High Priority)

- [ ] Action item 1
- [ ] Action item 2

### Planned (Medium Priority)

- [ ] Enhancement 1
- [ ] Enhancement 2

## Plugin-Specific Recommendations

### hooks-plugin
[Specific recommendations]

### agent-patterns-plugin
[Specific recommendations]

[etc.]
```

### 4.2 Display Report

Present the report to the user with clear sections and actionable items.

## Phase 5: Update Tracking

### 5.1 Prepare Update

Create updated tracking JSON:

```json
{
  "lastCheckedVersion": "[latest version]",
  "lastCheckedDate": "[today's date]",
  "changelogUrl": "https://raw.githubusercontent.com/anthropics/claude-code/refs/heads/main/CHANGELOG.md",
  "reviewedChanges": [
    {
      "version": "[latest]",
      "date": "[today]",
      "relevantChanges": ["change1", "change2"],
      "actionsRequired": ["action1"]
    },
    // ... previous entries preserved
  ]
}
```

### 5.2 Confirm Update

```
question: "Update version tracking to [latest version]?"
options:
  - "Yes, update tracking"
  - "No, keep current tracking"
```

### 5.3 Write Update

If confirmed, update `.claude-code-version-check.json` with new state.

## Phase 6: Suggest Next Steps

### 6.1 Present Options

```
question: "What would you like to do next?"
options:
  - label: "Create GitHub issues"
    description: "Generate issues for action items"
  - label: "Review a specific plugin"
    description: "Deep-dive into one plugin's changes"
  - label: "Done for now"
    description: "Exit review"
```

### 6.2 Create Issues (if selected)

For each high-priority action item:
1. Draft issue title and body
2. Suggest labels: `changelog-review`, `breaking-change`, `enhancement`
3. Offer to create via `gh issue create`

## Error Handling

| Error | Recovery |
|-------|----------|
| No tracking file | Create with version 0.0.0 |
| Network failure | Retry with exponential backoff |
| Parse failure | Report error, suggest manual review |
| No new versions | Report "up to date" and exit |

## Examples

### First Run (No Previous Check)

```
$ /changelog:review

Checking Claude Code changelog...
No previous version check found. Starting from v0.0.0.

Fetched changelog: 150+ versions available
Analyzing changes since v0.0.0...

[Full report generated]

Update tracking to v2.1.7? [Yes]
```

### Regular Check

```
$ /changelog:review

Last check: 2026-01-07 (v2.1.3)
Fetching current changelog...

New versions found: 2.1.4, 2.1.5, 2.1.6, 2.1.7

## High-Impact Changes

### [v2.1.7] Security fix for wildcard permissions
- Affected: configure-plugin
- Action: Review permission rules

[Report continues...]
```

### Targeted Review

```
$ /changelog:review --since 2.0.0

Reviewing all changes from v2.0.0 to v2.1.7...
Found 30 versions with relevant changes.

[Comprehensive report]
```
