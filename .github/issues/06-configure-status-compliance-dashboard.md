# Infrastructure Compliance Dashboard Workflow

## Summary

Create a scheduled workflow that runs `/configure:status` logic across all plugins to produce an infrastructure compliance report — tracking which plugins meet standards for pre-commit, release-please, CI/CD, security scanning, and documentation.

## Motivation

The configure-plugin has 42 skills covering infrastructure standards. Currently, compliance is checked manually via `/configure:status`. Automating this provides a continuous compliance dashboard that tracks drift over time.

## Scope

### Workflow: `.github/workflows/compliance-dashboard.yml`

**Trigger:** `schedule` (1st and 15th of month, 9:00 UTC) + `workflow_dispatch`

**Steps:**
1. **Standards Inventory:** Check each plugin against infrastructure standards:
   - Has `plugin.json` with all recommended fields
   - Listed in `marketplace.json` with correct version
   - Configured in `release-please-config.json`
   - Has `README.md` with skill table
   - Has `CHANGELOG.md`
2. **Cross-Cutting Compliance:**
   - Pre-commit hooks configured (if applicable)
   - Release-please version sync (plugin.json ↔ manifest)
   - Skill frontmatter date freshness (reviewed date <6 months old)
3. **Compliance Score:** Calculate per-plugin and overall compliance percentage

**Output:** Creates/updates a GitHub issue titled `Infrastructure Compliance: YYYY-MM-DD`

**Model:** `haiku` (checklist verification, no reasoning needed)

**Permissions:** `contents: read`, `issues: write`

### Report Structure

```markdown
## Infrastructure Compliance Report: YYYY-MM-DD

### Overall Score: XX%

### Per-Plugin Compliance
| Plugin | plugin.json | marketplace | release-please | README | CHANGELOG | Score |
|--------|-------------|-------------|----------------|--------|-----------|-------|

### Gaps
...

### Recommendations
...
```

### Relationship to Existing Workflows

- Extends `validate-plugin-configs.yml` (which only runs on PRs with changes)
- Uses `/configure:status` skill logic but in unattended mode
- Complements the agentic quality audit (Issue #5) with infrastructure focus

### Acceptance Criteria

- [ ] Runs bi-monthly on schedule + manual trigger
- [ ] Checks all plugins against infrastructure standards
- [ ] Calculates compliance score per-plugin and overall
- [ ] Creates structured GitHub issue with compliance matrix
- [ ] Identifies specific gaps with remediation steps
- [ ] Read-only — no file modifications

## Labels

`enhancement`, `github-actions`, `configure-plugin`, `compliance`
