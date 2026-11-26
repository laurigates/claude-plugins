#!/usr/bin/env bash
# Probe-root housekeeping, called by the root justfile.
#   probes.sh run <slug> [--clip] [--no-notify]
#   probes.sh list
#   probes.sh archive [days]      (default 14; decided probes only)
#   probes.sh latest
set -uo pipefail

ROOT="${PROBES_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

probe_status() { # $1 probe dir -> STATUS code or "pending"
  local s="$1/results/summary.txt"
  if [ -f "$s" ]; then
    grep -m1 '^STATUS=' "$s" | sed 's/^STATUS=//; s/ .*//'
  else
    echo pending
  fi
}

probe_dirs() {
  find "$ROOT" -mindepth 1 -maxdepth 1 -type d -name '[0-9]*-*' | sort
}

cmd_run() {
  local slug="${1:-}"
  [ -n "$slug" ] || { echo "usage: probes.sh run <slug> [--clip] [--no-notify]" >&2; exit 1; }
  shift
  local dir
  dir=$(find "$ROOT" -mindepth 1 -maxdepth 1 -type d \( -name "$slug" -o -name "*-$slug" \) | sort | tail -1)
  [ -n "$dir" ] && [ -x "$dir/run.sh" ] || { echo "STATUS=ERROR no runnable probe matching '$slug' in $ROOT" >&2; exit 1; }
  local flag
  for flag in "$@"; do
    case "$flag" in
      --clip) export PROBE_CLIP=1 ;;
      --no-notify) export PROBE_NOTIFY=0 ;;
      *) echo "unknown flag: $flag" >&2; exit 1 ;;
    esac
  done
  export PROBE_DIR="$dir"
  (cd "$dir" && ./run.sh)
}

cmd_list() {
  printf '%-36s %-18s %-9s %s\n' PROBE STATUS AGE_DAYS REF
  local dir ref age now mtime
  now=$(date +%s)
  while IFS= read -r dir; do
    [ -n "$dir" ] || continue
    ref=""
    if [ -f "$dir/.handoff.json" ] && command -v jq >/dev/null 2>&1; then
      ref=$(jq -r '.ref // ""' "$dir/.handoff.json" 2>/dev/null)
    fi
    mtime=$(python3 -c 'import os,sys; print(int(os.stat(sys.argv[1]).st_mtime))' "$dir" 2>/dev/null || echo "$now")
    age=$(((now - mtime) / 86400))
    printf '%-36s %-18s %-9s %s\n' "$(basename "$dir")" "$(probe_status "$dir")" "$age" "$ref"
  done < <(probe_dirs)
}

cmd_latest() {
  local last
  last=$(probe_dirs | tail -1)
  [ -n "$last" ] && basename "$last"
  return 0
}

cmd_archive() {
  local days="${1:-14}" moved=0 dir
  mkdir -p "$ROOT/archive"
  while IFS= read -r dir; do
    [ -n "$dir" ] || continue
    [ -f "$dir/results/summary.txt" ] || continue
    case "$(probe_status "$dir")" in pending | INCONCLUSIVE | ERROR) continue ;; esac
    if [ -n "$(find "$dir/results/summary.txt" -mtime +"$days")" ]; then
      mv "$dir" "$ROOT/archive/" && moved=$((moved + 1))
    fi
  done < <(probe_dirs)
  echo "ARCHIVED=$moved"
}

case "${1:-}" in
  run) shift; cmd_run "$@" ;;
  list) cmd_list ;;
  latest) cmd_latest ;;
  archive) shift; cmd_archive "$@" ;;
  *) echo "usage: probes.sh run|list|latest|archive" >&2; exit 1 ;;
esac
