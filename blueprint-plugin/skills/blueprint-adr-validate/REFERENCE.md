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

### ADR-Number Collisions (issue #1585)

`scripts/check-adr-numbers.sh` guards the parallel-PR numbering race. ADR
numbers are chosen at branch time but claimed at merge time, so two in-flight
ADR PRs can pick the same number and both land (the FVH infrastructure #2015
collision: two ADRs both numbered `0038`). The check is deterministic and
emits the `=== ADR NUMBER AUDIT ===` / `STATUS=` / `ISSUE_COUNT=` convention.

| Type | Severity | Meaning |
|------|----------|---------|
| `duplicate_adr_number` | ERROR | Two files in the working tree lead with the same `NNNN-`. |
| `adr_number_collision` | ERROR | A working-tree ADR's number is already held by a **different** filename on the base ref (`origin/main`) — the pre-merge parallel-PR case. |
| `adr_missing_index_row` | WARN | An ADR file is not referenced from the ADR directory's `README.md` index. |

It resolves the ADR directory as `docs/adrs/` (blueprint canonical) or
`docs/adr/`, degrades to `STATUS=OK` when neither exists, and skips the base-ref
comparison (still checking duplicates + index) when `origin/main` is
unavailable. Flags:

- `--project-dir <path>` — repo root (default: cwd).
- `--base-ref <ref>` — collision comparison ref (default: `origin/main`).

Remediation for an ERROR: renumber the newer ADR to the next free sequential
number, rewrite its `# ADR-NNNN:` title, and backfill the README index row.

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
- Use `/blueprint:derive-plans` to create ADRs with proper relationships
