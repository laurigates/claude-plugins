---
created: 2026-01-15
modified: 2026-01-18
reviewed: 2026-01-15
description: "Validate ADR relationships, detect orphaned references, and check domain consistency"
allowed_tools: [Read, Bash, Glob, Grep, Edit, AskUserQuestion]
---

Validate Architecture Decision Records for relationship consistency, reference integrity, and domain conflicts.

**Use Cases**:
- Ensure ADR integrity before major releases
- Audit documentation after refactoring
- Periodic documentation review
- Pre-merge validation in CI

**Steps**:

## Phase 1: Discovery

1. **Check for ADR directory**:
   ```bash
   ls docs/adrs/*.md 2>/dev/null | wc -l
   ```
   If no ADRs → exit with "No ADRs found in docs/adrs/"

2. **Parse all ADR frontmatter**:
   For each ADR in `docs/adrs/`:
   - Extract from YAML frontmatter:
     - ADR number (from filename: `NNNN-*.md`)
     - `date`
     - `status`
     - `domain` (optional)
     - `supersedes` (optional)
     - `superseded_by` (optional)
     - `extends` (optional)
     - `related` (optional array)
   - Build ADR registry for cross-reference validation

## Phase 2: Reference Validation

3. **Validate supersedes references**:
   For each ADR with `supersedes: ADR-XXXX`:
   - Verify target ADR file exists
   - Verify target ADR has `status: Superseded`
   - Verify target ADR has `superseded_by: ADR-{this}`
   - Flag mismatches as errors

4. **Validate extends references**:
   For each ADR with `extends: ADR-XXXX`:
   - Verify target ADR file exists
   - Verify target ADR status is NOT "Superseded" (warn if extending outdated)
   - Flag missing targets as errors

5. **Validate related references**:
   For each ADR with `related:` array:
   - Verify each referenced ADR exists
   - Check for bidirectional links (warn if one-way)
   - Flag orphaned references as errors

6. **Check for self-references**:
   - ADR cannot supersede, extend, or relate to itself
   - Flag as error

7. **Check for circular supersedes**:
   - Build supersession graph
   - Detect cycles (A supersedes B supersedes A)
   - Flag as error

## Phase 3: Domain Analysis

8. **Group ADRs by domain**:
   ```bash
   # Note: Use prefixed variable names to avoid shell reserved words (e.g., 'status' in zsh)
   for f in docs/adrs/*.md; do
     adr_domain=$(head -30 "$f" | grep -m1 "^domain:" | sed 's/^[^:]*:[[:space:]]*//')
     adr_status=$(head -30 "$f" | grep -m1 "^status:" | sed 's/^[^:]*:[[:space:]]*//')
     [ -n "$adr_domain" ] && echo "$adr_domain|$adr_status|$f"
   done | sort
   ```

9. **Detect domain conflicts**:
   For each domain with multiple ADRs:
   - Count "Accepted" status ADRs
   - If count > 1 → potential conflict
   - Extract decision summaries for comparison

10. **List untagged ADRs**:
    - ADRs without `domain:` field
    - Not an error, but recommendation to add

## Phase 4: Generate Report

11. **Compile validation report**:
    ```
    ADR Validation Report
    =====================

    Summary:
    - Total ADRs: {count}
    - With domain tags: {count} ({percent}%)
    - With relationships: {count}
    - Status breakdown:
      - Accepted: {count}
      - Proposed: {count}
      - Superseded: {count}
      - Deprecated: {count}

    Reference Integrity:
    {✅|❌} Supersedes references: {status}
    {✅|⚠️|❌} Extends references: {status}
    {✅|⚠️|❌} Related references: {status}

    {If errors:}
    Errors Found:
    - ADR-0005: supersedes ADR-0003 but ADR-0003 status is "Accepted" (not "Superseded")
    - ADR-0008: extends ADR-0002 which does not exist
    - ADR-0010: related to ADR-0010 (self-reference)

    {If warnings:}
    Warnings:
    - ADR-0007: extends ADR-0004 which is Superseded (consider extending ADR-0009 instead)
    - ADR-0006 ↔ ADR-0011: one-way related link (ADR-0011 doesn't reference ADR-0006)

    Domain Analysis:
    {For each domain with issues:}
    ⚠️ state-management: 2 Accepted ADRs (potential conflict)
       - ADR-0003: Use Redux for global state
       - ADR-0012: Use Zustand for state management
       → Recommendation: ADR-0012 should supersede ADR-0003

    {For domains without issues:}
    ✅ api-design: 3 ADRs (1 Accepted, 2 Superseded) - consistent

    Untagged ADRs (consider adding domain):
    - ADR-0001: Project Language Choice
    - ADR-0002: Framework Selection

    Issues Summary:
    - Errors: {count} (must fix)
    - Warnings: {count} (should review)
    - Recommendations: {count} (optional improvements)
    ```

## Phase 5: Remediation Options

12. **Prompt for action** (use AskUserQuestion):
    ```
    question: "How would you like to address the issues?"
    options:
      - label: "Fix all automatically"
        description: "Update superseded ADRs, add missing bidirectional links"
      - label: "Review each issue"
        description: "Step through issues one by one for approval"
      - label: "Export report only"
        description: "Save report to docs/adrs/validation-report.md"
      - label: "Skip for now"
        description: "Exit without changes"
    ```

13. **Execute based on selection**:

    **"Fix all automatically":**
    - For supersedes mismatches:
      - Update superseded ADR status to "Superseded"
      - Add `superseded_by: ADR-{number}`
    - For one-way related links:
      - Add reciprocal `related:` entry to target ADR
    - Report all changes made

    **"Review each issue":**
    - Loop through issues one at a time
    - For each, show context and ask:
      ```
      question: "Fix this issue?"
      options:
        - label: "Yes, apply fix"
        - label: "Skip this one"
        - label: "Stop reviewing"
      ```

    **"Export report only":**
    - Write report to `docs/adrs/validation-report.md`
    - Include timestamp

    **"Skip for now":**
    - Exit with summary count

## Phase 6: Report Changes

14. **Summarize changes made** (if any):
    ```
    Changes Applied:
    - Updated ADR-0003: status Accepted → Superseded, added superseded_by: ADR-0012
    - Updated ADR-0011: added related: [ADR-0006]

    Remaining issues: {count}
    ```

**Tips**:
- Run validation after creating new ADRs
- Domain conflicts indicate decisions that may need reconciliation
- Untagged ADRs are valid but harder to analyze for conflicts
- Use `/blueprint:adr` to create new ADRs with proper relationships
