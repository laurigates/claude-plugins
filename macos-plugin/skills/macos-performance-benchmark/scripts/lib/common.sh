#!/usr/bin/env bash
# lib/common.sh — shared emitters, guards, and helpers for the benchmark suite.
# Sourced by every diag/*.sh and bench/*.sh after they set SCRIPT_SECTION.

# Diagnostics run many `producer | head` pipelines whose `head` closes early;
# under `pipefail` that SIGPIPEs the producer (exit 141), and under `set -e` it
# would abort the whole run. A multi-section diagnostic must survive a single
# non-zero and keep collecting, so guard only against unset vars.
set -u

# ── Locate the suite root and load thresholds ─────────────────────────────────
SCRIPT_SECTION="${SCRIPT_SECTION:-unknown}"
MACOS_PERF_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${MACOS_PERF_LIB_DIR}/.." && pwd)"
export MACOS_PERF_LIB_DIR SCRIPTS_ROOT

# shellcheck disable=SC1091
source "${SCRIPTS_ROOT}/config.sh"

# ── Run directory ─────────────────────────────────────────────────────────────
if [[ -z "${RUN_DIR:-}" ]]; then
  RUN_DIR="${RESULTS_BASE}/$(date +%Y%m%d_%H%M%S)"
fi
export RUN_DIR
mkdir -p "$RUN_DIR"

TSV="${RUN_DIR}/summary.tsv"

# ── Colours (only when writing to a TTY) ──────────────────────────────────────
if [[ -t 1 ]]; then
  C_PASS="\033[0;32m" C_WARN="\033[0;33m" C_FAIL="\033[0;31m"
  C_INFO="\033[0;36m" C_SECT="\033[1;34m" C_RST="\033[0m"
else
  C_PASS="" C_WARN="" C_FAIL="" C_INFO="" C_SECT="" C_RST=""
fi

# ── Emitters (terminal line + one well-formed TSV row) ────────────────────────
# Multi-line messages (e.g. a whole `vm_stat` block) print in full to the
# terminal/log, but their TSV row collapses newlines/tabs to spaces so
# summary.tsv stays one-row-per-emit and machine-parseable.
_tsv() { printf '%s\t%s\t%s\n' "$1" "$SCRIPT_SECTION" "$(printf '%s' "$2" | tr '\n\t' '  ')" >> "$TSV"; }
pass() { printf "${C_PASS}[PASS]${C_RST} %s\n" "$*"; _tsv PASS "$*"; }
warn() { printf "${C_WARN}[WARN]${C_RST} %s\n" "$*"; _tsv WARN "$*"; }
fail() { printf "${C_FAIL}[FAIL]${C_RST} %s\n" "$*"; _tsv FAIL "$*"; }
info() { printf "${C_INFO}[INFO]${C_RST} %s\n" "$*"; _tsv INFO "$*"; }
section() { printf "\n${C_SECT}== %s ==${C_RST}\n" "$*"; _tsv SECTION "$*"; }

# ── Guards ────────────────────────────────────────────────────────────────────
require_tool() {
  if ! command -v "$1" &>/dev/null; then
    warn "Tool not found: $1 (skipping checks that require it)"
    return 1
  fi
  return 0
}

require_sudo() {
  if [[ "$EUID" -ne 0 ]]; then
    warn "Not running as root — skipping privileged check (re-run with sudo for full results)"
    return 1
  fi
  return 0
}

# ── Bounded execution (macOS ships no `timeout`) ──────────────────────────────
# run_bounded <seconds> <cmd...> — run cmd, killing it after <seconds>. Used to
# cap commands that can stall without Full Disk Access (e.g. `sfltool dumpbtm`).
run_bounded() {
  local secs="$1"; shift
  "$@" &
  local cmd_pid=$!
  ( sleep "$secs"; kill -TERM "$cmd_pid" 2>/dev/null ) &
  local killer=$!
  wait "$cmd_pid" 2>/dev/null
  local rc=$?
  kill -TERM "$killer" 2>/dev/null
  wait "$killer" 2>/dev/null
  return "$rc"
}

# ── Benchmark helper: keep the machine awake for the duration ─────────────────
caffeinate_start() { caffeinate -i & CAFF_PID=$!; }
caffeinate_stop() {
  if [[ -n "${CAFF_PID:-}" ]]; then
    kill "$CAFF_PID" 2>/dev/null || true
    unset CAFF_PID
  fi
}
