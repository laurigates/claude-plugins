# Diagnose Workflow

Execute this pipeline diagnostics workflow for the target repository.

## Step 1: Review Pre-computed Diagnostics

Review the pre-computed pipeline diagnostics in your system prompt:

- Which sources returned data and which were unavailable
- Repository analysis (technology stack, CI system)
- Initial signals: failing pods, out-of-sync apps, failed workflows

## Step 2: Delegate Analysis

Delegate to the `diagnose` subagent with instructions to:

1. Analyse all pre-computed diagnostic data
2. Correlate findings across sources by timestamp
3. Identify the failure chain (root cause → propagation → impact)
4. Classify severity (CRITICAL/HIGH/MEDIUM/LOW)
5. Produce the structured diagnostic report

The diagnose subagent may run additional read-only commands if the pre-computed data is insufficient. Safety hooks enforce kubectl/argocd read-only constraints.

## Step 3: Review Diagnostic Report

After the diagnose subagent returns its report:

1. Validate that findings are consistent and well-supported
2. Ensure severity classification matches the evidence
3. Check that recommended actions are actionable

## Step 4: Issue Creation

If `CREATE_ISSUE` is "True" and `DRY_RUN` is not "True":

1. Search for existing open issues with `[Pipeline Diagnostics]` prefix to avoid duplicates
2. Create a GitHub issue using `mcp__github__issue_write` with:
   - **Title:** `[Pipeline Diagnostics] <concise root cause summary>`
   - **Labels:** `pipeline`, `diagnostics`, and severity label (`critical`, `high`, `medium`, or `low`)
   - **Body:** Full diagnostic report from the diagnose subagent

If `DRY_RUN` is "True", display the issue that would be created without actually creating it.

## Step 5: Report

Output a summary to the user:

```markdown
## Diagnostics Summary

**Sources checked:** <list of sources and their availability>
**Severity:** <classification>

### Key Findings
- <top 3 findings across all sources>

### Recommended Actions
- <top 3 recommended actions>

### Issue
- <GitHub issue URL if created, or "Dry run — issue not created">
```

## Environment Variables

- `CREATE_ISSUE` — if "True", create GitHub issue with findings
- `DRY_RUN` — if "True", display diagnostics without creating issues
- `DIAGNOSTIC_SOURCES` — comma-separated sources or "auto" for auto-detection
- `K8S_NAMESPACE` — Kubernetes namespace for kubectl/argocd queries
- `ARGOCD_APP` — ArgoCD application name
