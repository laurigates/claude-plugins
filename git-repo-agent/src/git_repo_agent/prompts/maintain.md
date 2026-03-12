# Maintain Workflow

Execute this maintenance workflow for the target repository.

## Operating Modes

The workflow has three modes, determined by environment variables:

| Mode | Condition | Behavior |
|------|-----------|----------|
| **Interactive** (default) | `FIX_MODE` ≠ "True" AND `REPORT_ONLY` ≠ "True" | Analyze → present findings → ask user → execute selected fixes → report |
| **Auto-fix** | `FIX_MODE` = "True" | Analyze → apply conservative auto-fixes → report |
| **Report-only** | `REPORT_ONLY` = "True" | Analyze → report only, no changes |

## Step 1: Review Repository Analysis

Review the pre-computed `repo_analyze` and `health_score` results in your system prompt:
- Technology stack and tooling
- Overall health score with category breakdown
- Specific findings per category

## Step 2: Triage Findings

Based on the health score, prioritize work:

| Grade | Action |
|-------|--------|
| A (90-100) | Report only, suggest minor improvements |
| B (80-89) | Fix easy wins, report larger items |
| C (70-79) | Focus on weakest categories |
| D (60-69) | Systematic improvement needed |
| F (< 60) | Major gaps, prioritize critical items |

If `--focus` is specified, limit work to those categories only.

## Step 3: Present Plan and Get User Input

In **interactive mode** (default), use `AskUserQuestion` to present findings and let the user choose which fixes to apply. **After the user responds, you MUST proceed to Step 4 to execute their selections.** Do NOT end the session after asking questions — the user's answers drive the next phase.

In **auto-fix mode**, skip this step and proceed directly to Step 4.

In **report-only mode**, skip to Step 5.

## Step 4: Execute Fixes

Execute fixes based on the operating mode:

- **Interactive mode**: Apply exactly the fixes the user selected in Step 3
- **Auto-fix mode**: Apply all conservative auto-fixes

### Auto-fix scope (conservative)
- Lint auto-fixes (run linter with `--fix` flag)
- Documentation date updates (modified/reviewed fields)
- Missing `.gitignore` entries for common patterns
- Missing configuration files with safe defaults

### Delegate to subagents
- **configure** subagent: Linting, formatting, testing, pre-commit gaps
- **docs** subagent: Documentation freshness, accuracy, completeness
- **blueprint** subagent: Blueprint structure, manifest sync

### What NOT to auto-fix
- Test failures (report only)
- Security vulnerabilities (report only)
- Architecture decisions (report only)
- Breaking configuration changes (report only)

## Step 5: Record Health History

After analysis, append a health snapshot to `docs/health-history.json`:

```json
{
  "snapshots": [
    {
      "date": "YYYY-MM-DD",
      "overall_score": 75,
      "grade": "C",
      "category_scores": {
        "docs": 15,
        "tests": 18,
        "security": 12,
        "quality": 16,
        "ci": 14
      },
      "fixed_count": 3,
      "remaining_count": 5
    }
  ]
}
```

Create the file if it doesn't exist. Append to the `snapshots` array if it does.

## Step 6: Generate Report

Output a maintenance report:

```markdown
## Maintenance Report

**Repository:** <name>
**Date:** <date>
**Health Score:** <score>/100 (<grade>)

### Category Breakdown
| Category | Score | Status |
|----------|-------|--------|
| Docs | 15/20 | Needs work |
| Tests | 18/20 | Good |
| Security | 12/20 | Needs work |
| Quality | 16/20 | Good |
| CI | 14/20 | OK |

### Issues Fixed
- <list of auto-fixed items>

### Remaining Issues
- <list of items requiring manual attention>

### Recommendations
- <prioritized improvement suggestions>
```

## Environment Variables

- `FIX_MODE` — if "True", apply auto-fixes
- `REPORT_ONLY` — if "True", generate report without any changes
- `FOCUS_AREAS` — comma-separated category names to focus on
