# Documentation Structure Standards (ADR, PRD, PRP)

### 4.2 ADR Structure Validation
For each ADR, verify:

**Naming Convention**:
- Format: `NNNN-kebab-case-title.md` (e.g., `0001-plugin-architecture.md`)
- Sequential numbering
- Descriptive titles

**Required Sections** (MADR format):
```markdown
# ADR-NNNN: Title

**Date**: YYYY-MM
**Status**: Accepted | Superseded | Deprecated
**Deciders**: [who made the decision]

## Context
[The issue motivating this decision]

## Decision
[The change being proposed or made]

## Consequences
[What becomes easier or harder]
```

### 5.2 PRD Structure Validation
For each PRD, verify:

**Frontmatter** (if using Blueprint methodology):
```yaml
---
id: PRD-NNN
created: YYYY-MM-DD
modified: YYYY-MM-DD
reviewed: YYYY-MM-DD
status: Draft | Proposed | Active | Completed | Deprecated
---
```

**Required Sections**:
- Executive Summary / Problem Statement
- Stakeholders & User Personas
- Functional Requirements
- Non-Functional Requirements
- Success Metrics
- Scope (In/Out of scope)
- Technical Considerations

### 6.2 PRP Structure Validation
For each PRP, verify:

**Required Sections**:
- Goal & Why
- Success Criteria (testable)
- Context (documentation refs, codebase intelligence, known gotchas)
- Implementation Blueprint (architecture, task breakdown)
- TDD Requirements (test strategy, critical test cases)
- Validation Gates (executable commands)
- Confidence Score (0-10 across dimensions)

### For Documentation Standards
- **Frontmatter**: Always include created/modified/reviewed dates
- **Structure**: Follow established templates (ADR, PRD, PRP)
- **Clarity**: Write for future maintainers and AI assistants
- **Maintenance**: Review quarterly, update modified dates
- **Cross-reference**: Link related documentation
- **Examples**: Include code snippets and real examples
- **Scope**: Keep focused - one concern per document
