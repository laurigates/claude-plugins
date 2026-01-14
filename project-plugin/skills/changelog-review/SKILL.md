---
name: changelog-review
description: |
  Analyze Claude Code changelog for changes that impact plugin development.
  Use when checking for new features, breaking changes, or opportunities to
  improve plugins based on Claude Code updates.
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, WebFetch, TodoWrite
created: 2026-01-14
modified: 2026-01-14
reviewed: 2026-01-14
---

# Claude Code Changelog Review

Expertise for analyzing Claude Code changelog and identifying impacts on plugin development.

## Core Purpose

Review Claude Code releases to:
- Identify breaking changes requiring plugin updates
- Discover new features plugins can leverage
- Track deprecations before they become problems
- Ensure plugins follow current best practices

## Change Categories

### High Impact (Action Required)

| Category | Example Changes | Action |
|----------|----------------|--------|
| Breaking changes | API changes, renamed tools | Update affected plugins immediately |
| Security fixes | Permission vulnerabilities | Review and update permission rules |
| Deprecations | Removed features/fields | Remove deprecated usage |
| Hook changes | New events, schema changes | Update hooks-plugin |

### Medium Impact (Review Recommended)

| Category | Example Changes | Action |
|----------|----------------|--------|
| New features | New tools, frontmatter fields | Consider plugin enhancements |
| Permission updates | New wildcard patterns | Update permission documentation |
| SDK changes | New callbacks, streaming | Update SDK-related skills |
| MCP improvements | OAuth, server configs | Update agent-patterns-plugin |

### Low Impact (Information Only)

| Category | Example Changes | Action |
|----------|----------------|--------|
| Bug fixes | UI improvements | Note in changelog |
| Performance | Startup optimizations | No action needed |
| IDE features | VS Code updates | No action needed |

## Plugin Impact Matrix

Map changelog categories to plugins:

| Claude Code Area | Affected Plugins |
|------------------|------------------|
| Hooks | hooks-plugin, configure-plugin |
| Skills/Commands | All plugins with skills/commands |
| Agents | agents-plugin, agent-patterns-plugin |
| MCP servers | agent-patterns-plugin |
| Permissions | configure-plugin, hooks-plugin |
| Git operations | git-plugin |
| Testing tools | testing-plugin |
| SDK changes | agent-patterns-plugin |

## Version Tracking

Version state stored in `.claude-code-version-check.json`:

```json
{
  "lastCheckedVersion": "2.1.7",
  "lastCheckedDate": "2026-01-14",
  "changelogUrl": "https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md",
  "reviewedChanges": [
    {
      "version": "2.1.7",
      "date": "2026-01-14",
      "relevantChanges": [],
      "actionsRequired": []
    }
  ]
}
```

## Analysis Process

### Step 1: Fetch Current State

```bash
# Read last checked version
cat .claude-code-version-check.json | jq -r '.lastCheckedVersion'
```

### Step 2: Fetch Changelog

Use WebFetch to get the current changelog from:
`https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md`

### Step 3: Identify New Versions

Compare fetched changelog versions against lastCheckedVersion.
Extract all changes since that version.

### Step 4: Categorize Changes

For each change, determine:
1. Impact level (high/medium/low)
2. Affected plugins
3. Required action

### Step 5: Generate Report

Produce a report with:
- New versions found
- High-impact changes requiring immediate action
- Medium-impact changes worth reviewing
- Suggestions for plugin improvements

### Step 6: Update Version Tracking

Update `.claude-code-version-check.json` with:
- New lastCheckedVersion
- New lastCheckedDate
- Summary of reviewed changes

## Change Detection Patterns

### Breaking Changes

Look for:
- "BREAKING" or "Breaking Change" headers
- "Removed" sections
- "Migrat" keywords
- "deprecated" becoming "removed"

### Hook System Changes

Look for:
- "hook" mentions in features
- New hook events (SessionStart, SessionEnd, SubagentStart, etc.)
- Schema changes for hook input/output
- Permission decision updates

### Skill/Command Changes

Look for:
- "skill" or "slash command" mentions
- Frontmatter field changes
- Discovery mechanism updates
- New fields like "context: fork"

### Agent/Subagent Changes

Look for:
- "agent" or "subagent" mentions
- Task tool changes
- Agent configuration options
- New agent types

### Permission Changes

Look for:
- "permission" mentions
- Wildcard pattern updates
- Security fixes
- Bash permission changes

## Report Format

```markdown
# Claude Code Changelog Review

**Review Date**: YYYY-MM-DD
**Versions Reviewed**: X.X.X to Y.Y.Y
**Previous Check**: YYYY-MM-DD (vX.X.X)

## Summary

- **New versions**: N
- **High-impact changes**: N
- **Medium-impact changes**: N
- **Action items**: N

## High-Impact Changes

### [Version] - Change Title

**Impact**: Breaking/Security/Deprecation
**Affected plugins**: plugin1, plugin2
**Required action**: Description of what needs to be done

## Medium-Impact Changes

### [Version] - Change Title

**Impact**: New feature/Enhancement
**Opportunity**: How plugins could benefit
**Suggested plugins**: plugin1, plugin2

## Action Items

- [ ] Item 1 (high priority)
- [ ] Item 2 (medium priority)

## Next Steps

1. Create issues for high-priority items
2. Schedule review of medium-impact changes
3. Update version tracking file
```

## Automation Integration

For GitHub Actions workflow:

1. Run weekly on schedule
2. Fetch changelog and compare versions
3. If new versions found:
   - Generate analysis report
   - Create GitHub issue with findings
   - Update version tracking file
4. Label issues appropriately

## Quick Reference

### Relevant Claude Code URLs

| Resource | URL |
|----------|-----|
| Changelog | https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md |
| Documentation | https://docs.anthropic.com/en/docs/claude-code |
| GitHub | https://github.com/anthropics/claude-code |

### Version Number Format

Claude Code uses semantic versioning: `MAJOR.MINOR.PATCH`

- MAJOR: Breaking changes
- MINOR: New features
- PATCH: Bug fixes

### Issue Labels

| Label | Use For |
|-------|---------|
| `changelog-review` | All changelog-related issues |
| `breaking-change` | Breaking changes requiring updates |
| `enhancement` | New feature opportunities |
| `maintenance` | General housekeeping |
