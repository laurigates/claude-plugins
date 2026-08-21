#!/usr/bin/env bash
# Guard against actionlint version skew between the repo's two enforcement
# surfaces.
#
# Workflow linting is enforced twice: locally by the rhysd/actionlint hook in
# .pre-commit-config.yaml (`rev: vX.Y.Z`), and in CI by
# `go install github.com/rhysd/actionlint/cmd/actionlint@vX.Y.Z` in
# .github/workflows/plugin-pr-checks.yml. Today the only thing holding them
# together is a comment that says "Keep in sync with the actionlint CI step in
# plugin-pr-checks.yml".
#
# A comment is not a guard. When the two drift, CI rejects a workflow the local
# hook just approved (actionlint adds checks between releases), and the failure
# reads as a mystery because pre-commit passed. This is the exact failure mode
# that already earned **ruff** a dedicated guard here
# (scripts/check-ruff-version-sync.sh) — actionlint is the same shape and had
# no equivalent.
#
# Two zero-false-positive checks:
#
#   1. CI PINNED — every actionlint install in the workflow pins an explicit
#      version (`@vX.Y.Z`). An `@latest` or bare install silently tracks HEAD.
#   2. VERSIONS AGREE — the actionlint pre-commit `rev:` matches every CI pin.
#
# Emits the structured KEY=value / STATUS= convention
# (.claude/rules/structured-script-output.md).
#
# Usage:
#   check-actionlint-version-sync.sh [--project-dir <path>] [--strict]
#
#   --project-dir   Repo root to audit (default: git toplevel, else cwd)
#   --strict        Exit 1 when skew is found (default: always exit 0)
set -uo pipefail

proj_dir=""
strict=false

while [ $# -gt 0 ]; do
  case "$1" in
    --project-dir)
      if [ -z "${2:-}" ] || [ ! -d "${2:-}" ]; then
        echo "check-actionlint-version-sync.sh: --project-dir requires a directory" >&2
        exit 2
      fi
      proj_dir="$2"; shift 2 ;;
    --strict) strict=true; shift ;;
    -h|--help)
      echo "Usage: check-actionlint-version-sync.sh [--project-dir DIR] [--strict]" >&2
      exit 0 ;;
    *)
      echo "check-actionlint-version-sync.sh: unknown argument: $1" >&2
      exit 2 ;;
  esac
done

if [ -z "$proj_dir" ]; then
  proj_dir="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

precommit_config="$proj_dir/.pre-commit-config.yaml"
workflow_dir="$proj_dir/.github/workflows"

issue_count=0
declare -a issues=()

add_issue() {
  issues+=("  - SEVERITY=$1 TYPE=$2 MSG=$3")
  issue_count=$((issue_count + 1))
}

# --- pre-commit rev ----------------------------------------------------------
# The `rev:` belonging to the rhysd/actionlint repo block: the first rev that
# follows that repo URL. Mirrors the awk approach in check-ruff-version-sync.sh.
precommit_rev=""
if [ -f "$precommit_config" ]; then
  precommit_rev="$(awk '
    /rhysd\/actionlint/ { found = 1; next }
    found && /^[[:space:]]*rev:/ {
      sub(/^[[:space:]]*rev:[[:space:]]*/, "")
      gsub(/[[:space:]]*(#.*)?$/, "")
      print
      exit
    }
  ' "$precommit_config")"
fi

# --- CI pins -----------------------------------------------------------------
# Every actionlint install across the workflow fleet, not just plugin-pr-checks:
# a second workflow installing it at a different version is the same defect.
declare -a ci_pins=()
declare -a ci_unpinned=()

if [ -d "$workflow_dir" ]; then
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    file="${line%%:*}"
    rest="${line#*:}"
    rel="${file#"$proj_dir"/}"
    # Pinned form: .../actionlint@vX.Y.Z  (also accept a bare X.Y.Z)
    if printf '%s' "$rest" | grep -qE 'actionlint[^[:space:]]*@v?[0-9]+\.[0-9]+\.[0-9]+'; then
      pin="$(printf '%s' "$rest" | grep -oE 'actionlint[^[:space:]]*@v?[0-9]+\.[0-9]+\.[0-9]+' | grep -oE 'v?[0-9]+\.[0-9]+\.[0-9]+$' | head -1)"
      # Normalise to a leading `v` so `v1.7.12` and `1.7.12` compare equal.
      case "$pin" in v*) : ;; *) pin="v$pin" ;; esac
      ci_pins+=("$rel=$pin")
    else
      ci_unpinned+=("$rel")
    fi
  done < <(grep -rnE 'go install[[:space:]]+github\.com/rhysd/actionlint' "$workflow_dir" 2>/dev/null || true)
fi

# --- Check 1: CI pinned ------------------------------------------------------
for rel in ${ci_unpinned[@]+"${ci_unpinned[@]}"}; do
  add_issue ERROR unpinned_ci_actionlint \
    "$rel installs actionlint without an explicit @vX.Y.Z pin - it silently tracks HEAD"
done

# --- Check 2: versions agree -------------------------------------------------
if [ -n "$precommit_rev" ]; then
  for entry in ${ci_pins[@]+"${ci_pins[@]}"}; do
    rel="${entry%%=*}"
    pin="${entry##*=}"
    if [ "$pin" != "$precommit_rev" ]; then
      add_issue ERROR actionlint_version_skew \
        "$rel pins actionlint $pin but .pre-commit-config.yaml rev is $precommit_rev"
    fi
  done
elif [ "${#ci_pins[@]}" -gt 0 ]; then
  add_issue WARN missing_precommit_rev \
    ".pre-commit-config.yaml has no rhysd/actionlint rev to compare the $(echo "${#ci_pins[@]}") CI pin(s) against"
fi

# --- Report ------------------------------------------------------------------
echo "=== ACTIONLINT VERSION SYNC ==="
echo "PRECOMMIT_REV=${precommit_rev:-none}"
echo "CI_PIN_COUNT=${#ci_pins[@]}"
echo "CI_UNPINNED_COUNT=${#ci_unpinned[@]}"
for entry in ${ci_pins[@]+"${ci_pins[@]}"}; do
  echo "CI_PIN=${entry%%=*} VERSION=${entry##*=}"
done
# Guard integrity: a checker that found no install sites would also print OK.
if [ "${#ci_pins[@]}" -eq 0 ] && [ "${#ci_unpinned[@]}" -eq 0 ]; then
  echo "SCANNED_EMPTY=true"
else
  echo "SCANNED_EMPTY=false"
fi
echo "ISSUE_COUNT=$issue_count"

if [ "$issue_count" -gt 0 ]; then
  echo "ISSUES:"
  printf '%s\n' "${issues[@]}"
  echo "STATUS=FAIL"
  echo "=== END ACTIONLINT VERSION SYNC ==="
  [ "$strict" = true ] && exit 1
  exit 0
fi

echo "STATUS=OK"
echo "=== END ACTIONLINT VERSION SYNC ==="
exit 0
