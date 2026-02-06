# Release PR Documentation Audit Workflow

## Summary

Create a GitHub Actions workflow that audits Blueprint documentation (ADRs, PRDs, PRPs) on release PRs. Uses haiku model for cost-effective, mechanical checks.

## Motivation

Release PRs are natural checkpoints to verify documentation stays current. Automated audits catch stale docs, missing frontmatter, and broken cross-references before they accumulate.

## Scope

### Workflow: `.github/workflows/blueprint-doc-audit.yml`

**Trigger:** Pull requests targeting `main` that touch `**/docs/**`, `**/CHANGELOG.md`, or `**/.claude-plugin/**`

**Steps:**
1. List all ADRs, PRDs, and PRPs with status and dates (reuses `/blueprint:docs-list` logic)
2. Flag documents where `modified` date is >90 days old
3. Check ADR cross-references for broken links (references to non-existent docs)
4. Verify all documents have required frontmatter fields (status, created, modified)
5. Post findings as a PR comment — read-only, no file modifications

**Model:** `haiku` (mechanical pattern matching and date comparison)

**Permissions:** `contents: read`, `pull-requests: write`

### Implementation Details

- Uses `anthropics/claude-code-action@v1`
- `--model haiku --max-turns 15`
- Prompt constrains Claude to report-only mode (no `AskUserQuestion`, no file edits)
- Output: markdown table with status indicators posted as PR comment

### Acceptance Criteria

- [ ] Workflow triggers on release PRs and doc-related changes
- [ ] Reports stale documents (>90 days since modified)
- [ ] Validates frontmatter completeness
- [ ] Checks cross-reference integrity
- [ ] Posts structured PR comment with findings
- [ ] No file modifications — purely diagnostic

## Labels

`enhancement`, `github-actions`, `blueprint-maintenance`
