#!/usr/bin/env bash
# Aggregate benchmark results across all skills in a plugin.
#
# Usage: ./evaluate-plugin/scripts/aggregate_benchmark.sh <plugin-name>
# Reads:  <plugin-name>/skills/*/eval-results/benchmark.json
# Writes: <plugin-name>/eval-results/plugin-benchmark.json

set -euo pipefail

plugin_name="${1:?Usage: aggregate_benchmark.sh <plugin-name>}"

if [ ! -d "$plugin_name/skills" ]; then
  echo "Error: $plugin_name/skills directory not found" >&2
  exit 1
fi

# Count total skills
total_skills=$(find "$plugin_name/skills" -name "SKILL.md" -maxdepth 3 | wc -l)

# Find all benchmark files
benchmark_files=()
while IFS= read -r -d '' f; do
  benchmark_files+=("$f")
done < <(find "$plugin_name/skills" -path "*/eval-results/benchmark.json" -print0 2>/dev/null)

evaluated_count=${#benchmark_files[@]}

if [ "$evaluated_count" -eq 0 ]; then
  echo "No benchmark results found in $plugin_name/skills/*/eval-results/"
  exit 0
fi

# Build per-skill summaries
skill_entries=""
total_pass_rate=0
passing=0
partial=0
failing=0

for bf in "${benchmark_files[@]}"; do
  skill_dir=$(dirname "$(dirname "$bf")")
  skill_name=$(basename "$skill_dir")
  skill_path="$skill_dir/SKILL.md"

  mean_pass_rate=$(jq -r '.summary.with_skill.mean_pass_rate // 0' "$bf")
  num_evals=$(jq -r '.metadata.num_evals // 0' "$bf")

  # Determine status
  status="FAIL"
  pct=$(echo "$mean_pass_rate * 100" | bc -l 2>/dev/null || echo "0")
  pct_int=${pct%.*}
  if [ "${pct_int:-0}" -ge 80 ]; then
    status="PASS"
    passing=$((passing + 1))
  elif [ "${pct_int:-0}" -ge 50 ]; then
    status="PARTIAL"
    partial=$((partial + 1))
  else
    failing=$((failing + 1))
  fi

  total_pass_rate=$(echo "$total_pass_rate + $mean_pass_rate" | bc -l 2>/dev/null || echo "$total_pass_rate")

  entry=$(jq -n \
    --arg sn "$skill_name" \
    --arg sp "$skill_path" \
    --argjson ne "$num_evals" \
    --argjson mpr "$mean_pass_rate" \
    --arg st "$status" \
    '{skill_name: $sn, skill_path: $sp, num_evals: $ne, mean_pass_rate: $mpr, status: $st}')

  if [ -z "$skill_entries" ]; then
    skill_entries="$entry"
  else
    skill_entries="$skill_entries,$entry"
  fi
done

# Compute overall pass rate
if [ "$evaluated_count" -gt 0 ]; then
  overall_pass_rate=$(echo "$total_pass_rate / $evaluated_count" | bc -l 2>/dev/null || echo "0")
else
  overall_pass_rate=0
fi

# Write plugin benchmark
mkdir -p "$plugin_name/eval-results"
timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

jq -n \
  --arg pn "$plugin_name" \
  --arg ts "$timestamp" \
  --argjson se "$evaluated_count" \
  --argjson st "$total_skills" \
  --argjson opr "$overall_pass_rate" \
  --argjson sp "$passing" \
  --argjson spt "$partial" \
  --argjson sf "$failing" \
  --argjson skills "[$skill_entries]" \
  '{
    metadata: {
      plugin_name: $pn,
      timestamp: $ts,
      skills_evaluated: $se,
      skills_total: $st
    },
    skills: $skills,
    summary: {
      overall_pass_rate: $opr,
      skills_passing: $sp,
      skills_partial: $spt,
      skills_failing: $sf
    }
  }' > "$plugin_name/eval-results/plugin-benchmark.json"

echo "Plugin benchmark written to $plugin_name/eval-results/plugin-benchmark.json"
echo "Skills evaluated: $evaluated_count / $total_skills"
echo "Overall pass rate: $(printf '%.0f' "$(echo "$overall_pass_rate * 100" | bc -l 2>/dev/null || echo 0)")%"
