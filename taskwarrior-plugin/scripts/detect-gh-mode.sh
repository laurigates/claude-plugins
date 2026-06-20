#!/usr/bin/env bash
# detect-gh-mode.sh — single source of truth for GitHub-mode detection.
#
# GitHub mode (offer ghid/ghpr linkage, fold in PR status, reconcile against
# issues/PRs) is active only when the repo has a remote AND gh is authenticated.
# task-add / task-status / task-done / task-reconcile each made this same two-
# check probe; this consolidates it.
#
# Run from a skill body, never a Context backtick — `git remote get-url` writes
# to stderr in a remote-less repo, which aborts a Context command.
#
# Flags:
#   --project-dir=<dir>   Directory to probe (default: cwd)
#
# Output: structured KEY=VALUE block. GH_MODE=on only when both checks pass.
#
# Exit code: always 0 (probe result is in GH_MODE, not the exit code, so this
# stays parallel-safe in a Bash batch).

set -uo pipefail

gh_dir="$PWD"
while [ $# -gt 0 ]; do
  case "$1" in
    --project-dir=*) gh_dir="${1#*=}" ;;
    --project-dir) shift; gh_dir="${1:-$PWD}" ;;
    *) ;;
  esac
  shift
done

echo "=== GITHUB MODE ==="

gh_remote=""
gh_remote=$(git -C "$gh_dir" remote get-url origin 2>/dev/null || true)
if [ -n "$gh_remote" ]; then
  echo "REMOTE_PRESENT=true"
else
  echo "REMOTE_PRESENT=false"
fi

gh_auth=false
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  gh_auth=true
fi
echo "GH_AUTHENTICATED=${gh_auth}"

if [ -n "$gh_remote" ] && [ "$gh_auth" = true ]; then
  echo "GH_MODE=on"
else
  echo "GH_MODE=off"
fi
echo "STATUS=OK"
echo "=== END GITHUB MODE ==="
exit 0
