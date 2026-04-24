#!/usr/bin/env bash
# Run the test suite: N runs of each (test x condition) pair.
#
# Usage: run-suite.sh [--filter <glob>] [--runs <n>] [--conditions <csv>] [--run-id <id>]
# Defaults: --runs 3, all conditions, run-id = timestamp.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/.." && pwd)"

runs=3
filter="*"
conditions_csv=""
run_id=""

while [ $# -gt 0 ]; do
  case "$1" in
    --filter) filter="$2"; shift 2 ;;
    --runs) runs="$2"; shift 2 ;;
    --conditions) conditions_csv="$2"; shift 2 ;;
    --run-id) run_id="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

[ -z "$run_id" ] && run_id="$(date -u +%Y%m%d-%H%M%S)"
run_dir="$root/results/$run_id"
mkdir -p "$run_dir"

# Resolve test ids from filter.
mapfile -t test_files < <(find "$root/tests" -maxdepth 1 -type f -name "${filter}.yaml" | sort)
[ "${#test_files[@]}" -gt 0 ] || { echo "no tests matched filter: $filter" >&2; exit 1; }

# Resolve conditions.
if [ -n "$conditions_csv" ]; then
  IFS=',' read -ra conditions <<< "$conditions_csv"
else
  mapfile -t conditions < <(
    python3 -c '
import yaml
with open("'"$root"'/conditions.yaml") as f:
    data = yaml.safe_load(f)
for c in data["conditions"]:
    print(c["id"])
'
  )
fi

echo "[run-suite] run_id=$run_id"
echo "[run-suite] runs=$runs  conditions=${conditions[*]}"
echo "[run-suite] tests=${#test_files[@]}  dir=$run_dir"

total=0
failed=0
for tf in "${test_files[@]}"; do
  test_id="$(basename "$tf" .yaml)"
  for cond in "${conditions[@]}"; do
    for ((n=1; n<=runs; n++)); do
      total=$((total+1))
      if ! "$here/run-one.sh" "$test_id" "$cond" "$n" "$run_dir"; then
        failed=$((failed+1))
      fi
    done
  done
done

echo "[run-suite] done. $total runs, $failed failed."
echo "[run-suite] results: $run_dir"
printf '%s' "$run_id" > "$root/results/LATEST"
