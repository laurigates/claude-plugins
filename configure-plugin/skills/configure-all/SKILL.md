---
created: 2025-12-16
modified: 2026-08-08
reviewed: 2026-08-08
description: "Run all infrastructure standards checks and fixes. Use when onboarding a new project, doing a full compliance audit, or batch-fixing with --fix."
allowed-tools: Glob, Grep, Read, Write, Edit, Bash, AskUserQuestion, TodoWrite, SlashCommand, Agent
args: "[--check-only] [--fix] [--type <frontend|infrastructure|python>]"
argument-hint: "[--check-only] [--fix] [--type <frontend|infrastructure|python>]"
name: configure-all
---

# /configure:all

Run all infrastructure standards compliance checks.

## When to Use This Skill

| Use this skill when... | Use another approach when... |
|------------------------|------------------------------|
| Performing comprehensive infrastructure audit | Checking single component (use specific `/configure:X` skill) |
| Setting up new project with all standards | Project already has all standards configured |
| CI/CD compliance validation | Need detailed status only (use `/configure:status`) |
| Running initial configuration | Interactive component selection needed (use `/configure:select`) |
| Batch-fixing all compliance issues with `--fix` | Manual review of each component preferred |

## Context

- Project standards: !`find . -maxdepth 1 -name \'.project-standards.yaml\'`
- Project type indicators: !`find . -maxdepth 1 \( -name 'package.json' -o -name 'pyproject.toml' -o -name 'Cargo.toml' -o -name '*.tf' \)`
- Infrastructure dirs: !`find . -maxdepth 1 -type d \( -name 'terraform' -o -name 'helm' -o -name 'argocd' \)`
- Current standards version: !`find . -maxdepth 1 -name '.project-standards.yaml' -exec grep -m1 "^standards_version:" {} +`

## Parameters

Parse from command arguments:

- `--check-only`: Report status without offering fixes (CI/CD mode)
- `--fix`: Apply all fixes automatically without prompting
- `--type <type>`: Override auto-detected project type (frontend, infrastructure, python)

## Execution

Execute this comprehensive infrastructure standards compliance check:

### Step 1: Detect project type

1. Read `.project-standards.yaml` if it exists
2. Auto-detect project type from file indicators:
   - **infrastructure**: Has `terraform/`, `helm/`, `argocd/`, or `*.tf` files
   - **frontend**: Has `package.json` with vue/react dependencies
   - **python**: Has `pyproject.toml` or `requirements.txt`
3. Apply `--type` override if provided
4. Report detected vs tracked type if different

### Step 2: List components from the manifest

The component roster lives in [components.yaml](components.yaml) — the single
source of truth. Never hand-maintain a component list here; run the lister:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/list-components.sh"
```

Each `COMPONENT=<name> DOMAIN=<domain> HAS_SCRIPT=<bool> TYPES=<types>` line is
one component skill. If the lister reports `STATUS=ERROR`, stop and surface the
`ISSUES:` block — the manifest and the skills on disk have drifted.

### Step 3: Run all checks

For each listed component whose `TYPES` includes the detected project type
(`TYPES=all` always applies), invoke it in check-only mode using the
SlashCommand tool — e.g. `COMPONENT=configure-tests` runs:

```
/configure:tests --check-only
```

Skip components whose `TYPES` excludes the detected project type, and report
them as SKIP. For finer applicability judgment (e.g. Skaffold only when a
`k8s/` dir exists), see [REFERENCE.md](REFERENCE.md).

Collect results from each check.

### Step 3b: Heavy path — parallel check fan-out (optional)

Step 3 is a sequential pass and stays the default. When the applicable set is
large, the same work can be split across one read-only check agent per roster
row using the bundled harness — see
[`## Workflow harness (template)`](#workflow-harness-template) below and
[`workflows/configure-all-check.workflow.js`](workflows/configure-all-check.workflow.js).

Take this path only when all of the following hold:

| Condition | Why |
|-----------|-----|
| **15 or more applicable components** | Below ~15, the sequential path is cheaper than 15 agent preambles. This floor is enforced in the harness, which aborts under it. |
| The run is a **check**, not a fix | `--fix` never enters the workflow — see Step 5 |
| The lister returned `STATUS=OK` | An empty or errored roster aborts the harness; there is no fan-out width to read |

Two things the harness needs that this skill's frontmatter now grants:

1. **`Agent`** in `allowed-tools` — without it the skill cannot dispatch at all.
2. **`SlashCommand` in each check agent's own toolset** — without it the agent
   re-derives a component check from scratch instead of invoking
   `/configure:<component> --check-only`, which is the whole point.

The applicability filter is not delegated. `types === 'all' ||
types.split(',').includes(projectType)` is manifest data the lister already
emits, so no agent decides it. Finer judgements the manifest cannot express
(Skaffold only when a `k8s/` dir exists — see [REFERENCE.md](REFERENCE.md)) are
resolved here, before dispatch, and passed in as `ambiguous`.

The synthesis stage is a **barrier**: the fix plan must see every component at
once, because no single check agent can know that pre-commit and linting both
write `.pre-commit-config.yaml`.

### Step 4: Generate compliance report

Print a summary table with each component's status (PASS/WARN/FAIL), overall counts, and a list of issues to fix. For report format template, see [REFERENCE.md](REFERENCE.md).

### Step 5: Apply fixes (if requested)

If `--fix` flag is set or user confirms:

1. Run each failing configure command with `--fix`
2. Report what was fixed and what requires manual intervention

`--fix` never runs inside the workflow. Several components mutate the same
files; parallel fixers would race. Apply the `fixPlan` sequentially.

### Step 6: Update standards tracking

Create or update `.project-standards.yaml` with the current standards version, project type, timestamp, and component versions. For template, see [REFERENCE.md](REFERENCE.md).

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick compliance check (all components) | `/configure:all --check-only` |
| Auto-fix all issues | `/configure:all --fix` |
| Check standards file validity | `test -f .project-standards.yaml && cat .project-standards.yaml \| head -10` |
| List project type indicators | `find . -maxdepth 1 \( -name 'package.json' -o -name 'pyproject.toml' -o -name 'Cargo.toml' \) -exec basename {} \;` |
| Count missing components | `grep -c "status: missing" compliance-report.txt 2>/dev/null` |

## Flags

| Flag | Description |
|------|-------------|
| `--check-only` | Report status without offering fixes |
| `--fix` | Apply all fixes automatically |
| `--type <type>` | Override project type (frontend, infrastructure, python) |

## Exit Codes (for CI)

| Code | Meaning |
|------|---------|
| 0 | All checks passed |
| 1 | Warnings found (non-blocking) |
| 2 | Failures found (blocking) |

A workflow returns a value, not a process status, so `exitCode` cannot come from
the harness. When the Step 3b path is taken, this skill maps the returned
`report.overall` onto the table above: `PASS` → 0, `WARN` → 1, `FAIL` → 2.

## Workflow harness (template)

`workflows/configure-all-check.workflow.js` ships beside this skill. **It is a
TEMPLATE to adapt, not a script to run verbatim.** Read it, then rewrite it for
the work in front of you.

**Adapt freely:** the check and synthesis agent prompts, the wave width, the
`ambiguous` handling, the schema's optional fields, and the shape of the
`fixPlan` entries your project's remediation actually needs.

**Preserve across any adaptation:** (a) the loop bound comes from
`scripts/list-components.sh`'s `COMPONENT=` rows passed in as `args.roster`,
never from a prose "for each component" — and the applicability filter stays the
pure `types === 'all' || types.split(',').includes(projectType)` expression, so
no agent classifies a manifest field; (b) `CHECK_SCHEMA`'s closed
`PASS|WARN|FAIL|ERROR` status enum, plus the `files` array that makes contention
detectable, so a vague verdict is structurally impossible and a null return
becomes an explicit `ERROR` row rather than a silent pass; (c) the Synthesize
stage is a barrier — the fix plan must see every component at once, because
contention over a shared file (pre-commit and linting both write
`.pre-commit-config.yaml`) is invisible to any single check agent. Two
consequences of (c) that are also non-negotiable: the checks are **read-only**,
and `--fix` is applied outside the workflow, sequentially.

**Skip the harness when:** fewer than ~15 components are applicable, or the run
is a single-component check, or the lister reported `STATUS=ERROR` — that is a
linear pass and the harness is pure overhead. The steps above remain the
authoritative description of *what* each stage must produce; the harness only
fixes *how* the work is split.

This supersedes the former hardcoded four-teammate split (linting / security /
testing / CI). That table partitioned a roster it did not read, so it drifted
every time `components.yaml` changed; the harness derives its partition from the
lister instead.

## See Also

- `/configure:select` - Interactively select which components to configure
- `/configure:status` - Quick read-only status overview
- [components.yaml](components.yaml) - The authoritative component roster (per-component `/configure:X` skills are listed there, not here)
