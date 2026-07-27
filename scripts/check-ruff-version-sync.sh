#!/usr/bin/env bash
# Guard against ruff version skew between the repo's two enforcement surfaces.
#
# Python lint/format is enforced twice: locally by the ruff-pre-commit hooks in
# .pre-commit-config.yaml, and in CI by the `uvx ruff@<version>` steps in
# .github/workflows/plugin-pr-checks.yml. When the two pin different versions,
# CI rejects formatting that pre-commit just produced (ruff's formatter output
# changes between releases) and the failure reads as a mystery — the local hook
# passed. Two zero-false-positive checks keep them in lockstep:
#
#   1. CI PINNED — every `uvx ruff …` invocation pins an explicit version
#      (`uvx ruff@X.Y.Z`). An unpinned `uvx ruff` silently tracks latest.
#   2. VERSIONS AGREE — the ruff-pre-commit `rev: vX.Y.Z` matches every CI pin.
#
# Emits the structured KEY=value / STATUS= convention
# (.claude/rules/structured-script-output.md).
#
# Usage:
#   check-ruff-version-sync.sh [--project-dir <path>] [--strict]
#
#   --project-dir   Repo root to audit (default: git toplevel, else cwd)
#   --strict        Exit 1 when skew is found (default: always exit 0)
set -uo pipefail

proj_dir=""
strict=false

while [ $# -gt 0 ]; do
  case "$1" in
    --project-dir) proj_dir="$2"; shift 2 ;;
    --strict) strict=true; shift ;;
    *) shift ;;
  esac
done

if [ -z "$proj_dir" ]; then
  proj_dir="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

precommit_config="$proj_dir/.pre-commit-config.yaml"
workflow="$proj_dir/.github/workflows/plugin-pr-checks.yml"

issue_count=0
declare -a issues=()

add_issue() {
  # add_issue <severity> <type> <message>
  issues+=("  - SEVERITY=$1 TYPE=$2 MSG=$3")
  issue_count=$((issue_count + 1))
}

# --- pre-commit rev ---------------------------------------------------------
# The `rev:` line belonging to the ruff-pre-commit repo block: take the first
# rev that follows the repo URL.
precommit_rev=""
if [ -f "$precommit_config" ]; then
  precommit_rev="$(awk '
    /astral-sh\/ruff-pre-commit/ { found = 1; next }
    found && /^[[:space:]]*rev:/ {
      sub(/^[[:space:]]*rev:[[:space:]]*/, "")
      gsub(/[[:space:]"'"'"']/, "")
      print
      exit
    }
    found && /^[[:space:]]*-[[:space:]]*repo:/ { exit }
  ' "$precommit_config")"
fi
precommit_version="${precommit_rev#v}"

# --- CI pins ----------------------------------------------------------------
declare -a ci_pins=()
ci_unpinned=0
if [ -f "$workflow" ]; then
  while IFS= read -r invocation; do
    case "$invocation" in
      ruff@*) ci_pins+=("${invocation#ruff@}") ;;
      *) ci_unpinned=$((ci_unpinned + 1)) ;;
    esac
    # Comment lines are prose about the pins, not invocations — skip them.
  done < <(grep -v '^[[:space:]]*#' "$workflow" \
    | grep -oE 'uvx ruff(@[0-9][^[:space:]]*)?' | sed 's/^uvx //')
fi

# --- checks -----------------------------------------------------------------
if [ ! -f "$precommit_config" ]; then
  add_issue ERROR missing_precommit_config "$precommit_config not found"
elif [ -z "$precommit_version" ]; then
  add_issue ERROR missing_precommit_rev "no ruff-pre-commit rev: found in .pre-commit-config.yaml"
fi

if [ ! -f "$workflow" ]; then
  add_issue ERROR missing_workflow "$workflow not found"
elif [ "$ci_unpinned" -gt 0 ]; then
  add_issue ERROR unpinned_ci_ruff \
    "$ci_unpinned unpinned 'uvx ruff' invocation(s) in plugin-pr-checks.yml — pin as uvx ruff@${precommit_version:-X.Y.Z}"
elif [ "${#ci_pins[@]}" -eq 0 ]; then
  add_issue ERROR missing_ci_ruff "no 'uvx ruff@<version>' step found in plugin-pr-checks.yml"
fi

if [ -n "$precommit_version" ]; then
  for pin in ${ci_pins[@]+"${ci_pins[@]}"}; do
    if [ "$pin" != "$precommit_version" ]; then
      add_issue ERROR version_skew \
        "CI pins ruff@$pin but .pre-commit-config.yaml pins v$precommit_version — keep both in sync"
    fi
  done
fi

item_status=OK
[ "$issue_count" -gt 0 ] && item_status=ERROR

echo "=== RUFF VERSION SYNC ==="
echo "PRECOMMIT_REV=${precommit_rev:-none}"
echo "CI_PIN_COUNT=${#ci_pins[@]}"
echo "CI_PINS=$(printf '%s,' ${ci_pins[@]+"${ci_pins[@]}"} | sed 's/,$//')"
echo "CI_UNPINNED_COUNT=$ci_unpinned"
echo "STATUS=$item_status"
echo "ISSUE_COUNT=$issue_count"
if [ "$issue_count" -gt 0 ]; then
  echo "ISSUES:"
  printf '%s\n' "${issues[@]}"
fi
echo "=== END RUFF VERSION SYNC ==="

if [ "$strict" = true ] && [ "$issue_count" -gt 0 ]; then
  exit 1
fi
exit 0
