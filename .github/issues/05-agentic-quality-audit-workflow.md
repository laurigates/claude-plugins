# Agentic Quality Audit Workflow

## Summary

Create a scheduled GitHub Actions workflow that audits all skills across all plugins for agentic optimization compliance — checking for compact output, fail-fast patterns, machine-readable output, and proper permission granularity.

## Motivation

With 285+ skills across 31 plugins, quality can drift. The existing `skill-quality-review.yml` only checks changed files in PRs. A scheduled audit covers the full inventory and catches regressions or skills that predate current quality standards.

## Scope

### Workflow: `.github/workflows/agentic-quality-audit.yml`

**Trigger:** `schedule` (1st of each month, 9:00 UTC) + `workflow_dispatch`

**Steps:**
1. **Skill Inventory:** Scan all `**/skills/**/SKILL.md` files
2. **Quality Checks per skill:**
   - Has "Agentic Optimizations" table (for CLI/tool skills)
   - Has "When to Use" decision table
   - Under 500 lines (or has REFERENCE.md)
   - Uses granular `Bash(command *)` permission patterns (not broad `Bash`)
   - Model selection matches task complexity
   - Description matches user intents (not tool jargon)
   - Frontmatter has all required date fields
3. **Cross-Plugin Analysis:**
   - Identify duplicate coverage across plugins
   - Flag skills with overlapping descriptions
   - Check for skills missing from marketplace.json
4. **Trend Tracking:** Compare against previous audit (if stored)

**Output:** Creates GitHub issue with full audit report, categorized by severity

**Model:** `haiku` (pattern matching against known quality rules)

**Permissions:** `contents: read`, `issues: write`

### Implementation Details

- Uses `anthropics/claude-code-action@v1`
- `--model haiku --max-turns 30` (needs to scan many files)
- Reuses logic from `/health:agentic-audit` skill
- Groups findings by: critical (missing required sections), warning (suboptimal patterns), info (suggestions)
- Includes plugin-level summary table and per-skill detail

### Report Structure

```markdown
## Monthly Agentic Quality Audit: YYYY-MM

### Executive Summary
- X skills audited across Y plugins
- A critical issues, B warnings, C suggestions

### Plugin Summary
| Plugin | Skills | Critical | Warning | Info |
|--------|--------|----------|---------|------|

### Critical Issues
...

### Warnings
...

### Suggestions
...
```

### Acceptance Criteria

- [ ] Runs monthly on schedule + manual trigger
- [ ] Audits all skills across all plugins (not just changed files)
- [ ] Checks all quality criteria from `.claude/rules/skill-quality.md`
- [ ] Creates structured GitHub issue with findings
- [ ] Groups by severity (critical/warning/info)
- [ ] Includes plugin-level summary and per-skill detail
- [ ] Avoids duplicate open issues

## Labels

`enhancement`, `github-actions`, `skill-quality`
