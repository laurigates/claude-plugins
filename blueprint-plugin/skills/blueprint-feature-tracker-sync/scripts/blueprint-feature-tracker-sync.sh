#!/usr/bin/env bash
# blueprint-feature-tracker-sync deterministic core
# Owns the mechanical part of a full sync: taskwarrior-sidecar marker
# detection, implementation-evidence backfill (file-existence + git-log
# commit dedupe), status inference via the fixed decision table WITH the
# never-downgrade guard, and the statistics rollup. The interactive
# discrepancy resolution (Step 5) and next-action prompt (Step 11) stay
# with the model.
#
# Usage: bash blueprint-feature-tracker-sync.sh --project-dir <path> [--home-dir <path>]
#
# Reads <project_dir>/docs/blueprint/feature-tracker.json. Implementation
# evidence (file existence + `git log` commit SHAs) is resolved against
# <project_dir>, which is the injectable seam: tests plant a tracker JSON +
# a tiny git repo and point --project-dir at it so the run is offline.
# The script WRITES the backfilled tracker back in place (mirrors the
# skill's Step 3b/Step 7 behaviour); pass --dry-run to skip the write.

set -uo pipefail

home_dir=""
project_dir=""
dry_run=false

while [ $# -gt 0 ]; do
  case "$1" in
    --home-dir) home_dir="$2"; shift 2 ;;
    --project-dir) project_dir="$2"; shift 2 ;;
    --dry-run) dry_run=true; shift ;;
    *) shift ;;
  esac
done

: "${home_dir:=$HOME}"
: "${project_dir:=$(pwd)}"

echo "=== FEATURE TRACKER SYNC ==="

sync_status="OK"
issue_count=0
issues_list=""

add_issue() {
  issues_list="${issues_list}  - SEVERITY=$1 TYPE=$2 $3\n"
  issue_count=$((issue_count + 1))
}

if ! command -v jq >/dev/null 2>&1; then
  echo "JQ_AVAILABLE=false"
  echo "STATUS=ERROR"
  echo "ISSUE_COUNT=1"
  echo "ISSUES:"
  echo "  - SEVERITY=ERROR TYPE=missing_tool MSG=jq is required but not installed"
  echo "=== END FEATURE TRACKER SYNC ==="
  exit 1
fi
echo "JQ_AVAILABLE=true"

# Step 0: taskwarrior sidecar marker detection (file-marker signal only —
# the live-taskwarrior-linkage signal stays in the skill's prose).
sidecar=false
if [ -f "${project_dir}/.claude/rules/task-tracking.md" ]; then
  sidecar=true
fi
echo "SIDECAR=${sidecar}"

tracker="${project_dir}/docs/blueprint/feature-tracker.json"
if [ ! -f "$tracker" ]; then
  echo "TRACKER_PRESENT=false"
  echo "STATUS=ERROR"
  echo "ISSUE_COUNT=1"
  echo "ISSUES:"
  echo "  - SEVERITY=ERROR TYPE=tracker_missing MSG=feature-tracker.json not found; run /blueprint:init"
  echo "=== END FEATURE TRACKER SYNC ==="
  exit 1
fi
if ! jq empty "$tracker" >/dev/null 2>&1; then
  echo "TRACKER_PRESENT=true"
  echo "STATUS=ERROR"
  echo "ISSUE_COUNT=1"
  echo "ISSUES:"
  echo "  - SEVERITY=ERROR TYPE=invalid_json MSG=feature-tracker.json is not valid JSON"
  echo "=== END FEATURE TRACKER SYNC ==="
  exit 1
fi
echo "TRACKER_PRESENT=true"

git_available=false
if command -v git >/dev/null 2>&1 && git -C "$project_dir" rev-parse --git-dir >/dev/null 2>&1; then
  git_available=true
fi
echo "GIT_AVAILABLE=${git_available}"

# Step 3b: per-feature evidence backfill + status inference.
# For each feature with a non-empty implementation.files array:
#   - count how many listed files exist on disk;
#   - backfill implementation.commits from `git log --follow` per file
#     (deduped, merged into the existing array);
#   - infer status ONLY when current status == not_started, via:
#       all files exist            -> complete
#       some files exist           -> partial
#       no files exist             -> stays not_started
#   - the never-downgrade guard: a feature already complete/in_progress/
#     partial is never lowered, regardless of evidence.
features_total="$(jq '(.features // []) | length' "$tracker")"
echo "FEATURES_TOTAL=${features_total}"

flipped_count=0
work_json="$(jq -c '.' "$tracker")"

fi_index=0
while [ "$fi_index" -lt "$features_total" ]; do
  fr_id="$(printf '%s' "$work_json" | jq -r ".features[$fi_index].id // \"\"")"
  fr_status="$(printf '%s' "$work_json" | jq -r ".features[$fi_index].status // \"not_started\"")"
  files_n="$(printf '%s' "$work_json" | jq -r ".features[$fi_index].implementation.files // [] | length")"

  if [ "$files_n" -eq 0 ]; then
    fi_index=$((fi_index + 1))
    continue
  fi

  # Count existing files and gather their commit SHAs.
  exist_n=0
  new_commits=""
  while IFS= read -r rel_file; do
    [ -n "$rel_file" ] || continue
    if [ -e "${project_dir}/${rel_file}" ]; then
      exist_n=$((exist_n + 1))
      if [ "$git_available" = "true" ]; then
        file_commits="$(git -C "$project_dir" log --follow --format='%H' -- "$rel_file" 2>/dev/null || true)"
        new_commits="${new_commits}${file_commits}
"
      fi
    fi
  done < <(printf '%s' "$work_json" | jq -r ".features[$fi_index].implementation.files[]")

  # Infer status (never-downgrade guard).
  inferred="null"
  if [ "$fr_status" = "not_started" ]; then
    if [ "$exist_n" -eq "$files_n" ]; then
      inferred="complete"
    elif [ "$exist_n" -gt 0 ]; then
      inferred="partial"
    fi
  fi

  commits_file="$(mktemp)"
  printf '%s' "$new_commits" > "$commits_file"
  today="$(date -u +%Y-%m-%d)"

  work_json="$(printf '%s' "$work_json" | jq -c \
    --argjson i "$fi_index" \
    --rawfile commits "$commits_file" \
    --arg inferred "$inferred" \
    --arg today "$today" '
    .features[$i] |= (
      . as $fr
      | .implementation.commits = (
          ((.implementation.commits // []) +
           ($commits | split("\n") | map(select(length > 0))))
          | unique
        )
      | if ($fr.status // "not_started") == "not_started" and $inferred != "null"
        then .status = $inferred
             | (if $inferred == "complete" then .completed_at = $today else . end)
        else .
        end
    )
  ')"
  rm -f "$commits_file"

  if [ "$inferred" != "null" ]; then
    flipped_count=$((flipped_count + 1))
    add_issue WARN status_inferred "FR=${fr_id} FROM=not_started TO=${inferred} FILES_EXIST=${exist_n}/${files_n}"
  fi

  fi_index=$((fi_index + 1))
done

echo "EVIDENCE_FLIPPED=${flipped_count}"

# Step 6: statistics rollup across all features.
stat_complete="$(printf '%s' "$work_json" | jq '[.features[]? | select(.status == "complete")] | length')"
stat_partial="$(printf '%s' "$work_json" | jq '[.features[]? | select(.status == "partial")] | length')"
stat_in_progress="$(printf '%s' "$work_json" | jq '[.features[]? | select(.status == "in_progress")] | length')"
stat_not_started="$(printf '%s' "$work_json" | jq '[.features[]? | select(.status == "not_started")] | length')"
stat_blocked="$(printf '%s' "$work_json" | jq '[.features[]? | select(.status == "blocked")] | length')"

completion_pct=0
if [ "$features_total" -gt 0 ]; then
  completion_pct="$(jq -n --argjson c "$stat_complete" --argjson t "$features_total" '(($c / $t) * 1000 | round) / 10')"
fi

echo "STAT_COMPLETE=${stat_complete}"
echo "STAT_PARTIAL=${stat_partial}"
echo "STAT_IN_PROGRESS=${stat_in_progress}"
echo "STAT_NOT_STARTED=${stat_not_started}"
echo "STAT_BLOCKED=${stat_blocked}"
echo "COMPLETION_PERCENTAGE=${completion_pct}"

# Persist the backfilled tracker (Step 3b/Step 7) unless --dry-run.
if [ "$dry_run" = "true" ]; then
  echo "TRACKER_WRITTEN=false"
else
  printf '%s' "$work_json" | jq '.' > "${tracker}.tmp" && mv "${tracker}.tmp" "$tracker"
  echo "TRACKER_WRITTEN=true"
fi

if [ "$flipped_count" -gt 0 ]; then
  sync_status="WARN"
fi

echo "STATUS=${sync_status}"
echo "ISSUE_COUNT=${issue_count}"
if [ -n "$issues_list" ]; then
  echo "ISSUES:"
  printf '%b' "$issues_list" | sed '/^$/d'
fi
echo "=== END FEATURE TRACKER SYNC ==="
exit 0
