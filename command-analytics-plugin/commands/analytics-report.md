---
description: Display command and skill usage analytics
args: "[filter]"
allowed-tools: Bash, Read
argument-hint: "Optional filter: 'commands', 'skills', or specific name"
created: 2026-01-10
modified: 2026-01-10
reviewed: 2026-01-10
---

# /analytics:report

Display usage analytics for commands and skills across all projects.

## Context

Check if analytics data exists:

```bash
if [[ -f ~/.claude-analytics/summary.json ]]; then
  echo "Analytics available"
  SUMMARY=$(cat ~/.claude-analytics/summary.json)
  TOTAL=$(echo "$SUMMARY" | jq -r '.total_invocations // 0')
  SINCE=$(echo "$SUMMARY" | jq -r '.tracking_since // "unknown"')
  echo "Total invocations: $TOTAL"
  echo "Tracking since: $SINCE"
else
  echo "No analytics data found. Start using commands to collect data."
  exit 0
fi
```

## Parameters

- `$ARGS` - Optional filter:
  - Empty: Show all analytics
  - `commands`: Show only commands
  - `skills`: Show only skills
  - `<name>`: Show specific command/skill details

## Execution

**Display analytics report:**

```bash
ANALYTICS_DIR="${HOME}/.claude-analytics"
SUMMARY_FILE="${ANALYTICS_DIR}/summary.json"
EVENTS_FILE="${ANALYTICS_DIR}/events.jsonl"

if [[ ! -f "${SUMMARY_FILE}" ]]; then
  echo "📊 No analytics data yet"
  echo ""
  echo "Analytics will be collected automatically as you use commands and skills."
  echo "Data is stored in: ${ANALYTICS_DIR}"
  exit 0
fi

SUMMARY=$(cat "${SUMMARY_FILE}")
FILTER="${ARGS:-all}"

echo "📊 Command & Skill Analytics"
echo ""

# Header info
TOTAL=$(echo "$SUMMARY" | jq -r '.total_invocations')
SINCE=$(echo "$SUMMARY" | jq -r '.tracking_since')
echo "Total invocations: ${TOTAL}"
echo "Tracking since: ${SINCE}"
echo ""

# Top used items
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Most Used"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ "${FILTER}" == "all" || "${FILTER}" == "commands" ]]; then
  echo ""
  echo "📝 Commands"
  echo "$SUMMARY" | jq -r '
    .items |
    to_entries |
    map(select(.value.type == "command")) |
    sort_by(-.value.count) |
    .[:10] |
    .[] |
    "  \(.value.count | tostring | (. + "       ")[:6]) \(.key)  (\(.value.success)✓ \(.value.failure)✗)"
  '
fi

if [[ "${FILTER}" == "all" || "${FILTER}" == "skills" ]]; then
  echo ""
  echo "🎯 Skills"
  echo "$SUMMARY" | jq -r '
    .items |
    to_entries |
    map(select(.value.type == "skill")) |
    sort_by(-.value.count) |
    .[:10] |
    .[] |
    "  \(.value.count | tostring | (. + "       ")[:6]) \(.key)  (\(.value.success)✓ \(.value.failure)✗)"
  '
fi

# Success rate
if [[ "${FILTER}" == "all" ]]; then
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Success Rates"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  TOTAL_SUCCESS=$(echo "$SUMMARY" | jq '[.items[].success] | add // 0')
  TOTAL_FAILURE=$(echo "$SUMMARY" | jq '[.items[].failure] | add // 0')
  TOTAL_OPS=$((TOTAL_SUCCESS + TOTAL_FAILURE))

  if [[ $TOTAL_OPS -gt 0 ]]; then
    SUCCESS_RATE=$(echo "scale=1; ${TOTAL_SUCCESS} * 100 / ${TOTAL_OPS}" | bc)
    echo "  Overall: ${SUCCESS_RATE}% (${TOTAL_SUCCESS}✓ ${TOTAL_FAILURE}✗)"
  fi

  # Items with failures
  echo ""
  echo "  Items with failures:"
  echo "$SUMMARY" | jq -r '
    .items |
    to_entries |
    map(select(.value.failure > 0)) |
    sort_by(-.value.failure) |
    .[:5] |
    .[] |
    "    \(.key): \(.value.failure) failures"
  ' | while read -r line; do
    if [[ -n "$line" ]]; then
      echo "$line"
    else
      echo "    None!"
    fi
  done
fi

# Recent activity
if [[ "${FILTER}" == "all" ]]; then
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Recent Activity (last 10)"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  if [[ -f "${EVENTS_FILE}" ]]; then
    tail -10 "${EVENTS_FILE}" | jq -r '
      "\(.timestamp | split("T")[0] + " " + (.timestamp | split("T")[1] | split(".")[0]))  \(.name)  " +
      (if .success then "✓" else "✗" end)
    '
  fi
fi

# Specific item details
if [[ "${FILTER}" != "all" && "${FILTER}" != "commands" && "${FILTER}" != "skills" ]]; then
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Details: ${FILTER}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  echo "$SUMMARY" | jq -r \
    --arg name "${FILTER}" \
    '
    if .items[$name] then
      .items[$name] |
      "Type: \(.type)\n" +
      "Total uses: \(.count)\n" +
      "Successful: \(.success)\n" +
      "Failed: \(.failure)\n" +
      "First used: \(.first_used)\n" +
      "Last used: \(.last_used)"
    else
      "No data found for: " + $name
    end
    '

  # Show recent invocations
  if [[ -f "${EVENTS_FILE}" ]]; then
    echo ""
    echo "Recent invocations:"
    grep "\"${FILTER}\"" "${EVENTS_FILE}" | tail -5 | jq -r '
      "  \(.timestamp)  " +
      (if .success then "✓" else "✗ \(.error)" end)
    '
  fi
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "💡 Tips:"
echo "  • /analytics:report commands   - Show only commands"
echo "  • /analytics:report skills     - Show only skills"
echo "  • /analytics:unused            - Find never-used commands"
echo "  • /analytics:clear             - Reset analytics data"
```

## Post-actions

None.
