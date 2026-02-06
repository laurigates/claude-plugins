---
model: haiku
description: Export analytics data in various formats
args: "[format] [output-file]"
allowed-tools: Bash(jq *), Bash(cat *), Read
argument-hint: "Format: json, csv, or markdown. Optional output file path."
created: 2026-01-10
modified: 2026-01-10
reviewed: 2026-01-10
name: analytics-export
---

# /analytics:export

Export analytics data for external analysis or reporting.

## Context

Check analytics availability:

```bash
ANALYTICS_DIR="${HOME}/.claude-analytics"
SUMMARY_FILE="${ANALYTICS_DIR}/summary.json"
EVENTS_FILE="${ANALYTICS_DIR}/events.jsonl"

if [[ ! -f "${SUMMARY_FILE}" ]]; then
  echo "No analytics data to export."
  exit 0
fi

TOTAL=$(cat "${SUMMARY_FILE}" | jq -r '.total_invocations')
echo "Exporting ${TOTAL} invocations..."
```

## Parameters

- `$ARGS` - Format and optional output file:
  - `json` (default) - Export as JSON
  - `csv` - Export as CSV for spreadsheet analysis
  - `markdown` - Export as markdown table

## Execution

**Export analytics data:**

```bash
ANALYTICS_DIR="${HOME}/.claude-analytics"
SUMMARY_FILE="${ANALYTICS_DIR}/summary.json"
EVENTS_FILE="${ANALYTICS_DIR}/events.jsonl"

# Parse arguments
FORMAT=$(echo "${ARGS}" | awk '{print $1}')
OUTPUT_FILE=$(echo "${ARGS}" | awk '{print $2}')

FORMAT=${FORMAT:-json}

case "${FORMAT}" in
  json)
    if [[ -n "${OUTPUT_FILE}" ]]; then
      cat "${SUMMARY_FILE}" > "${OUTPUT_FILE}"
      echo "✓ Exported to: ${OUTPUT_FILE}"
    else
      echo "📦 Analytics Summary (JSON):"
      echo ""
      cat "${SUMMARY_FILE}" | jq '.'
    fi
    ;;

  csv)
    OUTPUT=${OUTPUT_FILE:-/dev/stdout}

    if [[ "${OUTPUT}" == "/dev/stdout" ]]; then
      echo "📦 Analytics Summary (CSV):"
      echo ""
    fi

    {
      echo "Name,Type,Count,Success,Failure,Success Rate,First Used,Last Used"
      cat "${SUMMARY_FILE}" | jq -r '
        .items |
        to_entries[] |
        [
          .key,
          .value.type,
          .value.count,
          .value.success,
          .value.failure,
          (.value.success * 100 / (.value.success + .value.failure)),
          .value.first_used,
          .value.last_used
        ] |
        @csv
      '
    } > "${OUTPUT}"

    if [[ "${OUTPUT}" != "/dev/stdout" ]]; then
      echo "✓ Exported to: ${OUTPUT}"
    fi
    ;;

  markdown)
    OUTPUT=${OUTPUT_FILE:-/dev/stdout}

    if [[ "${OUTPUT}" == "/dev/stdout" ]]; then
      echo "📦 Analytics Summary (Markdown):"
      echo ""
    fi

    {
      echo "# Command & Skill Analytics"
      echo ""
      TOTAL=$(cat "${SUMMARY_FILE}" | jq -r '.total_invocations')
      SINCE=$(cat "${SUMMARY_FILE}" | jq -r '.tracking_since')
      echo "**Total invocations:** ${TOTAL}"
      echo "**Tracking since:** ${SINCE}"
      echo ""

      echo "## Commands"
      echo ""
      echo "| Command | Uses | Success | Failure | Success Rate |"
      echo "|---------|------|---------|---------|--------------|"
      cat "${SUMMARY_FILE}" | jq -r '
        .items |
        to_entries[] |
        select(.value.type == "command") |
        "| \(.key) | \(.value.count) | \(.value.success) | \(.value.failure) | \((.value.success * 100 / (.value.success + .value.failure)) | floor)% |"
      ' | sort -t'|' -k2 -nr

      echo ""
      echo "## Skills"
      echo ""
      echo "| Skill | Uses | Success | Failure | Success Rate |"
      echo "|-------|------|---------|---------|--------------|"
      cat "${SUMMARY_FILE}" | jq -r '
        .items |
        to_entries[] |
        select(.value.type == "skill") |
        "| \(.key) | \(.value.count) | \(.value.success) | \(.value.failure) | \((.value.success * 100 / (.value.success + .value.failure)) | floor)% |"
      ' | sort -t'|' -k2 -nr
    } > "${OUTPUT}"

    if [[ "${OUTPUT}" != "/dev/stdout" ]]; then
      echo "✓ Exported to: ${OUTPUT}"
    fi
    ;;

  *)
    echo "❌ Unknown format: ${FORMAT}"
    echo ""
    echo "Supported formats:"
    echo "  • json     - JSON format"
    echo "  • csv      - CSV for spreadsheet import"
    echo "  • markdown - Markdown table"
    echo ""
    echo "Examples:"
    echo "  /analytics:export json"
    echo "  /analytics:export csv analytics.csv"
    echo "  /analytics:export markdown report.md"
    exit 1
    ;;
esac

echo ""
echo "💡 Tip: Raw event data is in ${EVENTS_FILE}"
```

## Post-actions

None.
