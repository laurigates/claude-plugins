# Maintain Workflow

Execute this maintenance workflow for the target repository.

## Operating Modes

The workflow has three modes, determined by environment variables:

| Mode | Condition | Behavior |
|------|-----------|----------|
| **Interactive** (default) | `FIX_MODE` ≠ "True" AND `REPORT_ONLY` ≠ "True" | Analyze → present findings → [orchestrator prompts user] → execute selected fixes → report |
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

## Step 3: Present Findings

In **interactive mode** (default), present your analysis as a numbered list of actionable findings. For each finding include:

- **Number** (sequential, starting at 1)
- **Category** in brackets: `[docs]`, `[tests]`, `[security]`, `[quality]`, `[ci]`
- **Description** of the issue
- **Fix type**: `auto-fixable` or `report-only`

Example output format:

```
1. [docs] README.md missing installation instructions — auto-fixable
2. [security] Dependency has known CVE — report-only
3. [quality] ESLint not configured — auto-fixable
4. [tests] 2 test failures in auth module — report-only
```

Mark items that should NOT be auto-fixed (test failures, security vulnerabilities, architecture decisions) as "report-only".

**In the analysis phase only: end your response after presenting the numbered findings list.** Do NOT use `AskUserQuestion`. The orchestrator will prompt the user for their selections in Python and then start a new session for the execution phase with the findings list and selections embedded in its user prompt. This "stop after findings" instruction does NOT apply when you see a "Phase 2 Override (execution)" section in your system prompt.

In **auto-fix mode**, skip this step and proceed directly to Step 4.

In **report-only mode**, present the full findings list with ALL items marked as `report-only` (since no fixes will be applied), then skip Step 4 and proceed to Step 5.

## Step 4: Execute Fixes

Execute fixes based on the operating mode:

- **Interactive mode**: In the execution phase you will receive a **fresh user prompt** from the orchestrator containing (a) the full numbered findings list from the analysis phase and (b) the user's selections (e.g., "1,3,5" or "all"). This is a new session — treat the embedded findings list as authoritative. Apply exactly the fixes corresponding to the user's selections by making real tool calls (Edit, Write, Bash). Do NOT re-run the analysis; do NOT present findings again; do NOT ask the user anything.
- **Auto-fix mode**: Apply all conservative auto-fixes

### Auto-fix scope (conservative)
- Lint auto-fixes (run linter with `--fix` flag)
- Documentation date updates (modified/reviewed fields)
- Missing `.gitignore` entries for common patterns
- Missing configuration files with safe defaults

### Delegate to subagents
- **configure** subagent: Linting, formatting, testing, pre-commit gaps
- **docs** subagent: Documentation freshness, accuracy, completeness

> Blueprint structure/manifest sync is available via the
> `git-repo-agent blueprint sync` / `upgrade` CLI commands (ADR-006). There
> is no blueprint subagent to delegate to from this workflow.

### Git Worktree

When making changes (interactive or auto-fix mode), you are working in a git worktree on a dedicated branch. Commit your changes directly to the current branch. Do NOT create new branches or push — the orchestrator manages the worktree and PR creation.

When committing dependency changes, always include lock files (uv.lock, package-lock.json, yarn.lock, pnpm-lock.yaml, bun.lockb, Cargo.lock, poetry.lock, go.sum) in the commit.

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
