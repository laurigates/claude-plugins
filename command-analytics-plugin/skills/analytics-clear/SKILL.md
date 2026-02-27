---
model: haiku
description: Clear all analytics data and start fresh
args: "[--confirm]"
allowed-tools: Bash
argument-hint: "Use --confirm to skip confirmation prompt"
disable-model-invocation: true
created: 2026-01-10
modified: 2026-01-10
reviewed: 2026-01-10
name: analytics-clear
---

# /analytics:clear

Reset all analytics data, removing tracking history and statistics.

## Context

Check if analytics data exists:

```bash
ANALYTICS_DIR="${HOME}/.claude-analytics"

if [[ -d "${ANALYTICS_DIR}" ]]; then
  SUMMARY_FILE="${ANALYTICS_DIR}/summary.json"
  if [[ -f "${SUMMARY_FILE}" ]]; then
    TOTAL=$(cat "${SUMMARY_FILE}" | jq -r '.total_invocations // 0')
    SINCE=$(cat "${SUMMARY_FILE}" | jq -r '.tracking_since // "unknown"')
    echo "Current analytics: ${TOTAL} invocations since ${SINCE}"
  fi
else
  echo "No analytics data to clear."
  exit 0
fi
```

## Parameters

- `$ARGS` - Optional `--confirm` flag to skip confirmation

## Execution

**Clear analytics data:**

```bash
ANALYTICS_DIR="${HOME}/.claude-analytics"
CONFIRM="${ARGS}"

if [[ "${CONFIRM}" != "--confirm" ]]; then
  echo "⚠️  This will permanently delete all analytics data."
  echo ""
  echo "This includes:"
  echo "  • All command/skill usage history"
  echo "  • Success/failure statistics"
  echo "  • Timing data"
  echo ""
  read -p "Are you sure? (yes/no): " RESPONSE

  if [[ "${RESPONSE}" != "yes" ]]; then
    echo "Cancelled."
    exit 0
  fi
fi

echo ""
echo "🗑️  Clearing analytics data..."

if [[ -d "${ANALYTICS_DIR}" ]]; then
  rm -rf "${ANALYTICS_DIR}"
  echo "✓ Analytics data cleared"
  echo ""
  echo "Analytics will start collecting again automatically."
else
  echo "No analytics data found."
fi
```

## Post-actions

None. Analytics tracking will automatically restart on next command/skill usage.
