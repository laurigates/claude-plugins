# Weekly Blueprint Health Check Workflow

## Summary

Create a scheduled GitHub Actions workflow that performs a comprehensive Blueprint documentation health audit weekly, creating a GitHub issue with the report.

## Motivation

Documentation drift happens gradually. A weekly health check catches staleness, missing IDs, broken ADR chains, and coverage gaps before they compound. Complements the existing `changelog-review.yml` weekly schedule.

## Scope

### Workflow: `.github/workflows/blueprint-health.yml`

**Trigger:** `schedule` (Monday 9:00 UTC) + `workflow_dispatch` for manual runs

**Steps:**
1. **Document Inventory:** List all ADRs, PRDs, PRPs with status, dates, and ID coverage
2. **Staleness Check:** Flag documents not modified in 90+ days
3. **ID Coverage:** Identify documents missing Blueprint IDs (reuses `/blueprint:sync-ids --dry-run` logic)
4. **ADR Validation:** Verify relationship chains (supersedes/superseded-by), check for orphaned references
5. **Feature Tracking Summary:** Summarize FR coverage gaps if feature tracker exists

**Output:** Creates a GitHub issue titled `Weekly Blueprint Health: YYYY-MM-DD` with label `blueprint-maintenance`

**Model:** `haiku` (inventory and validation are mechanical checks)

**Permissions:** `contents: read`, `issues: write`

### Implementation Details

- Uses `anthropics/claude-code-action@v1`
- `--model haiku --max-turns 20`
- Checks for existing open issue with same label to avoid duplicates (same pattern as `changelog-review.yml`)
- Report format: markdown tables grouped by check category
- Includes action items with severity levels (info, warning, action-required)

### Acceptance Criteria

- [ ] Runs weekly on schedule + manual trigger
- [ ] Creates GitHub issue with structured report
- [ ] Avoids duplicate issues (checks for existing open issue)
- [ ] Covers: inventory, staleness, IDs, ADR validation, feature tracking
- [ ] No file modifications — report-only
- [ ] Consistent with `changelog-review.yml` patterns

## Labels

`enhancement`, `github-actions`, `blueprint-maintenance`
