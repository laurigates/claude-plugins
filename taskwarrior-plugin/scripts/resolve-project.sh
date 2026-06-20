#!/usr/bin/env bash
# resolve-project.sh — single source of truth for the project-scope ladder.
#
# task-add / task-coordinate / task-status / task-reconcile all default to the
# current repo's project so an agent in repo A is not distracted by tasks from
# repos B and C. Before this script the resolution ladder was reimplemented in
# each skill; this consolidates it.
#
# Resolution order:
#   1. --project=<name>  → explicit override
#   2. --all             → no project (prints empty PROJECT=)
#   3. basename of git toplevel (run here where stderr/exit are tolerated)
#   4. basename of the cwd (no git repo)
#
# Run from the body of a skill, never a Context backtick — git probes write to
# stderr in a no-git cwd, which aborts a Context command (issue #1351).
#
# Flags:
#   --project=<name>    Explicit project override
#   --all               Emit empty PROJECT (cross-project scope)
#   --project-dir=<dir> Directory to resolve from (default: cwd)
#
# Output: structured KEY=VALUE block. PROJECT is empty for --all.
#
# Exit code: always 0 (resolution never fails — falls back to cwd basename).

set -uo pipefail

proj_override=""
proj_all=false
proj_dir="$PWD"

while [ $# -gt 0 ]; do
  case "$1" in
    --project=*) proj_override="${1#*=}" ;;
    --project) shift; proj_override="${1:-}" ;;
    --all) proj_all=true ;;
    --project-dir=*) proj_dir="${1#*=}" ;;
    --project-dir) shift; proj_dir="${1:-$PWD}" ;;
    *) ;;
  esac
  shift
done

echo "=== PROJECT SCOPE ==="

if [ "$proj_all" = true ]; then
  echo "PROJECT="
  echo "SOURCE=all"
  echo "STATUS=OK"
  echo "=== END PROJECT SCOPE ==="
  exit 0
fi

if [ -n "$proj_override" ]; then
  echo "PROJECT=${proj_override}"
  echo "SOURCE=override"
  echo "STATUS=OK"
  echo "=== END PROJECT SCOPE ==="
  exit 0
fi

proj_toplevel=""
proj_toplevel=$(git -C "$proj_dir" rev-parse --show-toplevel 2>/dev/null || true)

if [ -n "$proj_toplevel" ]; then
  echo "PROJECT=$(basename "$proj_toplevel")"
  echo "SOURCE=git-toplevel"
  echo "STATUS=OK"
  echo "=== END PROJECT SCOPE ==="
  exit 0
fi

echo "PROJECT=$(basename "$proj_dir")"
echo "SOURCE=cwd"
echo "STATUS=OK"
echo "=== END PROJECT SCOPE ==="
exit 0
