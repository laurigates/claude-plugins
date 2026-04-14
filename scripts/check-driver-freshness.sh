#!/usr/bin/env bash
# check-driver-freshness.sh
# Verify that the /configure:repo driver skill is not out of sync with its dependencies.
#
# Checks:
#   1. For each dependency SKILL.md, compare its `modified:` date to the driver's `reviewed:` date.
#      Exits non-zero if any dependency is newer than the driver's last review.
#   2. Exits non-zero if the driver's `reviewed:` date is older than 90 days (staleness check).
#
# Usage:
#   ./scripts/check-driver-freshness.sh [--driver <path>] [--max-age-days <N>]
#
# Exit codes:
#   0 - Driver is fresh
#   1 - Driver is stale (dependency newer than reviewed: date, or reviewed: >N days old)

set -uo pipefail

# Change to repository root
cd "$(dirname "$0")/.." || exit 1

# Defaults
DRIVER_PATH="configure-plugin/skills/configure-repo/SKILL.md"
MAX_AGE_DAYS=90
VERBOSE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --driver)
      DRIVER_PATH="$2"
      shift 2
      ;;
    --max-age-days)
      MAX_AGE_DAYS="$2"
      shift 2
      ;;
    --verbose|-v)
      VERBOSE=true
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "Usage: $0 [--driver <path>] [--max-age-days <N>] [--verbose]" >&2
      exit 1
      ;;
  esac
done

# ── Helpers ─────────────────────────────────────────────────────────────────

extract_date_field() {
  local skill_file="$1"
  local field_name="$2"
  head -20 "$skill_file" | grep -m1 "^${field_name}:" | sed 's/^[^:]*:[[:space:]]*//' | tr -d '\r '
}

# Cross-platform date → epoch seconds
date_to_epoch() {
  local date_str="$1"
  if date -j -f "%Y-%m-%d" "$date_str" "+%s" >/dev/null 2>&1; then
    date -j -f "%Y-%m-%d" "$date_str" "+%s"
  elif date -d "$date_str" "+%s" >/dev/null 2>&1; then
    date -d "$date_str" "+%s"
  else
    echo "0"
  fi
}

today_epoch() {
  if date -j "+%s" >/dev/null 2>&1; then
    date -j "+%s"
  else
    date "+%s"
  fi
}

log() {
  echo "$@"
}

verbose() {
  if $VERBOSE; then
    echo "  $*"
  fi
}

# ── Validate driver exists ───────────────────────────────────────────────────

if [ ! -f "$DRIVER_PATH" ]; then
  echo "ERROR: Driver skill not found: $DRIVER_PATH" >&2
  exit 1
fi

# ── Extract driver reviewed: date ─────────────────────────────────────────────

driver_reviewed=$(extract_date_field "$DRIVER_PATH" "reviewed")

if [ -z "$driver_reviewed" ]; then
  echo "ERROR: Driver skill has no 'reviewed:' date in frontmatter: $DRIVER_PATH" >&2
  exit 1
fi

verbose "Driver: $DRIVER_PATH"
verbose "Driver reviewed: $driver_reviewed"

driver_epoch=$(date_to_epoch "$driver_reviewed")

if [ "$driver_epoch" = "0" ]; then
  echo "ERROR: Could not parse driver reviewed date: $driver_reviewed" >&2
  exit 1
fi

# ── Parse dependency skill paths from driver ──────────────────────────────────

# Extract paths from the Dependencies table in the SKILL.md
# Looks for lines like: | `/configure:claude-plugins` | `configure-plugin/skills/configure-claude-plugins/SKILL.md` |
dependency_paths=()
while IFS= read -r dep_path; do
  if [ -n "$dep_path" ] && [ -f "$dep_path" ]; then
    dependency_paths+=("$dep_path")
  elif [ -n "$dep_path" ]; then
    verbose "WARNING: Dependency not found: $dep_path"
  fi
done < <(grep -oE '[a-z][a-z0-9-]+/skills/[a-z0-9-]+/SKILL\.md' "$DRIVER_PATH" | sort -u)

# ── Check each dependency ────────────────────────────────────────────────────

failed=false
stale_deps=()

for dep_file in "${dependency_paths[@]}"; do
  dep_modified=$(extract_date_field "$dep_file" "modified")

  if [ -z "$dep_modified" ]; then
    verbose "SKIP: $dep_file has no 'modified:' date"
    continue
  fi

  dep_epoch=$(date_to_epoch "$dep_modified")

  if [ "$dep_epoch" = "0" ]; then
    verbose "SKIP: Could not parse modified date '$dep_modified' for $dep_file"
    continue
  fi

  verbose "Checking: $dep_file  modified=$dep_modified  driver-reviewed=$driver_reviewed"

  if [ "$dep_epoch" -gt "$driver_epoch" ]; then
    stale_deps+=("$dep_file (modified: $dep_modified, driver reviewed: $driver_reviewed)")
    failed=true
  fi
done

# ── Check driver age (>MAX_AGE_DAYS) ──────────────────────────────────────────

now_epoch=$(today_epoch)
age_seconds=$(( now_epoch - driver_epoch ))
age_days=$(( age_seconds / 86400 ))

verbose "Driver age: ${age_days} days (max: ${MAX_AGE_DAYS})"

driver_age_stale=false
if [ "$age_days" -gt "$MAX_AGE_DAYS" ]; then
  driver_age_stale=true
  failed=true
fi

# ── Report ───────────────────────────────────────────────────────────────────

log ""
log "Driver Freshness Check"
log "======================"
log "Driver:    $DRIVER_PATH"
log "Reviewed:  $driver_reviewed  (${age_days} days ago)"
log "Max age:   ${MAX_AGE_DAYS} days"
log ""

if [ ${#stale_deps[@]} -gt 0 ]; then
  log "FAIL: ${#stale_deps[@]} dependency(ies) newer than driver's reviewed: date:"
  for dep in "${stale_deps[@]}"; do
    log "  - $dep"
  done
  log ""
  log "Update the driver skill, bump its 'reviewed:' date, and document any"
  log "behaviour changes from the updated dependency."
fi

if $driver_age_stale; then
  log "FAIL: Driver reviewed: date is ${age_days} days old (>${MAX_AGE_DAYS} days)."
  log "  Even if no dependencies changed, the driver should be re-reviewed"
  log "  quarterly to catch upstream claude-code behaviour changes."
fi

if ! $failed; then
  log "OK: Driver is fresh."
  log "  All ${#dependency_paths[@]} dependencies are older than or equal to the driver's reviewed: date."
  log "  Driver age: ${age_days} days (within ${MAX_AGE_DAYS}-day threshold)."
fi

log ""

$failed && exit 1 || exit 0
