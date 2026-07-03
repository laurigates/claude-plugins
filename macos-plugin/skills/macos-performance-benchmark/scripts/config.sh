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

# ── Benchmark thresholds (M4 Pro baselines) ───────────────────────────────────
# OpenSSL throughput (MB/s @16KB block)
AES_FAIL_MBS="${MACOS_PERF_AES_FAIL_MBS:-1019}"
AES_WARN_MBS="${MACOS_PERF_AES_WARN_MBS:-1426}"
SHA_FAIL_MBS="${MACOS_PERF_SHA_FAIL_MBS:-1497}"
SHA_WARN_MBS="${MACOS_PERF_SHA_WARN_MBS:-2096}"
# Python single-core wall time (seconds)
PY_SINGLE_FAIL_S="${MACOS_PERF_PY_SINGLE_FAIL_S:-8}"
PY_SINGLE_WARN_S="${MACOS_PERF_PY_SINGLE_WARN_S:-5}"
# Multi-core scaling efficiency (%)
SCALING_WARN_PCT="${MACOS_PERF_SCALING_WARN_PCT:-70}"
# Memory dd read-back (GB/s)
DD_READ_WARN_GBS="${MACOS_PERF_DD_READ_WARN_GBS:-2}"
MEM_PRESSURE_DROP_WARN_PP="${MACOS_PERF_MEM_PRESSURE_DROP_WARN_PP:-10}"
# NVMe sequential throughput (GB/s ×10 to stay in integer math)
DISK_WRITE_FAIL_GBS_X10="${MACOS_PERF_DISK_WRITE_FAIL_GBS_X10:-15}"
DISK_WRITE_WARN_GBS_X10="${MACOS_PERF_DISK_WRITE_WARN_GBS_X10:-25}"
DISK_READ_FAIL_GBS_X10="${MACOS_PERF_DISK_READ_FAIL_GBS_X10:-20}"
DISK_READ_WARN_GBS_X10="${MACOS_PERF_DISK_READ_WARN_GBS_X10:-40}"
DISK_TEST_SIZE_MB="${MACOS_PERF_DISK_TEST_SIZE_MB:-4096}"

# Optional local override file (gitignored / per-machine calibration)
if [[ -f "${MACOS_PERF_LIB_DIR:-}/../thresholds.local.sh" ]]; then
  # shellcheck disable=SC1091
  source "${MACOS_PERF_LIB_DIR}/../thresholds.local.sh"
fi
