#!/usr/bin/env bash
# bench/disk.sh — NVMe sequential read/write benchmarks.
export SCRIPT_SECTION="bench-disk"
# shellcheck disable=SC1091
source "$(dirname "$0")/../lib/common.sh"

LOG="${RUN_DIR}/disk_bench.txt"
exec > >(tee "$LOG") 2>&1

TESTFILE="$(mktemp /tmp/macos-perf-disk.XXXXXX)"
caffeinate_start
trap 'caffeinate_stop; rm -f "$TESTFILE"' EXIT

TEST_SIZE_MB="$DISK_TEST_SIZE_MB"

# ── Sequential write ──────────────────────────────────────────────────────────
section "Sequential Write (${TEST_SIZE_MB} MB)"
if require_tool dd && require_tool iostat; then
  info "Starting iostat monitoring in background…"
  IOSTAT_LOG="${RUN_DIR}/iostat_write.txt"
  iostat -d disk0 -c 20 -w 1 > "$IOSTAT_LOG" 2>&1 &
  IOSTAT_PID=$!

  info "Writing ${TEST_SIZE_MB} MB via dd…"
  WRITE_START="$(date +%s%3N)"  # ms
  dd if=/dev/zero of="$TESTFILE" bs=1m count="$TEST_SIZE_MB" conv=sync 2>&1
  WRITE_END="$(date +%s%3N)"

  kill "$IOSTAT_PID" 2>/dev/null || true
  info "iostat during write:"
  cat "$IOSTAT_LOG" 2>/dev/null || true

  write_ms=$(( WRITE_END - WRITE_START ))
  write_ms=$(( write_ms > 0 ? write_ms : 1 ))
  write_gbs_x10=$(( TEST_SIZE_MB * 10000 / write_ms ))  # 10x GB/s to avoid float
  write_gbs="${write_gbs_x10::-1}.${write_gbs_x10: -1}"

  info "Write: ${TEST_SIZE_MB} MB in ${write_ms}ms -> ~${write_gbs} GB/s"
  if (( write_gbs_x10 < DISK_WRITE_FAIL_GBS_X10 )); then
    fail "Sequential write: ~${write_gbs} GB/s (below fail threshold)"
  elif (( write_gbs_x10 < DISK_WRITE_WARN_GBS_X10 )); then
    warn "Sequential write: ~${write_gbs} GB/s (below warn threshold)"
  else
    pass "Sequential write: ~${write_gbs} GB/s"
  fi
else
  warn "dd or iostat not available — skipping write benchmark"
fi

# ── Sequential read ───────────────────────────────────────────────────────────
section "Sequential Read (${TEST_SIZE_MB} MB)"
if [[ -f "$TESTFILE" ]] && require_tool dd; then
  sync
  info "Reading ${TEST_SIZE_MB} MB via dd…"
  READ_START="$(date +%s%3N)"
  dd if="$TESTFILE" of=/dev/null bs=1m 2>&1
  READ_END="$(date +%s%3N)"

  read_ms=$(( READ_END - READ_START ))
  read_ms=$(( read_ms < 1 ? 1 : read_ms ))
  read_gbs_x10=$(( TEST_SIZE_MB * 10000 / read_ms ))
  read_gbs="${read_gbs_x10::-1}.${read_gbs_x10: -1}"

  info "Read: ${TEST_SIZE_MB} MB in ${read_ms}ms -> ~${read_gbs} GB/s"
  if (( read_gbs_x10 < DISK_READ_FAIL_GBS_X10 )); then
    fail "Sequential read: ~${read_gbs} GB/s (below fail threshold)"
  elif (( read_gbs_x10 < DISK_READ_WARN_GBS_X10 )); then
    warn "Sequential read: ~${read_gbs} GB/s (below warn threshold)"
  else
    pass "Sequential read: ~${read_gbs} GB/s"
  fi
else
  warn "Test file not available — skipping read benchmark"
fi

info "Disk benchmarks complete -> $LOG"
