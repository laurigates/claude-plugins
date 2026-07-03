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
  WRITE_START="$(now_ms)"
  dd if=/dev/zero of="$TESTFILE" bs=1m count="$TEST_SIZE_MB" conv=sync 2>&1
  WRITE_END="$(now_ms)"

  kill "$IOSTAT_PID" 2>/dev/null || true
  info "iostat during write:"
  cat "$IOSTAT_LOG" 2>/dev/null || true

  write_ms=$(( WRITE_END - WRITE_START ))
  write_ms=$(( write_ms > 0 ? write_ms : 1 ))
  write_mbs=$(( TEST_SIZE_MB * 1000 / write_ms ))
  info "Write: ${TEST_SIZE_MB} MB in ${write_ms}ms"
  score_hib bench_nvme_write_mbs "Sequential write" "$write_mbs" " MB/s"
else
  warn "dd or iostat not available — skipping write benchmark"
fi

# ── Sequential read ───────────────────────────────────────────────────────────
section "Sequential Read (${TEST_SIZE_MB} MB)"
if [[ -f "$TESTFILE" ]] && require_tool dd; then
  sync
  info "Reading ${TEST_SIZE_MB} MB via dd…"
  READ_START="$(now_ms)"
  dd if="$TESTFILE" of=/dev/null bs=1m 2>&1
  READ_END="$(now_ms)"

  read_ms=$(( READ_END - READ_START ))
  read_ms=$(( read_ms < 1 ? 1 : read_ms ))
  read_mbs=$(( TEST_SIZE_MB * 1000 / read_ms ))
  info "Read: ${TEST_SIZE_MB} MB in ${read_ms}ms"
  score_hib bench_nvme_read_mbs "Sequential read" "$read_mbs" " MB/s"
else
  warn "Test file not available — skipping read benchmark"
fi

info "Disk benchmarks complete -> $LOG"
