#!/usr/bin/env bash
# Prepare an eval run directory and write a run manifest.
#
# Creates:
#   <skill-dir>/eval-results/runs/<eval-id>-run-<N>/
# Writes:
#   <skill-dir>/eval-results/runs/<eval-id>-run-<N>/manifest.json
#
# Usage:
#   prepare_run.sh --skill-dir <path> --eval-id <id> --run <N> [--baseline]
#
# Output: KEY=value lines
#   RUN_DIR=<absolute path>
#   MANIFEST=<absolute path>
#   STARTED_AT=<iso8601>

set -uo pipefail

skill_dir=""
eval_id=""
run_num=""
baseline=false

while [ $# -gt 0 ]; do
  case "$1" in
    --skill-dir) skill_dir="$2"; shift 2 ;;
    --eval-id) eval_id="$2"; shift 2 ;;
    --run) run_num="$2"; shift 2 ;;
    --baseline) baseline=true; shift ;;
    *) shift ;;
  esac
done

if [ -z "$skill_dir" ] || [ -z "$eval_id" ] || [ -z "$run_num" ]; then
  echo "ERROR: --skill-dir, --eval-id, and --run are required" >&2
  exit 1
fi

if [ ! -d "$skill_dir" ]; then
  echo "ERROR: skill directory not found: $skill_dir" >&2
  exit 1
fi

echo "=== PREPARE RUN ==="

subdir="runs"
if [ "$baseline" = true ]; then
  subdir="baseline"
fi

run_dir="$skill_dir/eval-results/$subdir/${eval_id}-run-${run_num}"
mkdir -p "$run_dir"

started_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
manifest="$run_dir/manifest.json"

jq -n \
  --arg eid "$eval_id" \
  --argjson run "$run_num" \
  --arg ts "$started_at" \
  --argjson baseline "$baseline" \
  '{eval_id: $eid, run: $run, started_at: $ts, baseline: $baseline}' \
  > "$manifest"

echo "RUN_DIR=$run_dir"
echo "MANIFEST=$manifest"
echo "STARTED_AT=$started_at"
