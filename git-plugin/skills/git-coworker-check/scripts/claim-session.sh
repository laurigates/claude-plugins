#!/usr/bin/env bash
# Write a session marker and capture a baseline snapshot so this session can
# later distinguish its own changes from a coworker's.
#
# Marker path: <git-dir>/.claude-session-<pid>
# Baseline:    <git-dir>/.claude-baseline-<pid>.status
#              <git-dir>/.claude-baseline-<pid>.stash
#
# The caller is responsible for deleting these on exit (or trusting the
# `kill -0` stale-marker sweep in detect-coworkers.sh).

set -uo pipefail

project_dir=""
pid_override=""

while [ $# -gt 0 ]; do
  case "$1" in
    --project-dir) project_dir="$2"; shift 2 ;;
    --pid) pid_override="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$project_dir" ]; then
  project_dir="$(pwd)"
fi

cd "$project_dir" || exit 1

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "NOT_A_REPO=true"
  exit 0
fi

git_dir="$(git rev-parse --git-dir)"
pid="${pid_override:-$$}"

marker="$git_dir/.claude-session-$pid"
baseline_status="$git_dir/.claude-baseline-$pid.status"
baseline_stash="$git_dir/.claude-baseline-$pid.stash"

printf 'pid=%s\nstarted=%s\nhost=%s\ncwd=%s\n' \
  "$pid" "$(date -Iseconds)" "$(hostname)" "$project_dir" > "$marker"

git status --porcelain=v2 --branch > "$baseline_status" 2>/dev/null || true
git stash list > "$baseline_stash" 2>/dev/null || true

echo "MARKER=$marker"
echo "BASELINE_STATUS=$baseline_status"
echo "BASELINE_STASH=$baseline_stash"
