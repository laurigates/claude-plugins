#!/usr/bin/env bash
# Detect other Claude/agent processes working in the same repo clone.
#
# Combines five signals:
#   1. Baseline drift     — optional snapshot from a prior session
#   2. Session markers    — .git/.claude-session-<pid> files written by coworkers
#   3. Process scan       — other claude/node processes whose cwd is this repo
#   4. Taskwarrior claims — +ACTIVE tasks in this repo's project (best-effort)
#   5. Worktree leak      — untracked file in parent matches a path committed
#                           in a child worktree (issue #1319)
#
# Output is a block of KEY=value lines plus === SECTION === headers so the
# invoking skill can parse results without re-running git.
#
# Exit code: 0 always (diagnostic; the skill decides how to react).

set -uo pipefail

project_dir=""
baseline_status=""
baseline_stash=""
self_agent=""

while [ $# -gt 0 ]; do
  case "$1" in
    --project-dir) project_dir="$2"; shift 2 ;;
    --baseline-status) baseline_status="$2"; shift 2 ;;
    --baseline-stash) baseline_stash="$2"; shift 2 ;;
    --self-agent) self_agent="$2"; shift 2 ;;
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
tw_claim_drift=0
worktree_leak_drift=0

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
# Signal 4: taskwarrior +ACTIVE claims (best-effort)
# =========================================================================
echo "=== TASKWARRIOR_CLAIMS ==="

if command -v task >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  project="$(basename "$repo_root")"
  claims_json="$(task project:"$project" +ACTIVE export 2>/dev/null)"
  if [ -z "$claims_json" ]; then
    claims_json="[]"
  fi

  if [ "$claims_json" != "[]" ]; then
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      claim_agent="${line%%|*}"
      rest="${line#*|}"
      claim_id="${rest%%|*}"
      rest="${rest#*|}"
      claim_branch="${rest%%|*}"
      rest="${rest#*|}"
      claim_host="${rest%%|*}"
      rest="${rest#*|}"
      claim_pid="${rest%%|*}"
      rest="${rest#*|}"
      claim_start="$rest"

      if [ -n "$self_agent" ] && [ "$claim_agent" = "$self_agent" ]; then
        echo "OWN_CLAIM_TASK=$claim_id"
        echo "OWN_CLAIM_AGENT=$claim_agent"
        continue
      fi

      tw_claim_drift=$((tw_claim_drift + 1))
      echo "TW_CLAIM_TASK=$claim_id"
      echo "TW_CLAIM_AGENT=$claim_agent"
      echo "TW_CLAIM_BRANCH=$claim_branch"
      echo "TW_CLAIM_HOST=$claim_host"
      echo "TW_CLAIM_PID=$claim_pid"
      echo "TW_CLAIM_START=$claim_start"
    done < <(printf '%s' "$claims_json" | jq -r '.[] | "\(.agent // "")|\(.id)|\(.branch // "")|\(.host // "")|\(.pid // "")|\(.start // "")"')
  fi

  echo "TW_PROJECT=$project"
  echo "TW_CLAIM_COUNT=$tw_claim_drift"
  echo "TW_SCAN_METHOD=task"
else
  echo "TW_SCAN_METHOD=unavailable"
fi

# =========================================================================
# Signal 5: worktree leak — issue #1319
# =========================================================================
# `Agent(isolation: "worktree")` can briefly leak a file the child wrote in
# its worktree into the parent checkout at the same relative path. The orphan
# vanishes once the child commits, but a naive `git status` response in the
# parent would treat the file as user content and stash, restore, or commit
# it onto the wrong branch.
#
# Detection: for every untracked file in the parent, walk the list of linked
# worktrees and check whether the same relative path exists there (either as
# a working-tree file or as a path mentioned in HEAD). When both sides hold
# the path, the parent's copy is almost certainly a transient leak — leave
# it alone and let the child's commit resolve it.
echo "=== WORKTREE_LEAK_CHECK ==="

worktree_paths=()
while IFS= read -r wt_line; do
  case "$wt_line" in
    worktree\ *)
      wt_path="${wt_line#worktree }"
      # Skip the parent itself; we only care about linked worktrees.
      if [ "$wt_path" != "$repo_root" ]; then
        worktree_paths+=("$wt_path")
      fi
      ;;
  esac
done < <(git worktree list --porcelain 2>/dev/null)

echo "LINKED_WORKTREE_COUNT=${#worktree_paths[@]}"

if [ "${#worktree_paths[@]}" -gt 0 ]; then
  # `git status --porcelain` "?? path" lines list untracked files. Iterate
  # over them and probe each linked worktree.
  while IFS= read -r untracked_line; do
    case "$untracked_line" in
      "?? "*)
        rel_path="${untracked_line#?? }"
        # Strip surrounding quotes that git emits when the path contains spaces.
        case "$rel_path" in
          \"*\")
            rel_path="${rel_path#\"}"
            rel_path="${rel_path%\"}"
            ;;
        esac
        for wt in "${worktree_paths[@]}"; do
          # `.claude/worktrees/agent-*` is the harness's canonical layout, but
          # any linked worktree counts — the leak shape doesn't depend on it.
          hit=""
          if [ -e "$wt/$rel_path" ]; then
            hit="working_tree"
          elif git -C "$wt" cat-file -e "HEAD:$rel_path" 2>/dev/null; then
            hit="head_commit"
          fi
          if [ -n "$hit" ]; then
            worktree_leak_drift=$((worktree_leak_drift + 1))
            echo "WORKTREE_LEAK_PATH=$rel_path"
            echo "WORKTREE_LEAK_WORKTREE=$wt"
            echo "WORKTREE_LEAK_MATCH=$hit"
            break
          fi
        done
        ;;
    esac
  done < <(git status --porcelain --untracked-files=all 2>/dev/null)
fi

echo "WORKTREE_LEAK_COUNT=$worktree_leak_drift"

# =========================================================================
# Summary verdict
# =========================================================================
echo "=== VERDICT ==="

if [ "$marker_drift" -gt 0 ] || [ "$proc_drift" -gt 0 ] || [ "$tw_claim_drift" -gt 0 ]; then
  verdict="coworker_detected"
elif [ "$worktree_leak_drift" -gt 0 ]; then
  # A worktree leak (issue #1319) means the orchestrator must not clean the
  # untracked file even though no foreground coworker is visible — the child
  # agent's commit will reclaim it.
  verdict="worktree_leak_suspected"
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
echo "TW_CLAIM_COUNT=$tw_claim_drift"
echo "WORKTREE_LEAK_COUNT=$worktree_leak_drift"
