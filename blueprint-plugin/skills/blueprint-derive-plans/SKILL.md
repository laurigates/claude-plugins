---
created: 2026-01-15
modified: 2026-11-14
reviewed: 2026-05-29
description: Derive PRDs, ADRs, PRPs from git history, docs, and codebase. Use when onboarding a project to blueprint, generating a PRD or ADRs retroactively, or extracting features from conventional commits.
args: "[--quick] [--since DATE]"
argument-hint: "--quick for fast scan, --since 2024-01-01 for date range"
allowed-tools: Read, Write, Glob, Grep, Bash(git rev-parse *), Bash(git rev-list *), Bash(git log *), Bash(find *), Bash(grep *), Bash(sed *), Bash(sort *), Bash(uniq *), Bash(head *), Bash(wc *), Bash(mkdir *), Bash(jq *), Bash(date *), Bash(mv *), Bash(gh issue create *), AskUserQuestion, Task
model: opus
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

- Git repository: !`git rev-parse --git-dir`
- Blueprint initialized: !`find . -path '*/docs/blueprint/*' -maxdepth 3 -name 'manifest.json' -type f`
- Total commits: !`git rev-list --count HEAD`
- First commit: !`git log --reverse --format=%ai --max-count=1`
- Latest commit: !`git log --max-count=1 --format=%ai`
- Project type: !`find . -maxdepth 1 \( -name 'package.json' -o -name 'pyproject.toml' -o -name 'Cargo.toml' -o -name 'go.mod' -o -name 'pom.xml' \) -type f -print -quit`
- Documentation files: !`find . -maxdepth 2 \( -name "README.md" -o -name "ARCHITECTURE.md" -o -name "DESIGN.md" \)`

## Parameters

Parse these from `$ARGUMENTS`:

- `--quick`: Fast scan (last 50 commits only)
- `--since DATE`: Analyze commits from specific date (e.g., `--since 2024-01-01`)

Default behavior without flags: Standard analysis (last 200 commits with scope estimation).

For detailed templates, manifest format, and report examples, see [REFERENCE.md](REFERENCE.md).

## Execution

Execute this retroactive documentation generation workflow:

### Step 1: Verify prerequisites

Check the values in [Context](#context):

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

Ask for clarifications via `AskUserQuestion`. For the full question templates
(problem statement, target users, project phase, stakeholder scale), see
[REFERENCE.md](REFERENCE.md#clarifying-questions).

1. **Project purpose** (if not clear from README): present the inferred description for confirmation, or ask the user to provide one
2. **Target users**: developers, end users, or both — steers the PRD's framing
3. **Project phase**: MVP / active development / maintenance / planning major changes — sets feature-vs-stability emphasis
4. **Stakeholders**: scale (solo / small team / larger org / OSS community) → drives the depth of the PRD's stakeholder matrix (see [REFERENCE.md](REFERENCE.md#prd-template))
5. **Feature confirmation**: present {N} features extracted from git for review/prioritization
6. **Architecture rationale**: for each identified decision, ask the main driver
7. **Generation confirmation**: show the summary below and ask if ready to generate

For the confirmation step, present:
- Git history quality: {score}/10
- Features identified: {N}
- Architecture decisions: {N}
- Future work items: {N}
- Proposed documents: PRD (with stakeholder matrix), {N} ADRs, {N} PRPs

### Step 7: Generate documents

Create directory structure: `mkdir -p docs/prds docs/adrs docs/prps`

For each document type, use templates and patterns from [REFERENCE.md](REFERENCE.md):

1. **Generate PRD** as `docs/prds/project-overview.md`
   - Use sections and structure from REFERENCE.md
   - Include extracted features with priorities and sources
   - Mark sections with confidence scores

2. **Generate ADRs** as `docs/adrs/{NNNN}-{title}.md` (one per decision)
   - Start from the five-section template
     `${CLAUDE_SKILL_DIR}/../../templates/adr-template.md` (Context, Decision,
     Consequences, Options Considered, Related ADRs), filled as described in
     REFERENCE.md § ADR Template
   - Include git evidence (commit SHA, date, files changed)
   - Mark with confidence score
   - **Conflict & supersede check**: after writing the ADRs, run
     `/blueprint:adr-relationships` to detect same-domain conflicts and
     `/blueprint:adr-validate` to enforce bidirectional supersede consistency.
     Do not re-implement conflict scoring here — those skills own it.

3. **Create ADR index** at `docs/adrs/README.md`
   - Table of all ADRs with status and dates
   - Point new ADRs at blueprint-plugin's `templates/adr-template.md`
     (the five-section template), not MADR

4. **Generate PRPs** as `docs/prps/{feature}.md` (one per future work item)
   - Use PRP template from REFERENCE.md
   - Include source reference and confidence score
   - Suggest implementation based on codebase patterns

### Step 8: Update manifest and report results

1. Update `docs/blueprint/manifest.json` with import metadata: timestamp, commits analyzed, confidence scores, generated artifacts

### Step 8.5: Offer GitHub issues for generated docs (optional)

For the generated PRD (and optionally each PRP), prompt with `AskUserQuestion`
whether to open a tracking GitHub issue. See
[REFERENCE.md](REFERENCE.md#github-issue-tracking) for the prompt template and
the `gh issue create` command. When the user accepts:

1. Create the issue with title `[{PRD-NNN}] {Project Name}`.
2. Add the issue number to the doc's `github-issues` frontmatter.
3. Record it in the manifest `id_registry` (`documents[ID].github_issues` and the `github_issues` map).

Skip silently when no `gh` remote is configured or the user declines.

### Step 9: Update task registry

Run the `jq` update in [REFERENCE.md](REFERENCE.md#task-registry-update) on `docs/blueprint/manifest.json`.

2. Create summary report: [REFERENCE.md](REFERENCE.md#summary-report-format).

3. Prompt user for next action: [REFERENCE.md](REFERENCE.md#next-action-prompt).

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
