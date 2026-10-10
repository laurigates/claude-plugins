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
#
# Both shapes of `features` are handled (#2867): the OBJECT keyed by FR id that
# schemas/feature-tracker.schema.json declares (FR category -> nested
# `features` object of FR sub-features), and the flat ARRAY of records that
# reporting repos use. The resolved shape is reported as
# FEATURES_SHAPE=object|array|absent and is written back unchanged.
#
# Exit 0 on OK/WARN, 1 on ERROR. Any failed jq step is an ERROR: the script
# never reports STATUS=OK after a failure, and never writes a tracker it
# failed to process.

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
  echo "REASON=missing_tool: jq is required but not installed"
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
  echo "REASON=tracker_missing: feature-tracker.json not found; run /blueprint:init"
  echo "ISSUE_COUNT=1"
  echo "ISSUES:"
  echo "  - SEVERITY=ERROR TYPE=tracker_missing MSG=feature-tracker.json not found; run /blueprint:init"
  echo "=== END FEATURE TRACKER SYNC ==="
  exit 1
fi
if ! jq empty "$tracker" >/dev/null 2>&1; then
  echo "TRACKER_PRESENT=true"
  echo "STATUS=ERROR"
  echo "REASON=invalid_json: feature-tracker.json is not valid JSON"
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

# finish_error <type> <msg>: a failed jq/IO step. Emit STATUS=ERROR naming the
# cause, leave the tracker unwritten, exit 1. Every jq call from here on routes
# its exit status through this, so a failure can never fall through to
# STATUS=OK with empty STAT_* fields (#2867).
finish_error() {
  local err_msg="${2//$'\n'/ }"
  add_issue ERROR "$1" "MSG=${err_msg}"
  echo "TRACKER_WRITTEN=false"
  echo "STATUS=ERROR"
  echo "REASON=$1: ${err_msg:0:170}"
  echo "ISSUE_COUNT=${issue_count}"
  echo "ISSUES:"
  printf '%b' "$issues_list" | sed '/^$/d'
  echo "=== END FEATURE TRACKER SYNC ==="
  exit 1
}

# Shape detection, the same resolution blueprint-plugin/scripts/
# blueprint-tracker-check.sh reports: array | object | absent (missing/null).
# Any other type (a string, a number) is a malformed tracker, not "absent".
features_shape="$(jq -r '(.features // null) | type' "$tracker" 2>&1)" \
  || finish_error jq_failed "cannot read .features (${features_shape})"
case "$features_shape" in
  array|object) : ;;
  null) features_shape="absent" ;;
  *) finish_error malformed_features "features is a ${features_shape}; expected an object keyed by FR id or an array of records" ;;
esac
echo "FEATURES_SHAPE=${features_shape}"

# A feature RECORD is any object in the features collection that carries a
# `status` field, reached by descending only through `features` collections
# (array items or object values) — the record set blueprint-tracker-check.sh
# counts. An FR category with no `status` of its own is not a record; its
# status-bearing sub-features are. Records are addressed by jq PATH, so each
# update is a getpath/setpath that writes the original shape back unchanged.
# shellcheck disable=SC2016  # jq program text, not a shell expansion
JQ_RECORD_PATHS='
def members($p):
  getpath($p) as $c
  | if ($c | type) == "array" then range(0; $c | length) | $p + [.]
    elif ($c | type) == "object" then $c | keys_unsorted[] | $p + [.]
    else empty end;
def records($p):
  members($p) as $m
  | getpath($m) as $v
  | select(($v | type) == "object")
  | (if ($v | has("status")) then $m else empty end),
    (if ((($v.features // null) | type) | . == "array" or . == "object")
     then records($m + ["features"]) else empty end);
[records(["features"])]
'

# Step 3b: per-feature evidence backfill + status inference.
# For each feature record with a non-empty implementation.files array:
#   - count how many listed files exist on disk;
#   - backfill implementation.commits from `git log --follow` per file
#     (deduped, merged into the existing array);
#   - infer status ONLY when current status == not_started, via:
#       all files exist            -> complete
#       some files exist           -> partial
#       no files exist             -> stays not_started
#   - the never-downgrade guard: a feature already complete/in_progress/
#     partial is never lowered, regardless of evidence.
work_json="$(jq -c '.' "$tracker" 2>&1)" \
  || finish_error jq_failed "cannot load tracker (${work_json})"
record_paths="$(printf '%s' "$work_json" | jq -c "$JQ_RECORD_PATHS" 2>&1)" \
  || finish_error jq_failed "cannot enumerate feature records (${record_paths})"
features_total="$(printf '%s' "$record_paths" | jq 'length' 2>&1)" \
  || finish_error jq_failed "cannot count feature records (${features_total})"
echo "FEATURES_TOTAL=${features_total}"

flipped_count=0
today="$(date -u +%Y-%m-%d)"

# One row per record: <path-json> TAB <id> TAB <status> TAB <files-json>.
# The id is the object key in the object shape, else .id/.code/.name.
record_rows="$(printf '%s' "$work_json" | jq -r --argjson paths "$record_paths" '
  . as $root
  | $paths[] as $p
  | ($root | getpath($p)) as $r
  | [ ($p | tojson),
      (if ($p[-1] | type) == "string" then $p[-1]
       else (($r.id // $r.code // $r.name // "?") | tostring) end),
      (($r.status // "not_started") | tostring),
      ((($r.implementation // {}) | if type == "object" then (.files // []) else [] end)
        | if type == "array" then map(select(type == "string" and length > 0)) else [] end
        | tojson) ]
  | @tsv' 2>&1)" \
  || finish_error jq_failed "cannot read feature records (${record_rows})"

while IFS=$'\t' read -r rec_path fr_id fr_status files_json; do
  [ -n "$rec_path" ] || continue
  files_n="$(printf '%s' "$files_json" | jq 'length' 2>&1)" \
    || finish_error jq_failed "FR=${fr_id}: cannot read implementation.files (${files_n})"
  [ "$files_n" -gt 0 ] || continue

  # Count existing files and gather their commit SHAs.
  exist_n=0
  new_commits=""
  file_list="$(printf '%s' "$files_json" | jq -r '.[]' 2>&1)" \
    || finish_error jq_failed "FR=${fr_id}: cannot list implementation.files (${file_list})"
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
  done <<< "$file_list"

  # Infer status (never-downgrade guard).
  inferred="null"
  if [ "$fr_status" = "not_started" ]; then
    if [ "$exist_n" -eq "$files_n" ]; then
      inferred="complete"
    elif [ "$exist_n" -gt 0 ]; then
      inferred="partial"
    fi
  fi

  updated="$(printf '%s' "$work_json" | jq -c \
    --argjson p "$rec_path" \
    --arg commits "$new_commits" \
    --arg inferred "$inferred" \
    --arg today "$today" '
    setpath($p; getpath($p)
      | . as $fr
      | .implementation = ((.implementation // {}) | if type == "object" then . else {} end)
      | .implementation.commits = (
          (((.implementation.commits // []) | if type == "array" then . else [] end) +
           ($commits | split("\n") | map(select(length > 0))))
          | unique
        )
      | if ($fr.status // "not_started") == "not_started" and $inferred != "null"
        then .status = $inferred
             | (if $inferred == "complete" then .completed_at = $today else . end)
        else .
        end)
  ' 2>&1)" \
    || finish_error jq_failed "FR=${fr_id}: cannot apply evidence backfill (${updated})"
  work_json="$updated"

  if [ "$inferred" != "null" ]; then
    flipped_count=$((flipped_count + 1))
    add_issue WARN status_inferred "FR=${fr_id} FROM=not_started TO=${inferred} FILES_EXIST=${exist_n}/${files_n}"
  fi
done <<< "$record_rows"

echo "EVIDENCE_FLIPPED=${flipped_count}"

# Step 6: statistics rollup across the same record set as FEATURES_TOTAL.
stats="$(printf '%s' "$work_json" | jq -r --argjson paths "$record_paths" '
  . as $root
  | [ $paths[] as $p | ($root | getpath($p) | .status // "" | tostring) ] as $s
  | [ "complete", "partial", "in_progress", "not_started", "blocked" ]
  | map(. as $k | [$s[] | select(. == $k)] | length)
  | @tsv' 2>&1)" \
  || finish_error jq_failed "cannot compute statistics (${stats})"
IFS=$'\t' read -r stat_complete stat_partial stat_in_progress stat_not_started stat_blocked <<< "$stats"

completion_pct=0
if [ "$features_total" -gt 0 ]; then
  completion_pct="$(jq -n --argjson c "$stat_complete" --argjson t "$features_total" '(($c / $t) * 1000 | round) / 10' 2>&1)" \
    || finish_error jq_failed "cannot compute completion percentage (${completion_pct})"
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
  if ! printf '%s' "$work_json" | jq '.' > "${tracker}.tmp" 2>/dev/null \
     || ! mv "${tracker}.tmp" "$tracker"; then
    rm -f "${tracker}.tmp"
    finish_error write_failed "cannot write ${tracker}"
  fi
  echo "TRACKER_WRITTEN=true"
fi

if [ "$flipped_count" -gt 0 ]; then
  sync_status="WARN"
fi

echo "STATUS=${sync_status}"
if [ "$sync_status" != "OK" ]; then
  first_issue="$(printf '%b' "$issues_list" | sed '/^$/d' | sed -n '1s/^  - SEVERITY=[A-Z]* TYPE=\([^ ]*\) /\1: /p')"
  more=""
  [ "$issue_count" -gt 1 ] && more=" (+$((issue_count - 1)) more)"
  echo "REASON=${first_issue:0:180}${more}"
fi
echo "ISSUE_COUNT=${issue_count}"
if [ -n "$issues_list" ]; then
  echo "ISSUES:"
  printf '%b' "$issues_list" | sed '/^$/d'
fi
echo "=== END FEATURE TRACKER SYNC ==="
exit 0
