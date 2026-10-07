#!/usr/bin/env bash
# shellcheck disable=SC2034  # sets CLEANUP_PERIOD_* for the sourcing script
# Shared helper: resolve the effective `cleanupPeriodDays` retention setting.
#
# Sourced by check-runtime.sh and check-usage.sh. Precedence follows the
# settings merge order for scalar keys (highest wins):
#   <project>/.claude/settings.local.json > <project>/.claude/settings.json
#   > <home>/.claude/settings.json > default 30
# Managed settings are not read: their location is platform-specific and a
# managed value is reported by `/status`, not inferable from user files.
#
# Usage: resolve_cleanup_period <home_dir> <project_dir>
# Sets: CLEANUP_PERIOD_RAW     raw JSON value (e.g. 30, 0, "thirty")
#       CLEANUP_PERIOD_SOURCE  default|user|project|local
#       CLEANUP_PERIOD_VALID   true|false (whole number >= 1)
#       CLEANUP_PERIOD_DAYS    effective days (falls back to 30 when invalid)

resolve_cleanup_period() {
  local home="$1" project="$2" f src raw
  CLEANUP_PERIOD_RAW="30"
  CLEANUP_PERIOD_SOURCE="default"
  for pair in \
    "user:${home}/.claude/settings.json" \
    "project:${project}/.claude/settings.json" \
    "local:${project}/.claude/settings.local.json"; do
    src="${pair%%:*}"
    f="${pair#*:}"
    [ -f "$f" ] || continue
    raw=$(jq -c 'if type == "object" and has("cleanupPeriodDays") then .cleanupPeriodDays else empty end' "$f" 2>/dev/null) || continue
    [ -n "$raw" ] || continue
    CLEANUP_PERIOD_RAW="$raw"
    CLEANUP_PERIOD_SOURCE="$src"
  done

  if [[ "$CLEANUP_PERIOD_RAW" =~ ^[0-9]+$ ]] && [ "$CLEANUP_PERIOD_RAW" -ge 1 ]; then
    CLEANUP_PERIOD_VALID=true
    CLEANUP_PERIOD_DAYS="$CLEANUP_PERIOD_RAW"
  else
    CLEANUP_PERIOD_VALID=false
    CLEANUP_PERIOD_DAYS=30
  fi
}
