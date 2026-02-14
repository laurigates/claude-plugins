---
model: haiku
name: documentation-quality
description: Analyze and validate documentation quality for PRDs, ADRs, PRPs, CLAUDE.md, and .claude/rules/ to ensure standards compliance and freshness
allowed-tools: Bash(markdownlint *), Bash(vale *), Read, Grep, Glob, TodoWrite
created: 2026-01-08
modified: 2026-02-14
reviewed: 2026-01-08
---

# Documentation Quality Analysis

Expert analysis of technical documentation quality, structure, and maintenance for codebases using Blueprint Development methodology and Claude Code conventions.

For detailed examples, advanced patterns, and best practices, see [REFERENCE.md](REFERENCE.md).

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

## Documentation Type Summary

| Type | Location | Key Requirement |
|------|----------|-----------------|
| CLAUDE.md | Project root | Project structure, rules, conventions |
| .claude/rules/ | Rule directory | One concern per file, kebab-case names |
| ADRs | `docs/adrs/` | NNNN-title.md naming, Context/Decision/Consequences sections |
| PRDs | `docs/prds/` | Problem statement, requirements, success metrics, scope |
| PRPs | `docs/prps/` | Goal, success criteria, implementation blueprint, confidence score |

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
echo "CLAUDE.md: $(test -f CLAUDE.md && echo 'exists' || echo 'missing')"
echo "Rules: $(ls .claude/rules/*.md 2>/dev/null | wc -l) files"
echo "ADRs: $(ls docs/adrs/*.md 2>/dev/null | grep -v README | wc -l) files"
echo "PRDs: $(ls docs/prds/*.md 2>/dev/null | wc -l) files"
echo "PRPs: $(ls docs/prps/*.md 2>/dev/null | wc -l) files"
```

## Quality Scoring Summary

Calculate as average of five dimensions (each 0-10):

| Dimension | What to Check |
|-----------|---------------|
| **Structure** | File org, naming conventions, directory layout |
| **Completeness** | Required sections, frontmatter, cross-references |
| **Freshness** | Modified dates, git history, review cadence |
| **Standards** | Format adherence, markdown validity, working links |
| **Content Quality** | Clarity, actionable guidance, relevant examples |

**Score Guide**: 9-10 Excellent, 7-8 Good, 5-6 Fair, 3-4 Poor, 0-2 Critical

## Agentic Optimizations

| Task | Optimized Approach |
|------|-------------------|
| List docs | `find` with multiple `-name` patterns, single command |
| Check frontmatter | `grep -l "^---$" *.md` batch check |
| Validate names | Shell globbing `[0-9][0-9][0-9][0-9]-*.md` |
| Count files | Pipeline `ls \| wc -l` |
| Git history | `git log --since="6 months ago" --oneline` |
| Batch validation | `for` loop over files, collect issues |

## Quick Reference

### Frontmatter Template

```yaml
---
created: 2026-01-08
modified: 2026-02-14
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
Pros: ...
Cons: ...
```

### Quality Score Guide

- **9-10**: Excellent - Reference quality
- **7-8**: Good - Minor improvements
- **5-6**: Fair - Several issues
- **3-4**: Poor - Major work needed
- **0-2**: Critical - Severe problems

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

## Related Tools

- `/docs:quality-check` - Run comprehensive analysis
- `/blueprint:init` - Initialize Blueprint Development
- `/blueprint:prd` - Generate PRD from project docs
- `/blueprint:adr` - Generate ADRs from codebase
- `/blueprint:prp-create` - Create PRP for feature

## References

- [MADR (Markdown ADR)](https://adr.github.io/madr/) - ADR template format
- [Michael Nygard ADR](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions) - Original ADR format
- Blueprint Development methodology - PRP/PRD patterns
- `.claude/rules/` - Project-specific documentation standards
