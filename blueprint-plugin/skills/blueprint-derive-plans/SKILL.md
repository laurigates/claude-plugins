---
model: opus
created: 2026-01-15
modified: 2026-02-14
reviewed: 2026-02-14
description: "Derive PRDs, ADRs, and PRPs from git history, codebase structure, and existing documentation"
args: "[--quick] [--since DATE]"
argument-hint: "--quick for fast scan, --since 2024-01-01 for date range"
allowed-tools: Read, Write, Glob, Grep, Bash, AskUserQuestion, Task
name: blueprint-derive-plans
---

# /blueprint:derive-plans

Retroactively generate Blueprint documentation (PRDs, ADRs, PRPs) from an existing established project by analyzing git history, codebase structure, and existing documentation.

**Use case**: Onboarding established projects into the Blueprint Development system when PRD/ADR/PRP documents don't exist but the project has implementation history.

## When to Use This Skill

| Use this skill when... | Use alternative when... |
|------------------------|-------------------------|
| Project has git history but no PRDs/ADRs/PRPs | Starting a brand new project with no history |
| Onboarding an established project to Blueprint | Creating a fresh PRD from scratch with user guidance |
| Need to extract features from commit history | Project lacks conventional commits and clear history |
| Want to document architecture decisions retroactively | Decisions are already fully documented |

## Context

- Git repository: !`git rev-parse --git-dir 2>/dev/null && echo "YES" || echo "NO"`
- Blueprint initialized: !`test -f docs/blueprint/manifest.json && echo "YES" || echo "NO"`
- Total commits: !`git rev-list --count HEAD 2>/dev/null || echo "0"`
- First commit: !`git log --reverse --format=%ai -1 2>/dev/null || echo "UNKNOWN"`
- Latest commit: !`git log -1 --format=%ai 2>/dev/null || echo "UNKNOWN"`
- Project type: !`ls package.json pyproject.toml Cargo.toml go.mod pom.xml 2>/dev/null | head -1 | xargs basename 2>/dev/null || echo "UNKNOWN"`
- Documentation files: !`find . -maxdepth 2 -name "README.md" -o -name "ARCHITECTURE.md" -o -name "DESIGN.md" 2>/dev/null | wc -l`

## Parameters

Parse these from `$ARGUMENTS`:

- `--quick`: Fast scan (last 50 commits only)
- `--since DATE`: Analyze commits from specific date (e.g., `--since 2024-01-01`)

Default behavior without flags: Standard analysis (last 200 commits with scope estimation).

For detailed templates, manifest format, and report examples, see [REFERENCE.md](REFERENCE.md).

## Execution

Execute this retroactive documentation generation workflow:

### Step 1: Verify prerequisites

Check context values above:

1. If git repository = "NO" → Error: "This directory is not a git repository. Run from project root."
2. If total commits = "0" → Error: "Repository has no commit history"
3. If Blueprint initialized = "NO" → Ask user: "Blueprint not initialized. Initialize now (Recommended) or minimal import only?"
   - If "Initialize now" → Use Task tool to invoke `/blueprint:init`, then continue with this step 1
   - If "Minimal import only" → Create minimal directory structure: `mkdir -p docs/prds docs/adrs docs/prps`

### Step 2: Determine analysis scope

Parse `$ARGUMENTS` for `--quick` or `--since`:

1. If `--quick` flag present → scope = last 50 commits
2. If `--since DATE` present → scope = commits from DATE to now
3. Otherwise → Present options to user:
   - Quick scan (last 50 commits)
   - Standard analysis (last 200 commits)
   - Full history analysis (all commits)
   - Custom date range

Use selected scope for all subsequent git analysis.

### Step 3: Analyze git history quality

For commits in scope, calculate:

1. Count total commits: `git log --oneline {scope} | wc -l`
2. Count conventional commits: `git log --format="%s" {scope} | grep -cE "^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)\(?.*\)?:" || echo 0`
3. Calculate percentage and assign quality score (see [REFERENCE.md](REFERENCE.md#git-quality-scoring))

Report: "Git history quality: {score}/10 ({percentage}% conventional commits)"

### Step 4: Extract features and architecture decisions

Using methods from [REFERENCE.md](REFERENCE.md#git-analysis-patterns):

1. Extract feature boundaries from conventional commit scopes
2. Identify architecture decisions (migrations, major dependencies, breaking changes)
3. Find issue references and future work items (TODOs, skipped tests)
4. Identify release boundaries from git tags

Collect findings in structured format for user confirmation.

### Step 5: Analyze codebase and existing documentation

1. Use Explore agent to analyze architecture: directory structure, components, frameworks, patterns, entry points, data layer, API layer, testing structure
2. Extract dependencies from manifest files (package.json, pyproject.toml, Cargo.toml, go.mod, etc.)
3. Read and extract from existing documentation: README.md, docs/, ARCHITECTURE.md, DESIGN.md, CONTRIBUTING.md
4. Detect future work: TODOs in code, open GitHub issues, skipped tests

### Step 6: Clarify project context with user

Ask for clarifications on:

1. **Project purpose** (if not clear from README): Present inferred description for confirmation or ask user to provide
2. **Target users**: Who are the primary users (developers, end users, both)?
3. **Feature confirmation**: Present {N} features extracted from git for review/prioritization
4. **Architecture rationale**: For each identified decision, ask what was the main driver
5. **Generation confirmation**: Show summary with metrics and ask if ready to generate

For confirmation step, present:
- Git history quality: {score}/10
- Features identified: {N}
- Architecture decisions: {N}
- Future work items: {N}
- Proposed documents: PRD, {N} ADRs, {N} PRPs

### Step 7: Generate documents

Create directory structure: `mkdir -p docs/prds docs/adrs docs/prps`

For each document type, use templates and patterns from [REFERENCE.md](REFERENCE.md):

1. **Generate PRD** as `docs/prds/project-overview.md`
   - Use sections and structure from REFERENCE.md
   - Include extracted features with priorities and sources
   - Mark sections with confidence scores

2. **Generate ADRs** as `docs/adrs/{NNNN}-{title}.md` (one per decision)
   - Use ADR template from REFERENCE.md
   - Include git evidence (commit SHA, date, files changed)
   - Mark with confidence score

3. **Create ADR index** at `docs/adrs/README.md`
   - Table of all ADRs with status and dates
   - Link to MADR template for new ADRs

4. **Generate PRPs** as `docs/prps/{feature}.md` (one per future work item)
   - Use PRP template from REFERENCE.md
   - Include source reference and confidence score
   - Suggest implementation based on codebase patterns

### Step 8: Update manifest and report results

1. Update `docs/blueprint/manifest.json` with import metadata: timestamp, commits analyzed, confidence scores, generated artifacts
2. Create summary report showing:
   - Commits analyzed with date range
   - Git quality score
   - Documents generated (PRD, ADR count, PRP count)
   - Sections needing review (confidence < 7)
   - Recommended next steps

3. Prompt user for next action:
   - Review and refine documents
   - Generate project rules from PRD
   - Generate workflow commands
   - Exit (documents saved)

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Check git status | `git rev-parse --git-dir 2>/dev/null && echo "YES" \|\| echo "NO"` |
| Count commits | `git rev-list --count HEAD 2>/dev/null \|\| echo "0"` |
| Conventional commits count | `git log --format="%s" \| grep -cE "^(feat\|fix\|docs)" \|\| echo 0` |
| Extract scopes | `git log --format="%s" \| grep -oE '\([^)]+\)' \| sort \| uniq -c` |
| Fast analysis | Use `--quick` flag for last 50 commits only |

---

For detailed templates, git analysis patterns, document generation examples, and error handling guidance, see [REFERENCE.md](REFERENCE.md).
