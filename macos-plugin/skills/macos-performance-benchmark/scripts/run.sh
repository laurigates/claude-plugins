#!/usr/bin/env bash
# run.sh — orchestrator for the macOS performance benchmark suite.
# Replaces the standalone justfile: it creates one timestamped RUN_DIR, runs the
# selected diag/bench scripts against it, then generates the markdown report.
#
# Usage: run.sh <mode>
#   diagnose     all 4 diagnostics + report (~25s, no sudo needed)
#   bench        all 3 benchmarks + report (~3 min)
#   full         diagnose + bench in one run (~5 min)
#   diag-cpu | diag-memory | diag-disk | diag-startup   single diagnostic
#   bench-cpu | bench-memory | bench-disk               single benchmark
#   report       (re)generate report.md for the most recent run
#   report-list  list saved runs with PASS/WARN/FAIL counts
#   baseline-show   print this machine's recorded benchmark baseline
#   baseline-reset  clear the baseline (next bench run re-establishes it)
#
# `set -u` only (no -e / pipefail): a single failed diagnostic section must not
# abort the sequence — every mode still reaches report generation.
set -u

SCRIPTS_ROOT="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPTS_ROOT}/config.sh"

# ── Platform guard (Darwin only) ──────────────────────────────────────────────
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "macos-performance-benchmark: not Darwin, refusing" >&2
  exit 1
fi

mode="${1:-full}"

run_one() {  # run_one <section-tag> <script-relpath>
  SCRIPT_SECTION="$1" bash "${SCRIPTS_ROOT}/$2"
}

case "$mode" in
  diagnose|bench|full|diag-cpu|diag-memory|diag-disk|diag-startup|bench-cpu|bench-memory|bench-disk)
    RUN_DIR="${RESULTS_BASE}/$(date +%Y%m%d_%H%M%S)"
    export RUN_DIR
    mkdir -p "$RUN_DIR"
    echo "Run directory: $RUN_DIR"
    ;;
esac

case "$mode" in
  diagnose)
    run_one diag-cpu     diag/cpu.sh
    run_one diag-memory  diag/memory.sh
    run_one diag-disk    diag/disk.sh
    run_one diag-startup diag/startup.sh
    bash "${SCRIPTS_ROOT}/report/generate.sh" "$RUN_DIR"
    ;;
  bench)
    run_one bench-cpu    bench/cpu.sh
    run_one bench-memory bench/memory.sh
    run_one bench-disk   bench/disk.sh
    bash "${SCRIPTS_ROOT}/report/generate.sh" "$RUN_DIR"
    ;;
  full)
    run_one diag-cpu     diag/cpu.sh
    run_one diag-memory  diag/memory.sh
    run_one diag-disk    diag/disk.sh
    run_one diag-startup diag/startup.sh
    run_one bench-cpu    bench/cpu.sh
    run_one bench-memory bench/memory.sh
    run_one bench-disk   bench/disk.sh
    bash "${SCRIPTS_ROOT}/report/generate.sh" "$RUN_DIR"
    ;;
  diag-cpu)     run_one diag-cpu     diag/cpu.sh ;;
  diag-memory)  run_one diag-memory  diag/memory.sh ;;
  diag-disk)    run_one diag-disk    diag/disk.sh ;;
  diag-startup) run_one diag-startup diag/startup.sh ;;
  bench-cpu)    run_one bench-cpu    bench/cpu.sh ;;
  bench-memory) run_one bench-memory bench/memory.sh ;;
  bench-disk)   run_one bench-disk   bench/disk.sh ;;
  report)
    bash "${SCRIPTS_ROOT}/report/generate.sh"
    ;;
  baseline-show)
    bf="${RESULTS_BASE}/baseline.env"
    if [[ -f "$bf" ]]; then echo "Benchmark baseline ($bf):"; sort "$bf"; else echo "No baseline yet — run 'bench' to establish one."; fi
    ;;
  baseline-reset)
    rm -f "${RESULTS_BASE}/baseline.env"
    echo "Baseline cleared — the next bench run will re-establish it."
    ;;
  report-list)
    echo "Saved runs in ${RESULTS_BASE}/"
    find "${RESULTS_BASE}" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort | while read -r d; do
      ts="$(basename "$d")"
      pass="$(grep -c '^PASS' "$d/summary.tsv" 2>/dev/null || echo 0)"
      warn="$(grep -c '^WARN' "$d/summary.tsv" 2>/dev/null || echo 0)"
      fail="$(grep -c '^FAIL' "$d/summary.tsv" 2>/dev/null || echo 0)"
      printf "  %-20s  PASS:%-3s WARN:%-3s FAIL:%-3s\n" "$ts" "$pass" "$warn" "$fail"
    done
    ;;
  *)
    echo "Unknown mode: $mode" >&2
    echo "Modes: diagnose bench full diag-cpu diag-memory diag-disk diag-startup bench-cpu bench-memory bench-disk report report-list baseline-show baseline-reset" >&2
    exit 2
    ;;
esac
