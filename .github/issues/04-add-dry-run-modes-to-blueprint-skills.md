# Add --dry-run / --report-only Modes to Blueprint Skills

## Summary

Add `--dry-run` or `--report-only` argument modes to interactive Blueprint skills so they can run unattended in GitHub Actions workflows without triggering `AskUserQuestion` prompts.

## Motivation

Several Blueprint skills produce valuable maintenance reports but require user interaction (`AskUserQuestion`) in their normal flow. Adding a report-only mode makes them suitable for CI/CD automation while preserving the interactive experience for CLI users.

## Scope

### Skills to Modify

| Skill | Current Model | Interaction | Proposed Flag |
|-------|---------------|-------------|---------------|
| `/blueprint:sync` | opus | Asks what to regenerate | `--dry-run` — reports stale content only |
| `/blueprint:adr-validate` | haiku | May prompt for fixes | `--report-only` — validates and reports, no edits |
| `/blueprint:status` | opus | May prompt for upgrades | `--report-only` — status output only |
| `/blueprint:sync-ids` | opus | Confirms ID assignments | `--dry-run` — reports missing IDs only |
| `/blueprint:feature-tracker-sync` | opus | Confirms sync changes | `--summary` (may already exist) — progress report only |

### Implementation Pattern

For each skill, add to the frontmatter:

```yaml
args: "[--dry-run|--report-only]"
```

In the skill body, add a conditional section:

```markdown
## Parameters

- `--dry-run` / `--report-only`: Generate report without modifications or user prompts.
  When set, do NOT use AskUserQuestion or modify any files. Output findings as
  structured markdown to stdout.
```

### Output Format (standardized)

All dry-run outputs should follow a consistent format:

```markdown
## Blueprint Maintenance Report: <skill-name>

**Date:** YYYY-MM-DD
**Mode:** dry-run (no changes made)

### Findings

| Item | Status | Details |
|------|--------|---------|
| ... | ... | ... |

### Summary
- X items checked
- Y issues found
- Z actions recommended
```

### Acceptance Criteria

- [ ] All 5 listed skills support `--dry-run` or `--report-only` flag
- [ ] Dry-run mode produces structured markdown output
- [ ] Dry-run mode never uses `AskUserQuestion`
- [ ] Dry-run mode never modifies files (no Write, Edit, or Bash writes)
- [ ] Interactive mode is unchanged (backwards compatible)
- [ ] Standardized report format across all skills
- [ ] Skills document the flag in their frontmatter `args` field

## Dependencies

This issue is a prerequisite for effective use of:
- Issue #2 (Weekly Blueprint Health Check) — uses dry-run for deeper analysis
- Issue #5 (Agentic Quality Audit) — may use report-only for broader scope

## Labels

`enhancement`, `blueprint-plugin`, `automation-enablement`
