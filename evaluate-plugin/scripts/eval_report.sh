#!/usr/bin/env bash
# Generate a formatted markdown report from benchmark data.
#
# Usage: ./evaluate-plugin/scripts/eval_report.sh <benchmark.json>
# Output: Formatted markdown report to stdout

set -euo pipefail

benchmark_file="${1:?Usage: eval_report.sh <benchmark.json>}"

if [ ! -f "$benchmark_file" ]; then
  echo "Error: $benchmark_file not found" >&2
  exit 1
fi

# Detect file type: skill-level or plugin-level
if jq -e '.skills' "$benchmark_file" >/dev/null 2>&1; then
  # Plugin-level benchmark
  plugin_name=$(jq -r '.metadata.plugin_name' "$benchmark_file")
  timestamp=$(jq -r '.metadata.timestamp' "$benchmark_file")
  evaluated=$(jq -r '.metadata.skills_evaluated' "$benchmark_file")
  total=$(jq -r '.metadata.skills_total' "$benchmark_file")
  overall=$(jq -r '.summary.overall_pass_rate' "$benchmark_file")
  overall_pct=$(printf '%.0f' "$(echo "$overall * 100" | bc -l 2>/dev/null || echo 0)")

  echo "## Plugin Evaluation Report: $plugin_name"
  echo ""
  echo "**Generated**: $timestamp"
  echo "**Skills evaluated**: $evaluated / $total"
  echo "**Overall pass rate**: ${overall_pct}%"
  echo ""
  echo "| Skill | Evals | Pass Rate | Status |"
  echo "|-------|-------|-----------|--------|"

  jq -r '.skills[] | "| \(.skill_name) | \(.num_evals) | \(.mean_pass_rate * 100 | floor)% | \(.status) |"' "$benchmark_file"

  echo ""
  echo "### Summary"
  echo ""
  passing=$(jq -r '.summary.skills_passing' "$benchmark_file")
  partial=$(jq -r '.summary.skills_partial' "$benchmark_file")
  failing=$(jq -r '.summary.skills_failing' "$benchmark_file")
  echo "- Passing (>=80%): $passing"
  echo "- Partial (50-79%): $partial"
  echo "- Failing (<50%): $failing"

else
  # Skill-level benchmark
  skill_path=$(jq -r '.metadata.skill_path' "$benchmark_file")
  timestamp=$(jq -r '.metadata.timestamp' "$benchmark_file")
  num_evals=$(jq -r '.metadata.num_evals' "$benchmark_file")
  num_runs=$(jq -r '.metadata.num_runs_per_eval' "$benchmark_file")

  echo "## Evaluation Report: $skill_path"
  echo ""
  echo "**Generated**: $timestamp"
  echo "**Eval cases**: $num_evals"
  echo "**Runs per eval**: $num_runs"
  echo ""

  # Summary table
  ws_rate=$(jq -r '.summary.with_skill.mean_pass_rate // "N/A"' "$benchmark_file")
  ws_dur=$(jq -r '.summary.with_skill.mean_duration_ms // "N/A"' "$benchmark_file")

  has_baseline=$(jq -e '.summary.baseline.mean_pass_rate != null' "$benchmark_file" 2>/dev/null && echo "true" || echo "false")

  if [ "$has_baseline" = "true" ]; then
    bl_rate=$(jq -r '.summary.baseline.mean_pass_rate' "$benchmark_file")
    bl_dur=$(jq -r '.summary.baseline.mean_duration_ms' "$benchmark_file")
    delta_rate=$(jq -r '.summary.delta.pass_rate_improvement' "$benchmark_file")
    delta_dur=$(jq -r '.summary.delta.duration_overhead_ms' "$benchmark_file")

    ws_pct=$(printf '%.0f' "$(echo "$ws_rate * 100" | bc -l 2>/dev/null || echo 0)")
    bl_pct=$(printf '%.0f' "$(echo "$bl_rate * 100" | bc -l 2>/dev/null || echo 0)")
    delta_pct=$(printf '%+.0f' "$(echo "$delta_rate * 100" | bc -l 2>/dev/null || echo 0)")

    echo "| Metric | With Skill | Baseline | Delta |"
    echo "|--------|-----------|----------|-------|"
    echo "| Pass Rate | ${ws_pct}% | ${bl_pct}% | ${delta_pct}% |"
    echo "| Duration | ${ws_dur}ms | ${bl_dur}ms | ${delta_dur}ms |"
  else
    ws_pct=$(printf '%.0f' "$(echo "$ws_rate * 100" | bc -l 2>/dev/null || echo 0)")
    echo "| Metric | Value |"
    echo "|--------|-------|"
    echo "| Pass Rate | ${ws_pct}% |"
    echo "| Duration | ${ws_dur}ms |"
  fi

  echo ""

  # Per-eval breakdown
  echo "### Per-Eval Results"
  echo ""
  echo "| Eval ID | Config | Pass Rate |"
  echo "|---------|--------|-----------|"

  jq -r '.results[] | "| \(.eval_id) | \(.config) | \(.runs[0].grading.summary.pass_rate * 100 | floor)% |"' "$benchmark_file" 2>/dev/null || true
fi
