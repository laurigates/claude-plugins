# Architecture Decision Records

This directory contains Architecture Decision Records (ADRs) documenting significant technical decisions for this project.

## What Are ADRs?

An ADR captures the context, options considered, and rationale behind a significant architectural or technical decision. They serve as a decision log that helps current and future team members understand _why_ the system is built the way it is.

## ADR Lifecycle

| Status | Meaning |
|--------|---------|
| **Proposed** | Decision under discussion, not yet finalized |
| **Accepted** | Decision made and in effect |
| **Deprecated** | Decision no longer relevant (technology removed, approach abandoned) |
| **Superseded** | Replaced by a newer ADR (links to successor) |

## Listing ADRs

Generate a table of all ADRs programmatically:

```bash
printf "| ADR | Title | Status | Date |\n|-----|-------|--------|------|\n" && \
fd '^[0-9]{4}-.*\.md$' docs/adrs -x awk '
  /^# ADR-/ {gsub(/^# ADR-[0-9]+: /, ""); title=$0}
  /^## Status/ {p_status=1; next}
  p_status && NF {status=$0; p_status=0}
  /^## Date/ {p_date=1; next}
  p_date && NF {date=$0; p_date=0}
  /^status:/ && !status {gsub(/^status:[[:space:]]*/, ""); status=$0}
  /^date:/ && !date {gsub(/^date:[[:space:]]*/, ""); date=$0}
  END {
    fname = FILENAME; sub(/.*\//, "", fname); num = substr(fname, 1, 4)
    if (title == "") title = "(untitled)"
    if (status == "") status = "-"
    if (date == "") date = "-"
    printf "| [%s](%s) | %s | %s | %s |\n", num, FILENAME, title, status, date
  }
' {} | sort
```

Or use `/blueprint:adr-list` for formatted output with summary statistics.

## When to Write an ADR

Write an ADR when making decisions that:
- Are **hard to reverse** (database choice, framework, API style)
- Affect **multiple components** (state management, authentication approach)
- Involve **meaningful trade-offs** between alternatives
- Will be **questioned later** ("why did we choose X?")

Skip ADRs for obvious or trivial choices with no real alternatives.

## Proposed ADRs

Decisions identified but not yet documented as full ADRs:

<!-- Add proposed decisions here as bullet points:
- [ ] Decision topic — brief context (identified YYYY-MM-DD)
-->

_No proposed ADRs at this time._

## Creating ADRs

Use `/blueprint:derive-adr` to generate ADRs from project analysis, or create manually following the [MADR template](https://adr.github.io/madr/).

ADR files follow the naming convention: `NNNN-short-title.md` (e.g., `0001-use-react.md`).

---
*Generated via /blueprint:derive-adr*
