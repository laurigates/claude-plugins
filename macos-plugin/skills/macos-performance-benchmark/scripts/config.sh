#!/usr/bin/env bash
# config.sh — thresholds and paths for the macOS performance benchmark suite.
#
# Every value is env-overridable so the suite is NOT locked to one machine.
# Defaults are calibrated for an Apple Silicon M4 Pro (10P + 4E, 48 GB). To
# retune for a different Mac, export the relevant MACOS_PERF_* variable (or
# drop a `thresholds.local.sh` beside this file and source it) before running.
#
# This file is sourced; its variables are consumed by the diag/bench scripts.
# shellcheck disable=SC2034

# ── Where saved runs live (user-writable, outside the plugin dir) ─────────────
RESULTS_BASE="${MACOS_PERF_RESULTS_DIR:-${HOME}/.cache/macos-perf}"

# ── Diagnostics thresholds ────────────────────────────────────────────────────
# CPU: per-process CPU% that trips warn/fail (kernel_task/launchd excluded)
CPU_PROC_FAIL_PCT="${MACOS_PERF_CPU_PROC_FAIL_PCT:-50}"
CPU_PROC_WARN_PCT="${MACOS_PERF_CPU_PROC_WARN_PCT:-20}"
# CPU package power (W) — from macmon (sudo-free) or powermetrics (sudo)
CPU_POWER_FAIL_W="${MACOS_PERF_CPU_POWER_FAIL_W:-35}"
CPU_POWER_WARN_W="${MACOS_PERF_CPU_POWER_WARN_W:-15}"

# Memory
RAM_MIN_GB="${MACOS_PERF_RAM_MIN_GB:-32}"
MEM_FREE_FAIL_PCT="${MACOS_PERF_MEM_FREE_FAIL_PCT:-10}"
MEM_FREE_WARN_PCT="${MACOS_PERF_MEM_FREE_WARN_PCT:-20}"
WIRED_WARN_PCT="${MACOS_PERF_WIRED_WARN_PCT:-40}"
RSS_FAIL_GB="${MACOS_PERF_RSS_FAIL_GB:-8}"
RSS_WARN_GB="${MACOS_PERF_RSS_WARN_GB:-4}"

# Disk
DISK_FREE_FAIL_PCT="${MACOS_PERF_DISK_FREE_FAIL_PCT:-10}"
DISK_FREE_WARN_PCT="${MACOS_PERF_DISK_FREE_WARN_PCT:-20}"
LARGE_FILE_WARN_GB="${MACOS_PERF_LARGE_FILE_WARN_GB:-10}"

# Startup / background
BTM_THIRD_PARTY_WARN="${MACOS_PERF_BTM_THIRD_PARTY_WARN:-20}"
LAUNCH_ITEMS_WARN="${MACOS_PERF_LAUNCH_ITEMS_WARN:-15}"
LAUNCHCTL_FAIL="${MACOS_PERF_LAUNCHCTL_FAIL:-60}"
LAUNCHCTL_WARN="${MACOS_PERF_LAUNCHCTL_WARN:-30}"

# ── Benchmark scoring: self-calibrating per-machine baseline ──────────────────
# Benchmarks ship NO fixed thresholds — those would be wrong on every machine
# but the author's. Instead the first run records each score as this machine's
# baseline (best-seen, in ${RESULTS_BASE}/baseline.env); later runs compare
# against it and ratchet the baseline up whenever a score improves. The verdict
# is relative degradation from best:
BENCH_WARN_DEGRADE="${MACOS_PERF_BENCH_WARN_DEGRADE:-10}"  # % below best -> WARN
BENCH_FAIL_DEGRADE="${MACOS_PERF_BENCH_FAIL_DEGRADE:-30}"  # % below best -> FAIL

# Multi-core scaling efficiency keeps an absolute architectural floor (%) —
# it's a quality ratio, not a raw score, so it doesn't self-calibrate.
SCALING_WARN_PCT="${MACOS_PERF_SCALING_WARN_PCT:-70}"
# 16 GB allocation pressure drop (health signal, absolute, percentage points):
MEM_PRESSURE_DROP_WARN_PP="${MACOS_PERF_MEM_PRESSURE_DROP_WARN_PP:-10}"
# NVMe benchmark test-file size (MB):
DISK_TEST_SIZE_MB="${MACOS_PERF_DISK_TEST_SIZE_MB:-4096}"

# Optional local override file (gitignored / per-machine calibration)
if [[ -f "${MACOS_PERF_LIB_DIR:-}/../thresholds.local.sh" ]]; then
  # shellcheck disable=SC1091
  source "${MACOS_PERF_LIB_DIR}/../thresholds.local.sh"
fi
