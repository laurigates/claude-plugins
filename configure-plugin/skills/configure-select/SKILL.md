---
created: 2025-12-22
modified: 2026-07-05
reviewed: 2026-07-05
description: "Interactive selector for infrastructure standards. Use when setting up specific components or building infrastructure incrementally instead of running /configure:all."
allowed-tools: Glob, Grep, Read, Write, Edit, Bash, AskUserQuestion, TodoWrite, SlashCommand
args: "[--check-only] [--fix]"
argument-hint: "[--check-only] [--fix]"
name: configure-select
---

# /configure:select

Interactively select which infrastructure standards checks to run.

## When to Use This Skill

| Use this skill when... | Use another approach when... |
|------------------------|------------------------------|
| Setting up selected components interactively | Running all components (use `/configure:all`) |
| Choosing specific standards to implement | Checking status only (use `/configure:status`) |
| Customizing configuration scope for project | Single component needed (use specific `/configure:X` skill) |
| User wants control over which components to configure | Automated full setup preferred |
| Building configuration incrementally | Complete infrastructure setup needed immediately |

## Context

- Project standards: !`find . -maxdepth 1 -name \'.project-standards.yaml\'`
- Project type: !`find . -maxdepth 1 -name '.project-standards.yaml' -exec grep -m1 "^project_type:" {} +`
- Has terraform: !`find . -maxdepth 2 \( -name '*.tf' -o -type d -name 'terraform' \) -print -quit`
- Has package.json: !`find . -maxdepth 1 -name \'package.json\'`
- Has pyproject.toml: !`find . -maxdepth 1 -name \'pyproject.toml\'`
- Has Cargo.toml: !`find . -maxdepth 1 -name \'Cargo.toml\'`

## Parameters

Parse from `$ARGUMENTS`:

- `--check-only`: Report status without offering fixes (CI/CD mode)
- `--fix`: Apply fixes automatically to all selected components

## Execution

Execute this interactive component selection workflow:

### Step 1: Detect project type

1. Read `.project-standards.yaml` if it exists (check `project_type` field)
2. Auto-detect from file structure:
   - **infrastructure**: Has `terraform/`, `helm/`, `argocd/`, or `*.tf` files
   - **frontend**: Has `package.json` with vue/react dependencies
   - **python**: Has `pyproject.toml` or `requirements.txt`
   - **rust**: Has `Cargo.toml`
3. Report detected type to user

### Step 2: List domains and components from the manifest

The component roster lives in the sibling manifest
[configure-all/components.yaml](../configure-all/components.yaml). Run the
lister to get the current domains and their components:

```bash
bash "${CLAUDE_SKILL_DIR}/../configure-all/scripts/list-components.sh"
```

`DOMAIN=<key> TITLE=<title>` lines are the selectable domains;
`COMPONENT=<name> DOMAIN=<key> ...` lines are their members. Never
hand-maintain a category table here — the manifest is the single source of
truth.

### Step 3: Present component selection

Use AskUserQuestion with multiSelect, building the questions from the lister
output:

1. Group the manifest domains into at most 4 questions of 2–4 options each,
   keeping related domains in the same question (e.g. CI/CD with Git Metadata,
   Testing on its own, Code Quality with Security and Documentation, Containers
   with Editor & Dev Environment and Package Management).
2. Each option is one domain: label = the domain `TITLE`, description = that
   domain's component names from the lister output.
3. Selecting a domain selects all of its components. Skip components whose
   `TYPES` excludes the detected project type.

Map each selected domain to its components' `/configure:X` commands (a
`COMPONENT=configure-tests` row runs `/configure:tests`).

### Step 4: Execute selected checks

Run each selected command with appropriate flags:

- Default: Run with `--check-only` first, then offer `--fix`
- If `--check-only` flag: Only audit, no fixes offered
- If `--fix` flag: Apply fixes automatically

Report results as each check completes.

### Step 5: Generate summary report

Print a summary for selected components only:

```
Selected Components Summary:
+-----------------+----------+---------------------------------+
| Component       | Status   | Notes                           |
+-----------------+----------+---------------------------------+
| Pre-commit      | WARN     | 2 outdated hooks                |
| Linting         | PASS     | Biome configured                |
| Formatting      | PASS     | Biome configured                |
+-----------------+----------+---------------------------------+
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Interactive component selection | `/configure:select` |
| Select and auto-fix | `/configure:select --fix` |
| Check mode only | `/configure:select --check-only` |
| Detect project type | `test -f .project-standards.yaml && grep "^project_type:" .project-standards.yaml \| sed 's/.*:[[:space:]]*//'` |

## Flags

| Flag | Description |
|------|-------------|
| `--check-only` | Report status without offering fixes |
| `--fix` | Apply fixes automatically to all selected |

## Comparison with Other Commands

| Command | Use Case |
|---------|----------|
| `/configure:all` | Run everything (CI, full audit) |
| `/configure:select` | Choose specific components interactively |
| `/configure:status` | Quick read-only overview |
| `/configure:<component>` | Single component only |

## See Also

- `/configure:all` - Run all checks
- `/configure:status` - Read-only status overview
