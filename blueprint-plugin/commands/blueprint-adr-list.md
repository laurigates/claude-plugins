---
model: haiku
created: 2026-01-29
modified: 2026-01-29
reviewed: 2026-01-29
description: "List all ADRs with title, status, date, and domain in a markdown table"
allowed_tools: [Bash, Glob]
---

List Architecture Decision Records dynamically from the filesystem.

**Use Case**: Generate ADR index tables for README files, audit ADR status, or quickly view all architectural decisions.

**Steps**:

## 1. Check for ADRs

```bash
ls docs/adrs/*.md 2>/dev/null | head -1
```

If no ADRs found:
```
No ADRs found in docs/adrs/
Run `/blueprint:derive-adr` to generate ADRs from project analysis.
```

## 2. Generate ADR Table

The standard ADR format has:
- Line 1: `# ADR-NNNN: Title`
- Line 5: Status (after `## Status\n\n`)
- Line 9: Date (after `## Date\n\n`)
- Domain tag (optional): `domain: {domain}` somewhere in the file

**Command to generate markdown table**:

```bash
printf "| ADR | Title | Status | Date |\n|-----|-------|--------|------|\n" && \
fd '^[0-9]{4}-.*\.md$' docs/adrs -x awk '
  NR==1 {gsub(/^# ADR-[0-9]+: /, ""); title=$0}
  NR==5 {status=$0}
  NR==9 {date=$0}
  END {printf "| [%s](%s) | %s | %s | %s |\n", substr(FILENAME,11,4), FILENAME, title, status, date}
' {} | sort
```

**Note**: Adjust `substr(FILENAME,11,4)` offset based on path depth. For `docs/adrs/0001-*.md`:
- From repo root: offset 11 (skips `docs/adrs/`)
- If running from `docs/`: offset 6

## 3. Display Results

Output the generated table. Example:

```
| ADR | Title | Status | Date |
|-----|-------|--------|------|
| [0001](docs/adrs/0001-use-react.md) | Use React for Frontend | Accepted | 2024-01-15 |
| [0002](docs/adrs/0002-use-postgres.md) | Use PostgreSQL for Database | Accepted | 2024-01-20 |
| [0003](docs/adrs/0003-migrate-to-vite.md) | Migrate from CRA to Vite | Accepted | 2024-02-01 |
```

## 4. Optional: Extended Table with Domain

If domain tags are used, generate extended table:

```bash
printf "| ADR | Title | Status | Date | Domain |\n|-----|-------|--------|------|--------|\n" && \
fd '^[0-9]{4}-.*\.md$' docs/adrs -x awk '
  NR==1 {gsub(/^# ADR-[0-9]+: /, ""); title=$0}
  NR==5 {status=$0}
  NR==9 {date=$0}
  /^domain:/ {gsub(/^domain: */, ""); domain=$0}
  END {
    if (domain == "") domain = "-"
    printf "| [%s](%s) | %s | %s | %s | %s |\n", substr(FILENAME,11,4), FILENAME, title, status, date, domain
  }
' {} | sort
```

## 5. Summary Statistics

After the table, show summary:

```bash
echo ""
echo "**Summary**:"
echo "- Total: $(fd '^[0-9]{4}-.*\.md$' docs/adrs | wc -l | tr -d ' ') ADRs"
echo "- Accepted: $(grep -l '^Accepted$' docs/adrs/*.md 2>/dev/null | wc -l | tr -d ' ')"
echo "- Superseded: $(grep -l '^Superseded' docs/adrs/*.md 2>/dev/null | wc -l | tr -d ' ')"
echo "- Deprecated: $(grep -l '^Deprecated' docs/adrs/*.md 2>/dev/null | wc -l | tr -d ' ')"
```

**Tip**: Add this command to your `docs/adrs/README.md` so anyone can regenerate the index:

```markdown
## Listing ADRs

Generate a table of all ADRs:

\`\`\`bash
fd '^[0-9]{4}-.*\.md$' docs/adrs -x awk '...' | sort
\`\`\`
```
