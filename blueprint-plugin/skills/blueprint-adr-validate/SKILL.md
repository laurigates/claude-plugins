---
model: haiku
created: 2026-01-15
modified: 2026-02-14
reviewed: 2026-02-14
description: "Validate ADR relationships, detect orphaned references, and check domain consistency"
args: "[--report-only]"
argument-hint: "--report-only to validate without prompting for fixes"
allowed-tools: Read, Bash, Glob, Grep, Edit, AskUserQuestion
name: blueprint-adr-validate
---

# /blueprint:adr-validate

Validate Architecture Decision Records for relationship consistency, reference integrity, and domain conflicts.

**Usage**: `/blueprint:adr-validate [--report-only]`

## When to Use This Skill

| Use this skill when... | Use alternative when... |
|------------------------|-------------------------|
| Maintaining ADR integrity before releases | Creating new ADRs (use `/blueprint:derive-adr`) |
| Auditing after refactoring or changes | Quick one-time documentation review |
| Regular documentation review process | General ADR reading |

## Context

- ADR directory exists: !`test -d docs/adrs 2>/dev/null`
- ADR count: !`find docs/adrs -name "*.md" -type f 2>/dev/null`
- Domain-tagged ADRs: !`grep -l "^domain:" docs/adrs/*.md 2>/dev/null`
- Flag: !`echo "${1:---}" 2>/dev/null`

## Parameters

Parse `$ARGUMENTS`:

- `--report-only`: Output validation report without prompting for fixes
  - Default: Interactive mode with remediation options

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

Ask user action via AskUserQuestion:
- Fix all automatically (update status, add reciprocal links)
- Review each issue individually
- Export report to `docs/adrs/validation-report.md`
- Skip for now

Execute based on selection (see [REFERENCE.md](REFERENCE.md#remediation-procedures)).

### Step 7: Report changes and summary

Report all changes made:
- Updated ADRs (status changes, added links)
- Remaining issues count
- Next steps recommendation

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Check ADR directory | `test -d docs/adrs && echo "YES" \|\| echo "NO"` |
| Count ADRs | `ls docs/adrs/*.md 2>/dev/null \| wc -l` |
| Extract frontmatter | `head -50 {file} \| grep -m1 "^field:" \| sed 's/^[^:]*:[[:space:]]*//'` |
| Find by domain | `grep -l "^domain: {domain}" docs/adrs/*.md` |
| Detect cycles | Build supersession graph and traverse |

---

For validation rules, remediation procedures, and report format details, see [REFERENCE.md](REFERENCE.md).
