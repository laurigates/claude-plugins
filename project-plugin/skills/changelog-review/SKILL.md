---
name: changelog-review
description: Claude Code changelog analysis for plugin impact. Use when checking new features, breaking changes, or upgrade opportunities from a Claude Code release.
user-invocable: false
allowed-tools: Bash(git log *), Bash(git diff *), Read, Write, Edit, Glob, Grep, WebFetch, TodoWrite
created: 2026-01-14
modified: 2026-07-06
reviewed: 2026-07-06
---

# Claude Code Changelog Review

## When to Use This Skill

| Use this skill when... | Use another skill instead when... |
|---|---|
| Reviewing Claude Code releases for breaking changes that affect plugins | Distilling project session learnings into rules and recipes |
| Discovering new Claude Code features that plugins can leverage | Use project-skill-scripts instead when auditing skills for script-extraction wins |
| Tracking deprecations before they break installed plugins | Use project-continue instead when resuming feature work, not platform review |

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

For the human-readable review report template (Summary / High-Impact /
Medium-Impact / Action Items / Next Steps), see [REFERENCE.md](REFERENCE.md).
The CI path opens a triage issue instead — see Automation Integration below.

## Automation Integration

The `.github/workflows/changelog-review.yml` workflow runs this review weekly.
It is a thin caller of the org reusable workflow
`laurigates/.github/.github/workflows/reusable-changelog-review.yml@main`
(issue #1304): the schedule, dispatch input, and repo-specific inputs (analyzer
path, commit scope, rule-file sections, plugin list) live in the caller; the
two-job pipeline (bash pre-check gate → opus triage) lives upstream. The
analyzer script and its tests stay in this repo and are handed to the reusable
workflow via its `analyzer-script` input, so the analysis logic remains
reviewable and unit-tested here:

```bash
bash scripts/analyze-changelog.sh --excerpt <slice> --repo-dir . \
  --tracked <ver> --latest <ver>
```

The script (`scripts/analyze-changelog.sh`, tested by
`scripts/tests/test-analyze-changelog.sh`) emits structured `KEY=VALUE` output
and, beyond keyword counts, carries a **deprecation/removal → plugin-code
bridge**: for any tool/setting/command named in a deprecation **or BREAKING
removal** line, it greps this repo's skills/hooks/agents/rules and surfaces the
files that still reference it as triage candidates. Two miss classes drive this:

- **#1638** — a deprecated identifier (e.g. `TaskOutput`) that stayed referenced
  in a hook script because the old keyword map only ever pointed at
  `.claude/rules/*.md`. Caught by the `deprecat|removed|renamed|unshipped` forms.
- **#1733** — a BREAKING tool removal phrased verb-after with a `/`-separated
  pair (`BREAKING: `TeamCreate`/`TeamDelete` tools removed`, 2.1.178) that the
  deprecation-grammar forms missed, leaving the `agent-patterns-plugin:agent-teams`
  skill referencing removed tools unflagged. Caught by the BREAKING-line
  extractor.

**Reviewing the changelog is never doc-only.** Every run treats updating rule
docs *and* fixing plugin **code** that references a removed/renamed
tool/setting/env-var as part of the same task — the `ACTIONABLE_DEPRECATION`
candidates are the highest-priority section of the tracking issue, and a
referenced removed identifier is a correctness bug (the skill would instruct
Claude to call a tool that no longer exists), not just stale prose.

Workflow flow:

1. Run weekly on schedule
2. Fetch changelog and compare versions (skip-if-exists is drift-aware: an open
   but unactioned tracking issue no longer suppresses *newer* versions)
3. If new versions found: run the analyzer, open ONE tracking issue (highest
   priority = deprecated identifiers still referenced in our code), ratchet the
   version JSON via a tiny PR
4. Label issues appropriately

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Analyze a changelog slice (structured `KEY=VALUE`) | `bash scripts/analyze-changelog.sh --excerpt <slice> --repo-dir . --tracked <ver> --latest <ver>` |
| Triage filter — code-compliance candidates only | `… analyze-changelog.sh … \| grep -E '^(ACTIONABLE_DEPRECATION\|DEPRECATED_TOKENS)='` |
| List the surfaced candidate files | `… analyze-changelog.sh … \| sed -n '/^CANDIDATES:/,/^=== END/p'` |
| Roll-up status only | `… analyze-changelog.sh … \| grep -E '^(STATUS\|ISSUE_COUNT)='` |
| Run the analyzer regression tests | `bash project-plugin/skills/changelog-review/scripts/tests/test-analyze-changelog.sh` |

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
