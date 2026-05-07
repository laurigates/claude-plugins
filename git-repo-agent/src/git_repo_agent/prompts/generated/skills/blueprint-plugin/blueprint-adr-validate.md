# /blueprint:adr-validate

Validate Architecture Decision Records for relationship consistency, reference integrity, and domain conflicts.

**Usage**: `/blueprint:adr-validate [--report-only]`


## Execution

Execute complete ADR validation and remediation workflow:


### Step 1: Discover all ADRs

1. Check for ADR directory at `docs/adrs/`
2. If missing → Error: "No ADRs found in docs/adrs/"
3. Parse all ADR files: `ls docs/adrs/*.md`
4. Extract frontmatter for each ADR: number, date, status, domain, supersedes, superseded_by, extends, related


### Step 2: Validate reference integrity

For each ADR, validate:

1. **supersedes references**: Verify target exists, target status = "Superseded", target has reciprocal superseded_by
2. **extends references**: Verify target exists, warn if target is "Superseded"
3. **related references**: Verify all targets exist, warn if one-way links
4. **self-references**: Flag if ADR references itself
5. **circular chains**: Detect cycles in supersession graph
6. **Cross-workspace references** (v3.3.0+, manifests with `workspaces.role`):
   Recognise these reference forms in supersedes/extends/related fields:
   - `ADR-NNN` — local to the current workspace (existing behaviour).
   - `<workspace-path>/ADR-NNN` — points into a sibling/child workspace. Resolve
     by reading `<workspace-path>/docs/adrs/` from the monorepo root. Warn if
     the workspace is not listed in root `workspaces.children`.
   - `/ADR-NNN` — points at the monorepo root's ADR set. Resolve using the
     manifest's `workspaces.root_relative_path` (for child manifests) or the
     current directory (for root manifests).
   Unresolved cross-workspace refs are reported as warnings (not errors) so
   they do not block validation during migration.

See [REFERENCE.md](REFERENCE.md#validation-rules) for detailed checks.


### Step 3: Analyze domains

1. Group ADRs by domain field
2. For each domain with multiple "Accepted" ADRs → potential conflict flag
3. List untagged ADRs (not errors, but recommendations)


### Step 4: Generate validation report

Compile comprehensive report showing:
- Summary: Total ADRs, domain-tagged %, relationship counts, status breakdown
- Reference integrity: Supersedes, extends, related status (✅/⚠️/❌)
- Errors found: Broken references, self-references, cycles
- Warnings: Outdated extensions, one-way links
- Domain analysis: Conflicts and untagged ADRs


### Step 5: Handle --report-only flag

If `--report-only` flag present:
1. Output validation report from Step 4
2. Exit without prompting for fixes


### Step 6: Prompt for remediation (if interactive mode)

Ask user action via report to orchestrator:
- Fix all automatically (update status, add reciprocal links)
- Review each issue individually
- Export report to `docs/adrs/validation-report.md`
- Skip for now

Execute based on selection (see [REFERENCE.md](REFERENCE.md#remediation-procedures)).


### Step 7: Update task registry

Update the task registry entry in `docs/blueprint/manifest.json`:

```bash
jq --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg result "${VALIDATION_RESULT:-success}" \
  --argjson processed "${ADRS_VALIDATED:-0}" \
  '.task_registry["adr-validate"].last_completed_at = $now |
   .task_registry["adr-validate"].last_result = $result |
   .task_registry["adr-validate"].stats.runs_total = ((.task_registry["adr-validate"].stats.runs_total // 0) + 1) |
   .task_registry["adr-validate"].stats.items_processed = $processed' \
  docs/blueprint/manifest.json > tmp.json && mv tmp.json docs/blueprint/manifest.json
```

Where `VALIDATION_RESULT` is "success", "{N} warnings", or "failed: {reason}".


### Step 8: Report changes and summary

Report all changes made:
- Updated ADRs (status changes, added links)
- Remaining issues count
- Next steps recommendation


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