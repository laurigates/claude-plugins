---
model: haiku
name: Documentation Quality Analysis
description: Analyze and validate documentation quality for PRDs, ADRs, PRPs, CLAUDE.md, and .claude/rules/ to ensure standards compliance and freshness
allowed-tools: Bash, Read, Grep, Glob, TodoWrite
created: 2026-01-08
modified: 2026-01-08
reviewed: 2026-01-08
---

# Documentation Quality Analysis

Expert analysis of technical documentation quality, structure, and maintenance for codebases using Blueprint Development methodology and Claude Code conventions.

## Core Expertise

Documentation quality is critical for:
- **AI Assistant Context**: Well-structured docs enable better AI assistance
- **Knowledge Preservation**: Captures architectural decisions and rationale
- **Onboarding**: Accelerates new team member productivity
- **Maintenance**: Prevents knowledge loss and technical debt

This skill provides systematic analysis of:
- **CLAUDE.md**: Project-level AI assistant instructions
- **.claude/rules/**: Modular rule definitions
- **ADRs**: Architecture Decision Records
- **PRDs**: Product Requirements Documents
- **PRPs**: Product Requirement Prompts (Blueprint methodology)

## Documentation Types & Standards

### CLAUDE.md

**Purpose**: Guide AI assistants on working with the codebase

**Required Elements**:
```yaml
---
created: YYYY-MM-DD
modified: YYYY-MM-DD
reviewed: YYYY-MM-DD
---

# Project Name

## Project Structure
[Directory layout and organization]

## Rules
[Key rules and conventions]

## Development Workflow
[Common tasks and patterns]

## Conventions
[Naming, structure, etc.]
```

**Quality Indicators**:
- ✅ Clear project structure overview
- ✅ References to .claude/rules/ files
- ✅ Tables for quick reference
- ✅ Focused and concise (not a full manual)
- ✅ Updated within last 6 months

### .claude/rules/

**Purpose**: Modular, reusable rule definitions

**File Structure**:
```yaml
---
created: YYYY-MM-DD
modified: YYYY-MM-DD
reviewed: YYYY-MM-DD
---

# Rule Title

[Clear, specific guidance on a single concern]
```

**Quality Indicators**:
- ✅ One concern per rule file
- ✅ Descriptive file names (kebab-case)
- ✅ Clear scope and applicability
- ✅ Actionable guidance with examples
- ✅ Cross-references to related rules

**Common Rules**:
- `plugin-structure.md` - Plugin organization
- `release-please.md` - Version management
- `skill-development.md` - Skill creation patterns
- `agentic-optimization.md` - CLI optimization for AI
- `command-naming.md` - Command conventions

### Architecture Decision Records (ADRs)

**Purpose**: Document significant architectural choices

**Format**: MADR (Markdown Architecture Decision Records)

**Structure**:
```markdown
# ADR-NNNN: Title

**Date**: YYYY-MM
**Status**: Accepted | Superseded | Deprecated
**Deciders**: [who decided]

## Context
[Problem and constraints]

## Decision
[What was decided]

## Consequences
[Positive and negative outcomes]
```

**Location**: `docs/adrs/` or `docs/adr/`

**Naming**: Sequential numbers, kebab-case titles
- `0001-plugin-based-architecture.md`
- `0002-domain-driven-organization.md`

**Quality Indicators**:
- ✅ All major architectural decisions documented
- ✅ Sequential numbering without gaps
- ✅ Clear context and rationale
- ✅ Consequences documented (both pros and cons)
- ✅ Index file maintained
- ✅ Status accurate (Accepted/Superseded/Deprecated)

### Product Requirements Documents (PRDs)

**Purpose**: Define what needs to be built and why

**Location**: `docs/prds/` or `.claude/blueprints/prds/`

**Structure**:
```markdown
# Project/Feature Name - PRD

**Created**: YYYY-MM-DD
**Status**: Draft | Active | Implemented | Archived
**Version**: X.Y

## Executive Summary
- Problem Statement
- Proposed Solution
- Business Impact

## Stakeholders & Personas
[Who cares and who uses]

## Functional Requirements
[What the system must do]

## Non-Functional Requirements
[Performance, security, accessibility]

## Success Metrics
[How we measure success]

## Scope
- In Scope
- Out of Scope

## Technical Considerations
[Architecture, dependencies, integrations]
```

**Quality Indicators**:
- ✅ Clear problem statement
- ✅ User personas defined
- ✅ Specific, measurable requirements
- ✅ Success metrics defined
- ✅ Scope explicitly bounded
- ✅ Status field accurate
- ✅ Updated when requirements change

### Product Requirement Prompts (PRPs)

**Purpose**: AI-executable feature specifications (Blueprint methodology)

**Location**: `docs/prps/`

**Structure**:
```markdown
# [Feature Name] PRP

## Goal & Why
[One sentence goal + business justification]

## Success Criteria
[Specific, testable acceptance criteria]

## Context
- **Documentation References**: [URLs with sections]
- **ai_docs References**: [Curated context]
- **Codebase Intelligence**: [Files, patterns, snippets]
- **Known Gotchas**: [Warnings and mitigations]

## Implementation Blueprint
[Architecture decision + task breakdown + pseudocode]

## TDD Requirements
[Test strategy + critical test cases]

## Validation Gates
[Executable commands for quality gates]

## Confidence Score: X/10
- Context Completeness: X/10
- Implementation Clarity: X/10
- Gotchas Documented: X/10
- Validation Coverage: X/10
```

**Quality Indicators**:
- ✅ Explicit file paths and line numbers
- ✅ Code snippets from actual codebase
- ✅ Executable validation commands
- ✅ Honest confidence scoring (≥7 for execution)
- ✅ Known gotchas with mitigations
- ✅ Test strategy defined

## Quality Analysis Commands

### Check for Frontmatter

```bash
# Check if file has required frontmatter
grep -A 5 "^---$" CLAUDE.md | grep -E "(created|modified|reviewed):"

# Find files missing frontmatter
for f in docs/adrs/*.md; do
  grep -q "^---$" "$f" || echo "Missing frontmatter: $f"
done
```

### Validate ADR Naming

```bash
# Check ADR naming convention (NNNN-title.md)
find docs/adrs -name "*.md" ! -name "README.md" ! -name "[0-9][0-9][0-9][0-9]-*.md"

# Check for sequential numbering
ls docs/adrs/[0-9]*.md | sort
```

### Check Documentation Freshness

```bash
# Find docs not modified in 6 months
find docs -name "*.md" -mtime +180

# Check git history for documentation
git log --since="6 months ago" --oneline -- docs/ .claude/ CLAUDE.md

# Last modification of specific doc
git log -1 --format="%ai %s" -- CLAUDE.md
```

### Validate Sections

```bash
# Check if ADR has required sections
grep -E "^## (Context|Decision|Consequences)" docs/adrs/0001-*.md

# Check PRD completeness
grep -E "^## (Executive Summary|Functional Requirements|Success Metrics)" docs/prds/*.md
```

### Count Documentation

```bash
# Documentation inventory
echo "CLAUDE.md: $(test -f CLAUDE.md && echo '✅' || echo '❌')"
echo "Rules: $(ls .claude/rules/*.md 2>/dev/null | wc -l) files"
echo "ADRs: $(ls docs/adrs/*.md 2>/dev/null | grep -v README | wc -l) files"
echo "PRDs: $(ls docs/prds/*.md 2>/dev/null | wc -l) files"
echo "PRPs: $(ls docs/prps/*.md 2>/dev/null | wc -l) files"
```

## Quality Scoring Methodology

### Overall Quality Score (0-10)

Calculate as average of five dimensions:

| Dimension | Score 9-10 | Score 7-8 | Score 5-6 | Score 3-4 | Score 0-2 |
|-----------|------------|-----------|-----------|-----------|-----------|
| **Structure** | Perfect org, all conventions | Minor naming issues | Some disorganization | Poor structure | Missing/chaotic |
| **Completeness** | All sections present | 1-2 missing sections | Several gaps | Major gaps | Severely incomplete |
| **Freshness** | Updated <3mo | Updated <6mo | Updated <12mo | Stale >12mo | Abandoned >24mo |
| **Standards** | Perfect compliance | Minor deviations | Some non-compliance | Poor compliance | No standards |
| **Content Quality** | Excellent clarity | Good with minor issues | Acceptable | Unclear/vague | Unusable |

### Dimension-Specific Scoring

**Structure (Organization & Naming)**:
- File naming conventions followed
- Directory structure logical
- Sequential numbering (ADRs)
- Proper categorization (.claude/rules/)

**Completeness (Required Elements)**:
- All required sections present
- Frontmatter complete
- Cross-references included
- Examples provided where needed

**Freshness (Currency)**:
- `modified` dates recent
- Git commits align with modified dates
- Reflects current codebase state
- Regular review cadence

**Standards Compliance (Format Adherence)**:
- Frontmatter present and correct
- Template structure followed
- Markdown formatting valid
- Links and references work

**Content Quality (Clarity & Usefulness)**:
- Clear, specific language
- Actionable guidance
- Relevant examples
- Appropriate detail level
- No contradictions or confusion

## Common Documentation Issues

### Critical Issues (Must Fix)

| Issue | Detection | Fix |
|-------|-----------|-----|
| Missing CLAUDE.md | `! -f CLAUDE.md` | Create using project template |
| No frontmatter | `! grep "^---$"` | Add YAML frontmatter with dates |
| Completely outdated | modified >24mo | Review and update or archive |
| Broken structure | Missing required sections | Follow template structure |
| Invalid ADR naming | Not NNNN-title.md | Rename to follow convention |

### Warnings (Should Fix)

| Issue | Detection | Fix |
|-------|-----------|-----|
| Stale docs | modified >6mo | Review and update modified date |
| Missing sections | Template mismatch | Add missing sections |
| No ADR index | No README in adrs/ | Create index file |
| Vague requirements | Review content | Add specificity and examples |
| Low confidence PRP | Score <7 | Research more context |

### Suggestions (Nice to Have)

| Issue | Detection | Fix |
|-------|-----------|-----|
| Sparse rules | <3 rule files | Extract common patterns to rules |
| No PRPs | Empty prps/ dir | Create PRPs for planned features |
| Missing examples | Grep for code blocks | Add code examples |
| Poor cross-refs | Few markdown links | Link related documentation |
| No metrics | PRD without success criteria | Define measurable metrics |

## Analysis Workflow

### 1. Inventory Phase

Collect all documentation:
```bash
# List all documentation
find . -name "CLAUDE.md" -o -path "*/.claude/rules/*.md" -o -path "*/docs/adrs/*.md" -o -path "*/docs/prds/*.md" -o -path "*/docs/prps/*.md"
```

Create inventory:
- Count files by type
- Note missing standard docs
- Check directory structure

### 2. Validation Phase

For each document type:
- **Read** the file
- **Check** frontmatter exists and is valid
- **Verify** required sections present
- **Validate** naming conventions
- **Assess** content quality

### 3. Freshness Phase

Check currency:
```bash
# Git last modified
git log -1 --format="%ai" -- path/to/doc.md

# Compare frontmatter vs git
# (modified date should match recent git activity)
```

Flag stale documents:
- >6mo: Warning
- >12mo: Concern
- >24mo: Critical

### 4. Scoring Phase

Calculate scores:
1. **Structure**: File org, naming (0-10)
2. **Completeness**: Sections present (0-10)
3. **Freshness**: Currency (0-10)
4. **Standards**: Format compliance (0-10)
5. **Content**: Quality, clarity (0-10)

**Overall** = Average of 5 dimensions

### 5. Reporting Phase

Generate report:
- Executive summary with overall score
- Inventory table
- Dimension scores
- Critical issues (must fix)
- Warnings (should fix)
- Suggestions (nice to have)
- Actionable recommendations with specific files/fixes

## Agentic Optimizations

| Task | Optimized Approach |
|------|-------------------|
| List docs | `find` with multiple `-name` patterns, single command |
| Check frontmatter | `grep -l "^---$" *.md` batch check |
| Validate names | Shell globbing `[0-9][0-9][0-9][0-9]-*.md` |
| Count files | Pipeline `ls | wc -l` |
| Git history | `git log --since="6 months ago" --oneline` |
| Batch validation | `for` loop over files, collect issues |

## Quick Reference

### Frontmatter Template

```yaml
---
created: 2026-01-08
modified: 2026-01-08
reviewed: 2026-01-08
---
```

### ADR Quick Template

```markdown
# ADR-NNNN: Title

**Date**: 2026-01
**Status**: Accepted

## Context
[Why this decision?]

## Decision
[What did we decide?]

## Consequences
✅ Pros: ...
❌ Cons: ...
```

### Quality Score Guide

- **9-10**: Excellent - Reference quality
- **7-8**: Good - Minor improvements
- **5-6**: Fair - Several issues
- **3-4**: Poor - Major work needed
- **0-2**: Critical - Severe problems

## Related Tools

- `/docs:quality-check` - Run comprehensive analysis
- `/blueprint:init` - Initialize Blueprint Development
- `/blueprint:prd` - Generate PRD from project docs
- `/blueprint:adr` - Generate ADRs from codebase
- `/blueprint:prp-create` - Create PRP for feature

## Best Practices

1. **Regular Reviews**: Run quality checks monthly
2. **Update Modified Dates**: When editing, update frontmatter
3. **Quarterly Reviews**: Update `reviewed` date every 3 months
4. **Template Adherence**: Use standard templates consistently
5. **Specificity**: Prefer explicit over vague (file paths, metrics)
6. **Cross-Reference**: Link related documentation
7. **Examples**: Include code snippets and real examples
8. **Scope Management**: One concern per document
9. **Git Sync**: Commit docs with code changes
10. **AI-Friendly**: Write for both humans and AI assistants

## Error Handling

```bash
# Safe directory checks
test -d docs/adrs && ls docs/adrs || echo "ADRs directory not found"

# Safe file reads with fallback
cat CLAUDE.md 2>/dev/null || echo "CLAUDE.md not found"

# Git-aware freshness (works without git)
git log -1 --format="%ai" -- CLAUDE.md 2>/dev/null || echo "No git history"

# Glob with no-match handling
shopt -s nullglob
for f in docs/adrs/*.md; do
  echo "Processing $f"
done
```

## References

- [MADR (Markdown ADR)](https://adr.github.io/madr/) - ADR template format
- [Michael Nygard ADR](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions) - Original ADR format
- Blueprint Development methodology - PRP/PRD patterns
- `.claude/rules/` - Project-specific documentation standards
