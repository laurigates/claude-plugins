---
created: 2025-12-16
modified: 2026-11-25
reviewed: 2026-11-25
description: "Run all infrastructure standards checks and fixes. Use when onboarding a new project, doing a full compliance audit, or batch-fixing with --fix."
allowed-tools: Glob, Grep, Read, Write, Edit, Bash(bash ${CLAUDE_SKILL_DIR}/scripts/list-components.sh *), Bash(bash ${CLAUDE_SKILL_DIR}/scripts/detect-relevance.sh *), Bash(find *), Bash(grep *), AskUserQuestion, TodoWrite, SlashCommand, Agent
args: "[--check-only] [--fix] [--type <frontend|node|infrastructure|python|rust>]"
argument-hint: "[--check-only] [--fix] [--type <frontend|node|infrastructure|python|rust>]"
name: configure-all
---

# /configure:all

Run all infrastructure standards compliance checks, ranked by what the repo has.

## When to Use This Skill

| Use this skill when... | Use another approach when... |
|------------------------|------------------------------|
| Performing comprehensive infrastructure audit | Checking single component (use specific `/configure:X` skill) |
| Setting up new project with all standards | Project already has all standards configured |
| CI/CD compliance validation | Need detailed status only (use `/configure:status`) |
| Running initial configuration | Interactive component selection needed (use `/configure:select`) |
| Batch-fixing all compliance issues with `--fix` | Manual review of each component preferred |

## Context

- Project standards: !`find . -maxdepth 1 -name '.project-standards.yaml'`
- Project type indicators: !`find . -maxdepth 1 \( -name 'package.json' -o -name 'pyproject.toml' -o -name 'Cargo.toml' -o -name '*.tf' \)`
- Infrastructure dirs: !`find . -maxdepth 1 -type d \( -name 'terraform' -o -name 'helm' -o -name 'argocd' \)`

## Parameters

Parse from command arguments:

- `--check-only`: Report status without offering fixes (CI/CD mode)
- `--fix`: Apply all fixes automatically without prompting
- `--type <type>`: Override auto-detected project type (frontend, node, infrastructure, python, rust)

## Execution

### Step 1: Rank every component for this repo

The roster is [components.yaml](components.yaml). Never hand-maintain a component
list or decide relevance in prose; run the detector, which lists the roster and
tiers each row from file indicators:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/detect-relevance.sh" --project-dir .
```

Pass `--type <type>` through when the user gave one. If it reports
`STATUS=ERROR`, stop and surface the `ISSUES:` block: the manifest and the
skills on disk have drifted.

Output: `PROJECT_TYPE=` (and `PROJECT_TYPE_SOURCE=`: `override`, `standards_file`
or `detected`), `STANDARDS_VERSION=`, `SIGNAL_*=` booleans, then one
`RELEVANCE=<component> TIER=<APPLY|REVIEW|SKIP> REASON=...` row per component.
Report the detected type against the tracked one when they differ. The tiers
and signals are in [REFERENCE.md](REFERENCE.md#relevance-tiers).

### Step 2: Run the checks

For each `APPLY` row, then each `REVIEW` row, invoke the component in
check-only mode with the SlashCommand tool, e.g.
`COMPONENT=configure-tests` runs `/configure:tests --check-only`. `SKIP` rows are
not run; list them in the report with their `REASON`. Collect each result.

### Step 3: Heavy path — parallel check fan-out (optional)

Step 2 is sequential and stays the default. Fan out only when all hold:

| Condition | Why |
|-----------|-----|
| **15 or more** `APPLY` + `REVIEW` rows | Below ~15, sequential is cheaper than 15 agent preambles; the harness aborts under it |
| A check, not a fix | `--fix` never enters the workflow (Step 5) |
| The detector returned `STATUS=OK` | An empty roster has no fan-out width |

The harness needs `Agent` in `allowed-tools` and `SlashCommand` in each check
agent's toolset (without it the agent re-derives the check instead of invoking
`/configure:<component> --check-only`). Pass `args.roster` as the detector's
`RELEVANCE=` rows (`component`, `tier`, `reason`); the harness skips `SKIP`
rows itself. The synthesis stage is a **barrier**: the fix plan must see every
component at once, because pre-commit and linting both write
`.pre-commit-config.yaml`. The scale guard asks before every run.
See [Workflow harness](#workflow-harness-template).

### Step 4: Generate compliance report

Print a summary table grouped by tier with PASS/WARN/FAIL per component, the
`SKIP` rows with reasons, overall counts, and the issues to fix. Template:
[REFERENCE.md](REFERENCE.md#report-template).

### Step 5: Apply fixes (if requested)

With `--fix` or on confirmation, run each failing `APPLY` component with
`--fix`, sequentially. Confirm each `REVIEW` component with AskUserQuestion
before fixing it. Components that write the same file are never fixed in
parallel. Branching, commit grouping, parallel agents, stacked-PR merge order
and follow-up issues: [references/fix-phase.md](references/fix-phase.md).
Known traps: [references/gotchas.md](references/gotchas.md).

### Step 6: Update standards tracking

Create or update `.project-standards.yaml` using `STANDARDS_VERSION=` from the
detector (defined once, in `components.yaml`) and the detected project type.
Template: [REFERENCE.md](REFERENCE.md#standards-tracking-template).

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Rank components for this repo | `bash "${CLAUDE_SKILL_DIR}/scripts/detect-relevance.sh" --project-dir .` |
| Quick compliance check (all components) | `/configure:all --check-only` |
| Auto-fix all issues | `/configure:all --fix` |
| Check standards file validity | `test -f .project-standards.yaml && cat .project-standards.yaml \| head -10` |
| List project type indicators | `find . -maxdepth 1 \( -name 'package.json' -o -name 'pyproject.toml' -o -name 'Cargo.toml' \) -exec basename {} \;` |

## Flags

| Flag | Description |
|------|-------------|
| `--check-only` | Report status without offering fixes |
| `--fix` | Apply all fixes automatically |
| `--type <type>` | Override project type (frontend, node, infrastructure, python, rust) |

## Exit Codes (for CI)

| Code | Meaning |
|------|---------|
| 0 | All checks passed |
| 1 | Warnings found (non-blocking) |
| 2 | Failures found (blocking) |

A workflow returns a value, not a process status, so `exitCode` cannot come from
the harness. When the Step 3 path is taken, this skill maps the returned
`report.overall` onto the table above: `PASS` → 0, `WARN` → 1, `FAIL` → 2.

## Workflow harness (template)

`workflows/configure-all-check.workflow.js` ships beside this skill. **It is a
TEMPLATE to adapt, not a script to run verbatim.** Read it, then rewrite it for
the work in front of you.

**Adapt freely:** the check and synthesis agent prompts, the wave width, the
`ambiguous` handling, the schema's optional fields, and the shape of the
`fixPlan` entries.

**Preserve across any adaptation:** (a) the loop bound is the detector's
`RELEVANCE=` rows (or the lister's `COMPONENT=` rows) passed in as
`args.roster`, never a prose "for each component", and applicability stays the
pure expression `tier !== 'SKIP'` (rows without a tier: `types === 'all' ||
types.split(',').includes(projectType)`), so no agent classifies a field;
(b) `CHECK_SCHEMA`'s closed `PASS|WARN|FAIL|ERROR` status enum, plus the `files`
array that makes contention detectable, so a vague verdict is structurally
impossible and a null return becomes an explicit `ERROR` row; (c) the
Synthesize stage is a barrier. Two consequences of (c) are also non-negotiable:
the checks are **read-only**, and `--fix` is applied outside the workflow,
sequentially.

**Agent budget:** 1 + components. The wave width bounds how many run at once, not
how many run. **Skip the harness when** fewer than ~15 components are
applicable, the run checks a single component, or the detector reported
`STATUS=ERROR`.

## See Also

- `/configure:select` - Interactively select which components to configure
- `/configure:status` - Quick read-only status overview
- [components.yaml](components.yaml) - The authoritative component roster and standards version
- [references/fix-phase.md](references/fix-phase.md) - Applying fixes across one repo
- [references/gotchas.md](references/gotchas.md) - Traps met applying fixes
