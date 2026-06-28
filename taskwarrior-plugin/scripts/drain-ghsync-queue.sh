#!/usr/bin/env bash
# drain-ghsync-queue.sh — drain the on-exit GitHub-sync queue (issue #1810).
#
# The on-exit-taskwarrior-plugin native hook appends the UUID of every touched
# task carrying a GitHub linkage UDA (`ghid`/`ghpr`) to a queue file under the
# taskwarrior data dir. This script drains that queue in one batched pass:
#
#   1. Read + dedup the queued UUIDs (filtering to UUID-shaped tokens, so a
#      stale/corrupt queue is handled gracefully — its own failure mode).
#   2. Resolve them to their projects in ONE batched `task <uuids> export` call.
#   3. Invalidate the drift-probe TTL cache (`<cache-dir>/<proj>.stale`) for each
#      affected project, so the very next stale-check re-polls them in one
#      batched `gh` pass instead of waiting out the TTL.
#   4. Clear the queue (always — even on a no-op / corrupt queue).
#
# It performs NO network I/O itself: the batched `gh` poll is reconcile.sh's job,
# triggered by the cache it busts here. That keeps the drain deterministic and
# cheap. Fails open: any missing tool / unreadable queue → STATUS=OK, DRAINED=0.
#
# Output: structured KEY=VALUE block (see .claude/rules/structured-script-output.md).
#
# Flags / env:
#   --queue <file>      queue path     (env CLAUDE_TASKWARRIOR_GHSYNC_QUEUE)
#   --cache-dir <dir>   drift cache    (env CLAUDE_TASKWARRIOR_DRIFT_CACHE_DIR)

set -uo pipefail

queue_file="${CLAUDE_TASKWARRIOR_GHSYNC_QUEUE:-}"
cache_dir="${CLAUDE_TASKWARRIOR_DRIFT_CACHE_DIR:-${TMPDIR:-/tmp}/claude-taskwarrior-drift}"

while [ $# -gt 0 ]; do
  case "$1" in
    --queue) shift; queue_file="${1:-}" ;;
    --queue=*) queue_file="${1#*=}" ;;
    --cache-dir) shift; cache_dir="${1:-}" ;;
    --cache-dir=*) cache_dir="${1#*=}" ;;
    *) ;;
  esac
  shift
done

echo "=== TASKWARRIOR GHSYNC DRAIN ==="

# Resolve the default queue path from taskwarrior's data dir when not overridden.
if [ -z "$queue_file" ]; then
  data_loc=$(task _get rc.data.location 2>/dev/null || true)
  case "$data_loc" in
    "~"/*) data_loc="${HOME}/${data_loc#~/}" ;;
    "~") data_loc="${HOME}" ;;
  esac
  [ -z "$data_loc" ] && data_loc="${HOME}/.task"
  queue_file="${data_loc}/claude-plugin-ghsync.queue"
fi
echo "QUEUE_FILE=${queue_file}"

if [ ! -s "$queue_file" ]; then
  echo "QUEUED_UUIDS=0"
  echo "AFFECTED_PROJECTS="
  echo "CACHE_INVALIDATED=0"
  echo "DRAINED=0"
  echo "STATUS=OK"
  echo "ISSUE_COUNT=0"
  echo "=== END TASKWARRIOR GHSYNC DRAIN ==="
  exit 0
fi

# 1. Read + dedup UUID-shaped tokens (8-4-4-4-12 hex). A corrupt line is dropped.
uuids=()
while IFS= read -r raw; do
  tok="${raw//[$'\t\r ']/}"
  case "$tok" in
    [0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]-[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]-[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]-[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]-[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]) ;;
    *) continue ;;
  esac
  # dedup
  already="no"
  for u in "${uuids[@]:-}"; do [ "$u" = "$tok" ] && already="yes" && break; done
  [ "$already" = "no" ] && uuids+=("$tok")
done < "$queue_file"

echo "QUEUED_UUIDS=${#uuids[@]}"

# 2. Resolve UUIDs → projects in ONE batched `task export`. Fail open if task/jq
#    is unavailable: clear the queue but invalidate nothing (no project data).
projects=()
have_empty_project="no"
if [ "${#uuids[@]}" -gt 0 ] && command -v task >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  export_json=$(task "${uuids[@]}" export 2>/dev/null || true)
  if [ -n "$export_json" ]; then
    while IFS= read -r proj; do
      if [ -z "$proj" ]; then have_empty_project="yes"; continue; fi
      already="no"
      for p in "${projects[@]:-}"; do [ "$p" = "$proj" ] && already="yes" && break; done
      [ "$already" = "no" ] && projects+=("$proj")
    done < <(printf '%s' "$export_json" | jq -r '.[].project // ""' 2>/dev/null || true)
  fi
fi

# 3. Invalidate the drift TTL cache for each affected project. The proj_key
#    sanitization MUST match taskwarrior-drift-probe.sh so the right cache busts.
invalidated=0
bust_cache() { # bust_cache <proj-or-empty>
  local key
  key=$(printf '%s' "${1:-_all}" | tr -cd 'a-zA-Z0-9_-')
  [ -n "$key" ] || key="_all"
  local cf="${cache_dir}/${key}.stale"
  if [ -e "$cf" ]; then
    rm -f "$cf" 2>/dev/null && invalidated=$((invalidated + 1))
  fi
}
for p in "${projects[@]:-}"; do [ -n "$p" ] && bust_cache "$p"; done
[ "$have_empty_project" = "yes" ] && bust_cache ""

# Report affected projects (comma-separated; empty-project shown as _all).
proj_label=""
for p in "${projects[@]:-}"; do [ -n "$p" ] && proj_label="${proj_label:+$proj_label,}$p"; done
[ "$have_empty_project" = "yes" ] && proj_label="${proj_label:+$proj_label,}_all"
echo "AFFECTED_PROJECTS=${proj_label}"
echo "CACHE_INVALIDATED=${invalidated}"

# 4. Clear the queue (always — drained, even if resolution found nothing).
: > "$queue_file" 2>/dev/null || true

echo "DRAINED=${#uuids[@]}"
echo "STATUS=OK"
echo "ISSUE_COUNT=0"
echo "=== END TASKWARRIOR GHSYNC DRAIN ==="
exit 0
