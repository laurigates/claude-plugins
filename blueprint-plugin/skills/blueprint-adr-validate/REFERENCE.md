# blueprint-adr-validate REFERENCE

## Validation Rules

### Supersedes Validation
- Target file must exist
- Target status must be "Superseded"
- Target must have `superseded_by: ADR-{this}`
- Create error if any check fails

### Extends Validation
- Target file must exist (error if missing)
- Warn if target status is "Superseded"
- Cannot extend self

### Related Validation
- All referenced ADRs must exist (error if missing)
- Warn if link is one-way (target doesn't reference back)
- Cannot relate to self

### Error Conditions
- Self-reference: ADR relates to itself
- Circular chain: A supersedes B supersedes A
- Broken reference: Target ADR doesn't exist
- Inconsistent supersession: Supersedes but target not marked Superseded

## Report Format

```
ADR Validation Report
====================

Summary:
- Total ADRs: N
- With domain tags: N (X%)
- With relationships: N
- Status breakdown:
  - Accepted: N
  - Proposed: N
  - Superseded: N

Reference Integrity:
✅ Supersedes: Valid
⚠️ Extends: N warnings
❌ Related: N errors

Errors Found:
- ADR-0005: supersedes ADR-0003 but ADR-0003 not marked "Superseded"

Domain Analysis:
⚠️ state-management: 2 Accepted (conflict)
  - ADR-0003: Redux
  - ADR-0012: Zustand
  → Recommendation: ADR-0012 should supersede ADR-0003

✅ api-design: Consistent

Untagged ADRs (consider adding domain):
- ADR-0001: Language Choice
```

## Remediation Procedures

### Fix All Automatically
For each error:
1. If supersession mismatch → Update target status to "Superseded", add `superseded_by`
2. If one-way link → Add reciprocal `related:` entry to target

### Review Each Issue
1. Show issue context: ADR-X says Y, but Z
2. Ask: "Yes fix", "Skip", "Stop reviewing"
3. Apply fixes selected by user

### Export Report
Write full validation report to `docs/adrs/validation-report.md` with timestamp

## Frontmatter Extraction

Safe extraction pattern (avoids reserved variables):
```bash
adr_status=$(head -50 "$file" | grep -m1 "^status:" | sed 's/^[^:]*:[[:space:]]*//')
adr_domain=$(head -50 "$file" | grep -m1 "^domain:" | sed 's/^[^:]*:[[:space:]]*//')
adr_supersedes=$(head -50 "$file" | grep -m1 "^supersedes:" | sed 's/^[^:]*:[[:space:]]*//')
```

## Tips
- Run after creating new ADRs
- Domain conflicts indicate decisions needing reconciliation
- Untagged ADRs are valid but harder to analyze
- Use `/blueprint:derive-adr` to create ADRs with proper relationships
