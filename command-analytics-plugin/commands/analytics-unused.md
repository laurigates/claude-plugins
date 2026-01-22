---
model: haiku
description: Show commands and skills that have never been used
args: ""
allowed-tools: Bash, Read, Glob
argument-hint: ""
created: 2026-01-10
modified: 2026-01-10
reviewed: 2026-01-10
---

# /analytics:unused

Identify commands and skills that have never been invoked, helping you discover unused features or clean up unused plugins.

## Context

Check analytics availability:

```bash
if [[ ! -f ~/.claude-analytics/summary.json ]]; then
  echo "No analytics data yet. Cannot determine unused commands/skills."
  exit 0
fi
```

## Execution

**Scan for unused commands and skills:**

```bash
ANALYTICS_DIR="${HOME}/.claude-analytics"
SUMMARY_FILE="${ANALYTICS_DIR}/summary.json"

echo "🔍 Scanning for unused commands and skills..."
echo ""

# Get list of used commands/skills
if [[ -f "${SUMMARY_FILE}" ]]; then
  USED=$(cat "${SUMMARY_FILE}" | jq -r '.items | keys[]')
else
  USED=""
fi

# Find all command files in plugins
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Unused Commands"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

UNUSED_COUNT=0

# Scan for command files
find . -type f -path "*/commands/*.md" -not -path "*/node_modules/*" 2>/dev/null | while read -r cmd_file; do
  # Extract command name from filename
  # Format: plugin-name/commands/plugin-command.md -> plugin:command
  BASENAME=$(basename "$cmd_file" .md)

  # Try to extract command name from frontmatter
  CMD_NAME=$(grep -A 20 "^---$" "$cmd_file" | grep "^# /" | head -1 | sed 's/^# \///' || echo "")

  if [[ -z "$CMD_NAME" ]]; then
    # Fallback: derive from filename (e.g., analytics-report.md -> analytics:report)
    CMD_NAME=$(echo "$BASENAME" | sed 's/-/:/' | sed 's/-/:/')
  fi

  # Check if command has been used
  if ! echo "$USED" | grep -q "^${CMD_NAME}$"; then
    echo "  📝 /${CMD_NAME}"
    echo "     File: ${cmd_file}"
    echo ""
    UNUSED_COUNT=$((UNUSED_COUNT + 1))
  fi
done

if [[ $UNUSED_COUNT -eq 0 ]]; then
  echo "  All commands have been used! 🎉"
  echo ""
fi

# Find all skill files
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Unused Skills"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

UNUSED_SKILLS=0

find . -type f -path "*/skills/*/skill.md" -not -path "*/node_modules/*" 2>/dev/null | while read -r skill_file; do
  # Extract skill name from directory name
  SKILL_DIR=$(dirname "$skill_file")
  SKILL_NAME=$(basename "$SKILL_DIR")

  # Try to get skill name from frontmatter
  FRONTMATTER_NAME=$(grep -A 5 "^---$" "$skill_file" | grep "^name:" | head -1 | sed 's/^name: *//' || echo "")

  if [[ -n "$FRONTMATTER_NAME" ]]; then
    SKILL_NAME="$FRONTMATTER_NAME"
  fi

  # Check if skill has been used
  if ! echo "$USED" | grep -qi "$SKILL_NAME"; then
    echo "  🎯 ${SKILL_NAME}"
    echo "     File: ${skill_file}"
    echo ""
    UNUSED_SKILLS=$((UNUSED_SKILLS + 1))
  fi
done

if [[ $UNUSED_SKILLS -eq 0 ]]; then
  echo "  All skills have been used! 🎉"
  echo ""
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [[ $UNUSED_COUNT -eq 0 && $UNUSED_SKILLS -eq 0 ]]; then
  echo "✨ All commands and skills have been used at least once!"
else
  echo "💡 Consider:"
  echo "  • Trying out unused features to see if they're helpful"
  echo "  • Removing plugins you never use"
  echo "  • Sharing useful commands with your team"
fi

echo ""
```

## Post-actions

None.
