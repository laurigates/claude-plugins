#!/usr/bin/env bash
# bench/memory.sh — Memory bandwidth & pressure benchmarks.
export SCRIPT_SECTION="bench-memory"
# shellcheck disable=SC1091
source "$(dirname "$0")/../lib/common.sh"

LOG="${RUN_DIR}/memory_bench.txt"
exec > >(tee "$LOG") 2>&1

TMPFILE="$(mktemp /tmp/macos-perf-mem.XXXXXX)"
caffeinate_start
trap 'caffeinate_stop; rm -f "$TMPFILE"' EXIT

# ── Python 512 MB sequential bandwidth ────────────────────────────────────────
section "Python Memory Bandwidth (512 MB)"
if require_tool python3; then
  info "Allocating 512 MB, writing, strided read…"
  python3 - <<'PYEOF'
import time, array

SIZE = 512 * 1024 * 1024  # 512 MB
ELEMENT = 8  # bytes per float (double)
N = SIZE // ELEMENT
STRIDE = 64  # cache line stride in elements

buf = array.array('d', [0.0] * N)

t0 = time.perf_counter()
for i in range(N):
    buf[i] = float(i)
t1 = time.perf_counter()
write_bw = SIZE / (t1 - t0) / 1e9
print(f"Sequential write: {write_bw:.2f} GB/s")

t0 = time.perf_counter()
s = 0.0
for i in range(0, N, STRIDE):
    s += buf[i]
t1 = time.perf_counter()
read_bw = (N // STRIDE * ELEMENT) / (t1 - t0) / 1e6
print(f"Strided read: {read_bw:.0f} MB/s  (checksum: {s:.0f})")
PYEOF
  pass "Python memory bandwidth test complete"
fi

# ── dd memory copy benchmark ──────────────────────────────────────────────────
section "Memory Copy via dd (1 GB)"
if require_tool dd; then
  info "Writing 1 GB via /dev/urandom…"
  WRITE_START="$(date +%s)"
  dd if=/dev/urandom of="$TMPFILE" bs=1m count=1024 2>&1
  WRITE_END="$(date +%s)"
  write_s=$(( WRITE_END - WRITE_START ))
  write_s=$(( write_s < 1 ? 1 : write_s ))

  info "Reading 1 GB back…"
  READ_START="$(date +%s)"
  dd if="$TMPFILE" of=/dev/null bs=1m 2>&1
  READ_END="$(date +%s)"
  read_s=$(( READ_END - READ_START ))
  read_s=$(( read_s < 1 ? 1 : read_s ))

  read_gbs=$(( 1024 / read_s ))
  info "Read back: ~${read_gbs} GB/s (${read_s}s for 1 GB)"
  if (( read_gbs >= DD_READ_WARN_GBS )); then
    pass "dd read-back: ~${read_gbs} GB/s"
  else
    warn "dd read-back: ~${read_gbs} GB/s < ${DD_READ_WARN_GBS} GB/s"
  fi
fi

# ── 16 GB allocation pressure test ────────────────────────────────────────────
section "16 GB Allocation Pressure"
if require_tool python3 && require_tool memory_pressure; then
  pre_pressure="$(memory_pressure 2>/dev/null | grep "System-wide memory free percentage" | grep -o '[0-9]*%' || echo "?%")"
  info "Memory free before: $pre_pressure"

  info "Allocating 16 GB in Python…"
  python3 - <<'PYEOF' &
import time, array
N = (16 * 1024 * 1024 * 1024) // 8  # 16 GB as float64
print("Allocating...", flush=True)
buf = array.array('d', bytes(N * 8))
print("Writing...", flush=True)
for i in range(0, N, 65536):
    buf[i] = float(i)
print("Done. Holding 5s...", flush=True)
time.sleep(5)
print("Released.", flush=True)
PYEOF
  PY_PID=$!
  sleep 3
  post_pressure="$(memory_pressure 2>/dev/null | grep "System-wide memory free percentage" | grep -o '[0-9]*%' || echo "?%")"
  info "Memory free during: $post_pressure"

  pre_n="${pre_pressure//%/}"
  post_n="${post_pressure//%/}"
  if [[ "$pre_n" =~ ^[0-9]+$ ]] && [[ "$post_n" =~ ^[0-9]+$ ]]; then
    drop=$(( pre_n - post_n ))
    if (( drop > MEM_PRESSURE_DROP_WARN_PP )); then
      warn "Memory pressure increased significantly: ${pre_pressure} -> ${post_pressure} (${drop}pp drop)"
    else
      pass "Memory pressure stable: ${pre_pressure} -> ${post_pressure}"
    fi
  fi
  wait "$PY_PID" 2>/dev/null || true
fi

info "Memory benchmarks complete -> $LOG"
