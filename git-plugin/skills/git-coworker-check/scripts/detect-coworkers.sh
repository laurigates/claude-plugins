#!/usr/bin/env bash
# Detect other Claude/agent processes working in the same repo clone.
#
# Combines three signals:
#   1. Baseline drift  — optional snapshot from a prior session
#   2. Session markers — .git/.claude-session-<pid> files written by coworkers
#   3. Process scan    — other claude/node processes whose cwd is this repo
#
# Output is a block of KEY=value lines plus === SECTION === headers so the
# invoking skill can parse results without re-running git.
#
# Exit code: 0 always (diagnostic; the skill decides how to react).

set -uo pipefail

project_dir=""
baseline_status=""
baseline_stash=""

while [ $# -gt 0 ]; do
  case "$1" in
    --project-dir) project_dir="$2"; shift 2 ;;
    --baseline-status) baseline_status="$2"; shift 2 ;;
    --baseline-stash) baseline_stash="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$project_dir" ]; then
  project_dir="$(pwd)"
fi

cd "$project_dir" || exit 0

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "NOT_A_REPO=true"
  exit 0
fi

repo_root="$(git rev-parse --show-toplevel)"
git_dir="$(git rev-parse --git-dir)"
self_pid="$$"

# Build an exclusion set of ancestor PIDs — the Claude process that invoked
# this script is not a "coworker". Read PPid from /proc/<pid>/status.
ancestors=" $self_pid "
if [ -d /proc ]; then
  cur="$self_pid"
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    status_file="/proc/$cur/status"
    [ -r "$status_file" ] || break
    ppid="$(awk '/^PPid:/ {print $2; exit}' "$status_file")"
    case "$ppid" in ''|0|1) break ;; esac
    ancestors="$ancestors$ppid "
    cur="$ppid"
  done
fi

echo "REPO_ROOT=$repo_root"
echo "SELF_PID=$self_pid"
echo "HOSTNAME=$(hostname)"
echo "TIMESTAMP=$(date -Iseconds)"

status_drift="unknown"
stash_drift="unknown"
marker_drift=0
proc_drift=0

# =========================================================================
# Signal 1: baseline drift
# =========================================================================
echo "=== BASELINE_DRIFT ==="

current_status="$(git status --porcelain=v2 --branch 2>/dev/null || true)"
current_stash="$(git stash list 2>/dev/null || true)"

if [ -n "$baseline_status" ] && [ -f "$baseline_status" ]; then
  new_status_lines="$(diff <(cat "$baseline_status") <(printf '%s' "$current_status") | awk '/^> / {sub(/^> /,""); print}')"
  if [ -n "$new_status_lines" ]; then
    status_drift="true"
    echo "DRIFT_FILES=true"
    echo "=== NEW_STATUS_LINES ==="
    printf '%s\n' "$new_status_lines"
    echo "=== END_NEW_STATUS_LINES ==="
  else
    status_drift="false"
    echo "DRIFT_FILES=false"
  fi
else
  echo "DRIFT_FILES=unknown"
  echo "DRIFT_FILES_REASON=no baseline snapshot provided"
fi

if [ -n "$baseline_stash" ] && [ -f "$baseline_stash" ]; then
  new_stash_lines="$(diff <(cat "$baseline_stash") <(printf '%s' "$current_stash") | awk '/^> / {sub(/^> /,""); print}')"
  if [ -n "$new_stash_lines" ]; then
    stash_drift="true"
    echo "DRIFT_STASH=true"
    echo "=== NEW_STASH_LINES ==="
    printf '%s\n' "$new_stash_lines"
    echo "=== END_NEW_STASH_LINES ==="
  else
    stash_drift="false"
    echo "DRIFT_STASH=false"
  fi
else
  echo "DRIFT_STASH=unknown"
fi

# =========================================================================
# Signal 2: session markers
# =========================================================================
echo "=== SESSION_MARKERS ==="

for marker in "$git_dir"/.claude-session-*; do
  [ -e "$marker" ] || continue
  marker_pid="${marker##*.claude-session-}"
  case "$marker_pid" in *[!0-9]*) continue ;; esac
  if [ "$marker_pid" = "$self_pid" ]; then
    continue
  fi
  if kill -0 "$marker_pid" 2>/dev/null; then
    marker_drift=$((marker_drift + 1))
    echo "MARKER_PID=$marker_pid"
    echo "MARKER_FILE=$marker"
    echo "MARKER_CONTENTS=$(tr '\n' '|' < "$marker")"
  else
    echo "STALE_MARKER=$marker"
  fi
done
echo "OTHER_MARKER_COUNT=$marker_drift"

# =========================================================================
# Signal 3: process scan (best-effort)
# =========================================================================
echo "=== PROCESS_SCAN ==="

if [ -d /proc ]; then
  for pid_dir in /proc/[0-9]*; do
    pid="${pid_dir##*/}"
    case "$ancestors" in *" $pid "*) continue ;; esac
    cwd="$(readlink "$pid_dir/cwd" 2>/dev/null)" || continue
    case "$cwd" in
      "$repo_root"|"$repo_root"/*)
        comm="$(cat "$pid_dir/comm" 2>/dev/null | tr -d '\n' | head -c 80)"
        case "$comm" in
          claude|node|Claude|"claude code"|claude-code)
            proc_drift=$((proc_drift + 1))
            echo "PROC_PID=$pid"
            echo "PROC_COMM=$comm"
            echo "PROC_CWD=$cwd"
            ;;
        esac
        ;;
    esac
  done
  echo "PROC_SCAN_METHOD=proc"
  echo "ANCESTORS_EXCLUDED=$ancestors"
elif command -v lsof >/dev/null 2>&1; then
  lsof_out="$(lsof -a -d cwd -c claude -c node -Fpn 2>/dev/null || true)"
  pid=""
  while IFS= read -r line; do
    case "$line" in
      p*) pid="${line#p}" ;;
      n*)
        path="${line#n}"
        case "$path" in
          "$repo_root"|"$repo_root"/*)
            if [ -n "$pid" ] && [ "$pid" != "$self_pid" ]; then
              proc_drift=$((proc_drift + 1))
              echo "PROC_PID=$pid"
              echo "PROC_CWD=$path"
            fi
            ;;
        esac
        ;;
    esac
  done <<< "$lsof_out"
  echo "PROC_SCAN_METHOD=lsof"
else
  echo "PROC_SCAN_METHOD=unavailable"
fi
echo "OTHER_PROC_COUNT=$proc_drift"

# =========================================================================
# Summary verdict
# =========================================================================
echo "=== VERDICT ==="

if [ "$marker_drift" -gt 0 ] || [ "$proc_drift" -gt 0 ]; then
  verdict="coworker_detected"
elif [ "$status_drift" = "true" ] || [ "$stash_drift" = "true" ]; then
  verdict="drift_detected"
else
  verdict="clear"
fi
echo "VERDICT=$verdict"
echo "STATUS_DRIFT=$status_drift"
echo "STASH_DRIFT=$stash_drift"
echo "MARKER_COUNT=$marker_drift"
echo "PROC_COUNT=$proc_drift"
