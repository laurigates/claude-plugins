#!/usr/bin/env bash
# Run the routing suite: N runs of each (task × condition) pair.
# Adapted from experiments/claude-probe/scripts/run-suite.sh (tasks/, not tests/).
#
# Usage: run-suite.sh [--filter <glob>] [--runs <n>] [--conditions <csv>] [--run-id <id>]
# Defaults: --runs 3, all conditions, run-id = timestamp.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/.." && pwd)"

runs=3
filter="*"
tasks_csv=""
conditions_csv=""
run_id=""

while [ $# -gt 0 ]; do
  case "$1" in
    --filter) filter="$2"; shift 2 ;;
    --tasks) tasks_csv="$2"; shift 2 ;;
    --runs) runs="$2"; shift 2 ;;
    --conditions) conditions_csv="$2"; shift 2 ;;
    --run-id) run_id="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

[ -z "$run_id" ] && run_id="$(date -u +%Y%m%d-%H%M%S)"
run_dir="$root/results/$run_id"
mkdir -p "$run_dir"

# Resolve task files: explicit --tasks csv wins, else glob on --filter.
task_files=()
if [ -n "$tasks_csv" ]; then
  IFS=',' read -ra want <<< "$tasks_csv"
  for t in "${want[@]}"; do
    tf="$root/tasks/${t}.yaml"
    [ -f "$tf" ] || { echo "no such task: $t ($tf)" >&2; exit 1; }
    task_files+=("$tf")
  done
else
  mapfile -t task_files < <(find "$root/tasks" -maxdepth 1 -type f -name "${filter}.yaml" | sort)
fi
[ "${#task_files[@]}" -gt 0 ] || { echo "no tasks matched (filter=$filter tasks=$tasks_csv)" >&2; exit 1; }

# Resolve conditions.
if [ -n "$conditions_csv" ]; then
  IFS=',' read -ra conditions <<< "$conditions_csv"
else
  mapfile -t conditions < <(
    python3 -c '
import yaml
data = yaml.safe_load(open("'"$root"'/conditions.yaml"))
for c in data["conditions"]:
    print(c["id"])
'
  )
fi

echo "[run-suite] run_id=$run_id"
echo "[run-suite] runs=$runs  conditions=${conditions[*]}"
echo "[run-suite] tasks=${#task_files[@]}  dir=$run_dir"

total=0
failed=0
for tf in "${task_files[@]}"; do
  task_id="$(basename "$tf" .yaml)"
  for cond in "${conditions[@]}"; do
    for ((n=1; n<=runs; n++)); do
      total=$((total+1))
      if ! "$here/run-one.sh" "$task_id" "$cond" "$n" "$run_dir"; then
        failed=$((failed+1))
      fi
    done
  done
done

echo "[run-suite] done. $total runs, $failed failed."
echo "[run-suite] results: $run_dir"
printf '%s' "$run_id" > "$root/results/LATEST"
