#!/usr/bin/env bash
# Remove session marker and baseline files for the given PID (default: $$).

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

cd "$project_dir" || exit 0

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  exit 0
fi

git_dir="$(git rev-parse --git-dir)"
pid="${pid_override:-$$}"

rm -f \
  "$git_dir/.claude-session-$pid" \
  "$git_dir/.claude-baseline-$pid.status" \
  "$git_dir/.claude-baseline-$pid.stash"
