---
model: haiku
created: 2026-02-06
modified: 2026-02-06
reviewed: 2026-02-06
description: "List blueprint documents (ADRs, PRDs, PRPs) with metadata extracted from frontmatter and headers"
args: "<type>"
allowed_tools: [Bash, Glob]
argument-hint: "adrs | prds | prps | all"
name: blueprint-docs-list
---

List blueprint documents programmatically from the filesystem. Extracts metadata from YAML frontmatter and markdown headers.

**Use Case**: Audit document status, generate index tables, or get a quick overview of all project documentation.

## Parameters

| Arg | Description |
|-----|-------------|
| `adrs` | List Architecture Decision Records |
| `prds` | List Product Requirements Documents |
| `prps` | List Product Requirement Prompts |
| `all` | Summary of all document types |

## Execution

### If arg is `adrs`

Run `/blueprint:adr-list` — it handles ADR-specific extraction with both header-section and frontmatter support.

### If arg is `prds`

```bash
printf "| PRD | Title | Status | Date |\n|-----|-------|--------|------|\n" && \
for f in docs/prds/*.md; do
  [ -f "$f" ] || continue
  fname=$(basename "$f")
  [ "$fname" = "README.md" ] && continue
  doc_title=$(head -50 "$f" | grep -m1 "^title:" | sed 's/^title:[[:space:]]*//' || true)
  doc_status=$(head -50 "$f" | grep -m1 "^status:" | sed 's/^status:[[:space:]]*//' || true)
  doc_date=$(head -50 "$f" | grep -m1 "^date:\|^created:" | sed 's/^[^:]*:[[:space:]]*//' || true)
  # Fallback: extract title from H1
  if [ -z "$doc_title" ]; then
    doc_title=$(head -20 "$f" | grep -m1 "^# " | sed 's/^# //')
  fi
  printf "| [%s](%s) | %s | %s | %s |\n" \
    "${fname%.md}" "$f" "${doc_title:-(untitled)}" "${doc_status:--}" "${doc_date:--}"
done
```

### If arg is `prps`

```bash
printf "| PRP | Title | Status | Confidence |\n|-----|-------|--------|------------|\n" && \
for f in docs/prps/*.md; do
  [ -f "$f" ] || continue
  fname=$(basename "$f")
  [ "$fname" = "README.md" ] && continue
  doc_title=$(head -50 "$f" | grep -m1 "^title:" | sed 's/^title:[[:space:]]*//' || true)
  doc_status=$(head -50 "$f" | grep -m1 "^status:" | sed 's/^status:[[:space:]]*//' || true)
  doc_confidence=$(head -50 "$f" | grep -m1 "^confidence:" | sed 's/^confidence:[[:space:]]*//' || true)
  if [ -z "$doc_title" ]; then
    doc_title=$(head -20 "$f" | grep -m1 "^# " | sed 's/^# //')
  fi
  printf "| [%s](%s) | %s | %s | %s |\n" \
    "${fname%.md}" "$f" "${doc_title:-(untitled)}" "${doc_status:--}" "${doc_confidence:--}"
done
```

### If arg is `all`

Show counts and status breakdown for each document type:

```bash
echo "## Blueprint Documents Summary"
echo ""
for doc_type in adrs prds prps; do
  doc_count=$(ls docs/$doc_type/*.md 2>/dev/null | grep -cv 'README.md' || echo 0)
  echo "### ${doc_type^^}: $doc_count documents"
  if [ "$doc_count" -gt 0 ]; then
    for s in Accepted Proposed Deprecated Superseded draft ready approved; do
      sc=$(grep -ril "^status:.*$s\|^$s$" docs/$doc_type/*.md 2>/dev/null | wc -l | tr -d ' ')
      [ "$sc" -gt 0 ] && echo "- $s: $sc"
    done
  fi
  echo ""
done
```

## Post-Actions

After listing, suggest:
- For empty directories: "Run `/blueprint:derive-adr` or `/blueprint:derive-prd` to generate documents"
- For stale documents: "Review documents with status 'draft' or 'Proposed'"
