---
model: opus
created: 2026-01-15
modified: 2026-02-14
reviewed: 2026-01-15
description: "Derive PRDs, ADRs, and PRPs from git history, codebase structure, and existing documentation"
args: "[--quick] [--since DATE]"
argument-hint: "--quick for fast scan, --since 2024-01-01 for date range"
allowed-tools: Read, Write, Glob, Grep, Bash, AskUserQuestion, Task
name: blueprint-derive-plans
---

Retroactively generate Blueprint documentation (PRDs, ADRs, PRPs) from an existing established project by analyzing git history, codebase structure, and existing documentation.

**Use Case**: Onboarding established projects into the Blueprint Development system when PRD/ADR/PRP documents don't exist but the project has implementation history.

**Arguments**:
- `--quick`: Fast scan (last 50 commits only)
- `--since DATE`: Analyze commits from specific date (e.g., `--since 2024-01-01`)

**Prerequisites**:
- Project is a git repository with commit history
- Project has some existing code and/or documentation

For detailed templates, manifest format, and report examples, see [REFERENCE.md](REFERENCE.md).

---

## Phase 1: Prerequisites & Discovery

### 1.1 Check Git Repository

```bash
git rev-parse --git-dir 2>/dev/null
```

If not a git repository, error: "This directory is not a git repository. Run from project root."

### 1.2 Check Blueprint Status

```bash
ls docs/blueprint/manifest.json 2>/dev/null
```

**If not initialized**, use AskUserQuestion with options: "Initialize now (Recommended)", "Minimal import only", or "Cancel".

### 1.3 Detect Project Context

```bash
# Project type detection
ls package.json pyproject.toml Cargo.toml go.mod pom.xml build.gradle 2>/dev/null | head -1

# Commit count and date range
git rev-list --count HEAD
git log --format="%ai" | tail -1
git log -1 --format="%ai"
```

### 1.4 Estimate Analysis Scope

Present scope options based on commit count: "Quick scan (last 50)", "Standard (last 200)", "Full history", or "Custom date range".

---

## Phase 2: Git History Analysis

### 2.1 Assess Git History Quality

```bash
git log --oneline {scope} | wc -l
git log --oneline --format="%s" {scope} | grep -cE "^(feat|fix|docs|style|refactor|perf|test|build|ci|chore)\(?.*\)?:" || echo 0
```

**Git Quality Score**: 80%+ conventional = 9-10, 50-79% = 6-8, 20-49% = 4-5, <20% = 1-3.

### 2.2 Extract Feature Boundaries

```bash
git log --oneline --format="%s" {scope} | grep -oE "^\w+\(([^)]+)\)" | sed 's/.*(\([^)]*\)).*/\1/' | sort | uniq -c | sort -rn | head -20
```

For each scope with 3+ commits, capture: name, commit count, date range, type distribution.

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

### 2.4 Extract Issue References

```bash
git log --oneline --format="%s %b" {scope} | grep -oE "(Fixes|Closes|Resolves|Refs|Related to) #[0-9]+" | sort | uniq -c | sort -rn | head -30
```

### 2.5 Identify Release Boundaries

```bash
git tag -l | grep -E "^v?[0-9]+\.[0-9]+" | head -20
```

---

## Phase 3: Codebase Analysis

### 3.1 Architecture Discovery

Use Explore agent to analyze: directory structure, major components, frameworks/libraries, design patterns, entry points, data layer, API layer, and testing structure.

### 3.2 Dependency Analysis

Read the project manifest (`package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`) and extract: major frameworks, testing frameworks, build tools, database drivers.

### 3.3 Existing Documentation Analysis

```bash
fd -e md -d 3 . | head -30
```

Read and extract from: `README.md`, `docs/`, `ARCHITECTURE.md`, `CONTRIBUTING.md`.

### 3.4 Future Work Detection

```bash
rg "TODO|FIXME|XXX|HACK" --type-add 'code:*.{ts,js,tsx,jsx,py,go,rs,java}' -t code -c 2>/dev/null | head -20
gh issue list --state open --limit 20 --json number,title,labels 2>/dev/null || echo "[]"
rg "(skip|xtest|xit|pending|@pytest.mark.skip|#\[ignore\])" --type-add 'test:*.{test.ts,test.js,spec.ts,spec.js,_test.py,_test.go}' -t test -c 2>/dev/null | head -10
```

---

## Phase 4: User Interaction

Use AskUserQuestion for each of the following:

1. **Project context clarification** - if purpose not clear from README
2. **Target users** - developers, end users, or both
3. **Feature confirmation** - review extracted features or accept all as-is
4. **Feature prioritization** - for each major feature: P0, P1, P2, or Skip
5. **Architecture decision rationale** - for each decision: performance, familiarity, ecosystem, feature needs, legacy, or custom explanation
6. **Generation confirmation** - show analysis summary and offer: "Generate all", "PRD and ADRs only", "PRD only", "Let me adjust", or "Cancel"

---

## Phase 5: Document Generation

### 5.1 Create Directory Structure

```bash
mkdir -p docs/prds docs/adrs docs/prps
```

### 5.2 Generate PRD

Create `docs/prds/project-overview.md` using the PRD template from [REFERENCE.md](REFERENCE.md). Include import metadata and confidence summary.

### 5.3 Generate ADRs

For each identified architecture decision, create `docs/adrs/{NNNN}-{title}.md` using the ADR template from [REFERENCE.md](REFERENCE.md). Create `docs/adrs/README.md` index.

### 5.4 Generate PRPs

For each identified future work item, create `docs/prps/{feature}.md` using the PRP template from [REFERENCE.md](REFERENCE.md).

---

## Phase 6: Manifest Updates & Reporting

### 6.1 Update Manifest

Update `docs/blueprint/manifest.json` with import metadata. See [REFERENCE.md](REFERENCE.md) for format.

### 6.2 Summary Report

Generate completion report with: analysis summary (commits, conventional %, quality score), documents generated (PRDs, ADRs, PRPs with confidence), sections needing review, and next steps.

### 6.3 Prompt Next Action

Offer: "Review and refine documents", "Generate project rules", "Generate workflow commands", or "I'm done for now".

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

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick scan | `/blueprint:derive-plans --quick` |
| Date-scoped | `/blueprint:derive-plans --since 2024-01-01` |
| Commit quality check | `git log --format="%s" \| grep -cE "^(feat\|fix\|docs)\\("` |
| Scope estimation | `git rev-list --count HEAD` |

## Tips

- **Git history quality matters**: Projects with conventional commits produce better results
- **User input improves accuracy**: Answer clarifying questions to increase confidence scores
- **Review low-confidence sections**: Focus review effort on sections marked < 7/10
- **Iterative refinement**: Run import once, then refine documents manually
- **Combine with existing docs**: If some documentation exists, import will incorporate it
