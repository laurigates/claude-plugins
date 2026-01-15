---
created: 2026-01-15
modified: 2026-01-15
reviewed: 2026-01-15
description: "Retroactively generate PRDs, ADRs, and PRPs from existing project history and documentation"
args: "[--quick] [--since DATE]"
argument-hint: "--quick for fast scan, --since 2024-01-01 for date range"
allowed_tools: [Read, Write, Glob, Grep, Bash, AskUserQuestion, Task]
---

Retroactively generate Blueprint documentation (PRDs, ADRs, PRPs) from an existing established project by analyzing git history, codebase structure, and existing documentation.

**Use Case**: Onboarding established projects into the Blueprint Development system when PRD/ADR/PRP documents don't exist but the project has implementation history.

**Arguments**:
- `--quick`: Fast scan (last 50 commits only)
- `--since DATE`: Analyze commits from specific date (e.g., `--since 2024-01-01`)

**Prerequisites**:
- Project is a git repository with commit history
- Project has some existing code and/or documentation

---

## Phase 1: Prerequisites & Discovery

### 1.1 Check Git Repository

```bash
git rev-parse --git-dir 2>/dev/null
```

If not a git repository → Error: "This directory is not a git repository. Run from project root."

### 1.2 Check Blueprint Status

```bash
ls docs/blueprint/manifest.json 2>/dev/null
```

**If not initialized**, use AskUserQuestion:
```
question: "Blueprint not initialized. How would you like to proceed?"
options:
  - label: "Initialize now (Recommended)"
    description: "Run /blueprint:init to set up full structure first"
  - label: "Minimal import only"
    description: "Create docs structure and import documents only"
  - label: "Cancel"
    description: "Exit - run /blueprint:init manually when ready"
```

If "Initialize now" → Run `/blueprint:init` first, then continue.
If "Minimal import only" → Create minimal directory structure inline.

### 1.3 Detect Project Context

```bash
# Project type detection
ls package.json pyproject.toml Cargo.toml go.mod pom.xml build.gradle 2>/dev/null | head -1

# Commit count for scope estimation
git rev-list --count HEAD

# Date range of commits
git log --format="%ai" | tail -1  # First commit date
git log -1 --format="%ai"         # Last commit date
```

### 1.4 Estimate Analysis Scope

Based on commit count, present options:

```
question: "This repository has {N} commits spanning {date_range}. How deep should the analysis be?"
options:
  - label: "Quick scan (last 50 commits)"
    description: "Fast analysis, focuses on recent history"
  - label: "Standard analysis (last 200 commits)"
    description: "Balanced depth and speed"
  - label: "Full history analysis"
    description: "Comprehensive analysis of all commits (may take longer)"
  - label: "Custom date range"
    description: "Analyze commits from a specific period"
```

If "Custom date range" selected → ask for start date.

---

## Phase 2: Git History Analysis

### 2.1 Assess Git History Quality

```bash
# Count total commits in scope
git log --oneline {scope} | wc -l

# Count conventional commits
git log --oneline --format="%s" {scope} | grep -cE "^(feat|fix|docs|style|refactor|perf|test|build|ci|chore)\(?.*\)?:" || echo 0

# Calculate percentage
```

**Git Quality Score**:
- 80%+ conventional commits → Score 9-10 (excellent)
- 50-79% conventional → Score 6-8 (good)
- 20-49% conventional → Score 4-5 (fair)
- <20% conventional → Score 1-3 (poor, graceful degradation)

### 2.2 Extract Feature Boundaries

```bash
# Group commits by scope (from conventional commits)
git log --oneline --format="%s" {scope} | grep -oE "^\w+\(([^)]+)\)" | sed 's/.*(\([^)]*\)).*/\1/' | sort | uniq -c | sort -rn | head -20

# Extract unique scopes as feature candidates
```

For each scope with 3+ commits:
- Name: scope value
- Commit count: number of commits
- Date range: first to last commit with this scope
- Types: feat/fix/refactor distribution

### 2.3 Extract Architecture Decisions

```bash
# Technology migrations
git log --oneline --format="%s" {scope} | grep -iE "(migrate|switch|replace|upgrade|adopt|move from|move to)" | head -20

# Major dependency changes
git log --oneline --format="%s" {scope} | grep -iE "(add|install|introduce|integrate|remove|drop) .*(library|framework|package|dependency|database|orm)" | head -20

# Breaking changes
git log --oneline --format="%s" {scope} | grep -E "^[a-z]+(\([^)]+\))?!:" | head -20
git log --format="%B" {scope} | grep -iB5 "BREAKING CHANGE:" | head -30
```

For each identified decision:
- What changed (from commit message)
- When (commit date)
- Commit SHA (for reference)
- Confidence: High if explicit, Medium if inferred

### 2.4 Extract Issue References

```bash
# Find issue references
git log --oneline --format="%s %b" {scope} | grep -oE "(Fixes|Closes|Resolves|Refs|Related to) #[0-9]+" | sort | uniq -c | sort -rn | head -30
```

Map issues to features where possible.

### 2.5 Identify Release Boundaries

```bash
# Find release tags
git tag -l | grep -E "^v?[0-9]+\.[0-9]+" | head -20

# Get commits between releases
git log --oneline {tag1}..{tag2} | head -10
```

---

## Phase 3: Codebase Analysis

### 3.1 Architecture Discovery

Use Explore agent for comprehensive analysis:

```
Analyze this project's architecture:
1. Directory structure and organization pattern
2. Major components/modules and their responsibilities
3. Frameworks and libraries in use (from dependencies)
4. Design patterns visible in the code
5. Entry points and main flows
6. Data layer (database, ORM, models)
7. API layer (routes, controllers, handlers)
8. Testing structure and frameworks

Report findings organized by architectural decision category.
```

### 3.2 Dependency Analysis

```bash
# Node.js
cat package.json 2>/dev/null | head -100

# Python
cat pyproject.toml 2>/dev/null | head -100
cat requirements.txt 2>/dev/null | head -50

# Rust
cat Cargo.toml 2>/dev/null | head -100

# Go
cat go.mod 2>/dev/null | head -50
```

Extract:
- Major frameworks (React, Express, FastAPI, etc.)
- Testing frameworks (Jest, pytest, etc.)
- Build tools
- Database drivers

### 3.3 Existing Documentation Analysis

```bash
# Find documentation files
fd -e md -d 3 . | head -30
```

Read and extract from:
- `README.md`: Project purpose, features, usage
- `docs/`: Any existing documentation
- `ARCHITECTURE.md`, `DESIGN.md`: Architecture overview
- `CONTRIBUTING.md`: Development practices

### 3.4 Future Work Detection

```bash
# TODOs in code
rg "TODO|FIXME|XXX|HACK" --type-add 'code:*.{ts,js,tsx,jsx,py,go,rs,java}' -t code -c 2>/dev/null | head -20

# Open GitHub issues (if gh CLI available)
gh issue list --state open --limit 20 --json number,title,labels 2>/dev/null || echo "[]"

# Skipped tests
rg "(skip|xtest|xit|pending|@pytest.mark.skip|#\[ignore\])" --type-add 'test:*.{test.ts,test.js,spec.ts,spec.js,_test.py,_test.go}' -t test -c 2>/dev/null | head -10
```

---

## Phase 4: User Interaction

### 4.1 Project Context Clarification

If project purpose not clear from README:
```
question: "What is the primary purpose of this project?"
options:
  - "[Inferred]: {inferred_description}" (if README provides hints)
  - "Let me describe it"
```

### 4.2 Target Users

```
question: "Who are the primary users of this project?"
options:
  - "Developers (internal tool/library)"
  - "End users (application)"
  - "Both developers and end users"
  - "Other"
```

### 4.3 Feature Confirmation

Present extracted features:
```
question: "I identified {N} features from git history. Would you like to review them?"
options:
  - label: "Yes, let me review and prioritize"
    description: "I'll show each feature for confirmation"
  - label: "Accept all as-is"
    description: "Use inferred features with default priorities"
  - label: "Skip feature extraction"
    description: "I'll define features manually in the PRD"
```

If reviewing, for each major feature:
```
question: "Feature: {feature_name} ({commit_count} commits). Priority?"
options:
  - "P0 - Critical"
  - "P1 - Important"
  - "P2 - Nice to have"
  - "Skip this feature"
```

### 4.4 Architecture Decision Rationale

For each identified architecture decision:
```
question: "I found that {technology} was adopted. What was the main driver?"
options:
  - "Performance requirements"
  - "Team familiarity"
  - "Ecosystem/community support"
  - "Specific feature needs"
  - "Legacy/inherited decision"
  - "Let me explain"
```

### 4.5 Generation Confirmation

```
question: "Ready to generate documents. Summary:"

**Analysis Results**:
- Git history quality: {score}/10
- Features identified: {N}
- Architecture decisions: {N}
- Future work items: {N}

**Documents to generate**:
- PRD: 1 document with {N} features
- ADRs: {N} architecture decisions
- PRPs: {N} suggested future work items

options:
  - label: "Generate all (Recommended)"
    description: "Create PRD, ADRs, and PRPs"
  - label: "PRD and ADRs only"
    description: "Skip PRP generation"
  - label: "PRD only"
    description: "Only create the requirements document"
  - label: "Let me adjust"
    description: "Go back and modify analysis"
  - label: "Cancel"
    description: "Exit without generating"
```

---

## Phase 5: Document Generation

### 5.1 Create Directory Structure

```bash
mkdir -p docs/prds docs/adrs docs/prps
```

### 5.2 Generate PRD

Create `docs/prds/project-overview.md`:

```markdown
# {Project Name} - Product Requirements Document

**Created**: {date}
**Status**: Retroactive (Generated from history)
**Version**: {latest_tag or "1.0"}
**Import Confidence**: {overall_score}/10

## Executive Summary

### Problem Statement
{Extracted from README or user input}
<!-- confidence: {score}/10 - {source} -->

### Proposed Solution
{Project description from README/analysis}
<!-- confidence: {score}/10 - {source} -->

### Business Impact
{Inferred or from user input}
<!-- confidence: {score}/10 - {source} -->

## Stakeholders & Personas

{From user input or marked as "Needs clarification"}

### User Personas

#### Primary: {Persona from user input}
- **Description**: {description}
- **Needs**: {needs}
- **Goals**: {goals}

## Functional Requirements

### Core Features

| ID | Feature | Description | Priority | Source |
|----|---------|-------------|----------|--------|
| FR-001 | {feature} | {from commits/code} | {P0/P1/P2} | git: {scope}, {commit_count} commits |
| FR-002 | {feature} | {description} | {priority} | git: {scope} |

### Feature Details

#### FR-001: {Feature Name}
- **Commits**: {first_sha}..{last_sha} ({date_range})
- **Related issues**: {issue_refs}
- **Key files**: {main_files}

## Non-Functional Requirements

### Performance
{Inferred from dependencies or marked as "Needs input"}

### Security
{Inferred from auth-related code or marked as "Needs input"}

### Compatibility
{From package.json engines, tsconfig target, etc.}

## Technical Considerations

### Architecture
{From Explore agent analysis}

### Tech Stack
{From dependency analysis}
- Language: {language}
- Framework: {framework}
- Testing: {test_framework}
- Database: {database if detected}

### Dependencies
{Key dependencies from manifest}

## Success Metrics

| Metric | Baseline | Target | Measurement |
|--------|----------|--------|-------------|
| {metric} | {current} | {target} | {how} |

<!-- Most metrics need user input for established projects -->

## Scope

### In Scope
{Inferred from implemented features}

### Out of Scope
{Marked as "Needs user input"}

## Timeline & Phases

### Current Phase: {Inferred from git activity}

### History
| Phase | Focus | Dates | Status |
|-------|-------|-------|--------|
| Initial Development | Core features | {first_commit} - {tag_v1} | Complete |
| {Phase 2} | {inferred} | {dates} | {status} |

---

## Import Metadata

**Generated by**: /blueprint:import-plans
**Analysis date**: {date}
**Commits analyzed**: {count}
**Date range**: {first_commit_date} to {last_commit_date}
**Git quality score**: {score}/10

### Confidence Summary
| Section | Confidence | Notes |
|---------|------------|-------|
| Executive Summary | {score}/10 | {notes} |
| Features | {score}/10 | {notes} |
| Technical | {score}/10 | {notes} |
| Non-Functional | {score}/10 | {notes} |

### Sections Needing Review
- {list sections with low confidence}
```

### 5.3 Generate ADRs

For each identified architecture decision, create `docs/adrs/{NNNN}-{title}.md`:

```markdown
# ADR-{number}: {Decision Title}

**Date**: {commit_date}
**Status**: Accepted (Retroactive)
**Confidence**: {score}/10

## Context

{Inferred from pre-change state or user input}
<!-- This decision was identified from git history. Original context may need clarification. -->

## Decision Drivers

- {driver from user input or inferred}
- {driver 2}

## Considered Options

1. **{Current choice}** - The implemented solution
2. **{Alternative 1}** - Common alternative for this type of decision
3. **{Alternative 2}** - Another common alternative

## Decision Outcome

**Chosen option**: "{Current choice}" because {user-provided rationale or "rationale needs documentation"}.

### Positive Consequences

- {inferred benefit from implementation}
- {benefit 2}

### Negative Consequences

- {known tradeoff if any}
- {limitation if any}

## Evidence

- **Commit**: {sha} - "{commit_message}"
- **Date**: {date}
- **Files changed**: {key files}

---

*Retroactively generated from git history via /blueprint:import-plans*
*Original commit: {sha} on {date}*
```

Create `docs/adrs/README.md` index:

```markdown
# Architecture Decision Records

This directory contains Architecture Decision Records (ADRs) documenting significant technical decisions.

**Note**: These ADRs were retroactively generated from git history. Review and enhance rationale sections as needed.

## Index

| ADR | Title | Status | Date | Confidence |
|-----|-------|--------|------|------------|
| [0001](0001-{title}.md) | {title} | Accepted | {date} | {score}/10 |
| [0002](0002-{title}.md) | {title} | Accepted | {date} | {score}/10 |

## Template

New ADRs should follow the [MADR template](https://adr.github.io/madr/).
```

### 5.4 Generate PRPs

For each identified future work item, create `docs/prps/{feature}.md`:

```markdown
# PRP: {Feature/Task Name}

**Created**: {date}
**Status**: Suggested
**Source**: {TODO|Issue|Analysis}
**Confidence**: {score}/10

## Goal

{Extracted from TODO comment, issue title, or analysis}

### Why

{Inferred from context or marked as "Needs clarification"}

## Context

### Source Reference

**Origin**: {source_type}
- Location: `{file}:{line}` or Issue #{number}
- Text: "{original_text}"

### Codebase Intelligence

{From Explore agent - related code, patterns to follow}

### Known Gotchas

| Gotcha | Impact | Mitigation |
|--------|--------|------------|
| {identified concern} | {impact} | {suggested approach} |

## Suggested Implementation

{Basic outline based on similar features in codebase}

## TDD Requirements

{Template based on project testing patterns}

### Test Strategy
- Unit tests: {what to test}
- Integration tests: {if applicable}

---

*Suggested future work identified via /blueprint:import-plans*
*Requires prioritization and detailed planning before execution*
```

---

## Phase 6: Manifest Updates & Reporting

### 6.1 Update Manifest

Update `docs/blueprint/manifest.json`:

```json
{
  "format_version": "3.0.0",
  "updated_at": "{ISO timestamp}",
  "structure": {
    "has_prds": true,
    "has_adrs": true,
    "has_prps": true
  },
  "import_metadata": {
    "imported_at": "{ISO timestamp}",
    "commits_analyzed": {count},
    "date_range": ["{start}", "{end}"],
    "git_quality_score": {score},
    "features_extracted": {count},
    "decisions_identified": {count},
    "future_work_suggested": {count},
    "overall_confidence": {score}
  },
  "generated_artifacts": [
    {
      "type": "prd",
      "file": "docs/prds/project-overview.md",
      "confidence": {score},
      "source": "import"
    },
    {
      "type": "adr",
      "file": "docs/adrs/0001-{title}.md",
      "confidence": {score},
      "source": "import"
    }
  ]
}
```

### 6.2 Summary Report

```
Blueprint Import Complete!

**Analysis Summary**
- Commits analyzed: {N} ({date_range})
- Conventional commits: {percentage}%
- Git quality score: {score}/10

**Documents Generated**

PRD: docs/prds/project-overview.md (confidence: {score}/10)
   - Features documented: {N}
   - User clarifications incorporated: {N}

ADRs: {N} decisions documented
   - 0001-{title}.md (confidence: {score}/10)
   - 0002-{title}.md (confidence: {score}/10)
   ...

PRPs: {N} future work items suggested
   - docs/prps/{name}.md (from TODOs)
   - docs/prps/{name}.md (from issues)
   ...

**Needs Review**
{List sections/documents with confidence < 7}

**Next Steps**
1. Review documents marked "needs clarification"
2. Run `/blueprint:generate-rules` to create implementation patterns
3. Run `/blueprint:generate-commands` for workflow automation
```

### 6.3 Prompt Next Action

```
question: "Import complete (average confidence: {score}/10). What would you like to do?"
options:
  - label: "Review and refine documents (Recommended)"
    description: "Go through items marked 'needs clarification'"
  - label: "Generate project rules"
    description: "Run /blueprint:generate-rules from the new PRD"
  - label: "Generate workflow commands"
    description: "Run /blueprint:generate-commands for this project"
  - label: "I'm done for now"
    description: "Exit - documents are saved and ready for review"
```

**Based on selection**:
- "Review and refine" → Show list of documents needing attention with file paths
- "Generate project rules" → Run `/blueprint:generate-rules`
- "Generate workflow commands" → Run `/blueprint:generate-commands`
- "I'm done" → Exit with quick reference

---

## Error Handling

| Condition | Action |
|-----------|--------|
| Not a git repository | Error with message, suggest running from project root |
| No commits | Error: "Repository has no commit history" |
| No README and no docs | Warn, ask user for project description |
| Blueprint already has PRDs | Ask: Merge, Replace, or Cancel |
| gh CLI not available | Skip issue-based analysis, warn user |
| Very large repo (>5000 commits) | Suggest --quick or --since flag |
| No conventional commits | Graceful degradation: lower confidence, use file-based analysis |

---

## Tips

- **Git history quality matters**: Projects with conventional commits produce better results
- **User input improves accuracy**: Answer clarifying questions to increase confidence scores
- **Review low-confidence sections**: Focus review effort on sections marked < 7/10
- **Iterative refinement**: Run import once, then refine documents manually
- **Combine with existing docs**: If some documentation exists, import will incorporate it
