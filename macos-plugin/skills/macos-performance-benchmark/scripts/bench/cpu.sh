#!/usr/bin/env bash
# bench/cpu.sh — CPU benchmarks (OpenSSL + Python).
export SCRIPT_SECTION="bench-cpu"
# shellcheck disable=SC1091
source "$(dirname "$0")/../lib/common.sh"

LOG="${RUN_DIR}/cpu_bench.txt"
exec > >(tee "$LOG") 2>&1

NCPU="$(sysctl -n hw.logicalcpu)"
caffeinate_start
trap 'caffeinate_stop' EXIT

# ── OpenSSL single-thread ─────────────────────────────────────────────────────
section "OpenSSL Single-Thread"
if require_tool openssl; then
  info "Running openssl speed (single-thread) — ~15s"
  ssl_out="$(openssl speed aes-256-cbc sha256 sha512 rsa2048 2>&1)"
  info "Results:"
  echo "$ssl_out"

  aes_line="$(echo "$ssl_out" | grep "aes-256-cbc" | tail -1 || true)"
  if [[ -n "$aes_line" ]]; then
    aes_16k="$(echo "$aes_line" | awk '{print $NF}')"
    aes_mbs="$(echo "$aes_16k" | awk '{printf "%.0f", $1/1048576}')"
    info "AES-256-CBC @16KB: ${aes_mbs} MB/s"
    if (( aes_mbs < AES_FAIL_MBS )); then
      fail "AES-256-CBC: ${aes_mbs} MB/s < ${AES_FAIL_MBS} MB/s threshold"
    elif (( aes_mbs < AES_WARN_MBS )); then
      warn "AES-256-CBC: ${aes_mbs} MB/s < ${AES_WARN_MBS} MB/s warn threshold"
    else
      pass "AES-256-CBC: ${aes_mbs} MB/s"
    fi
  fi

  sha_line="$(echo "$ssl_out" | grep "^sha256 " | tail -1 || true)"
  if [[ -n "$sha_line" ]]; then
    sha_16k="$(echo "$sha_line" | awk '{print $NF}')"
    sha_mbs="$(echo "$sha_16k" | awk '{printf "%.0f", $1/1048576}')"
    info "SHA-256 @16KB: ${sha_mbs} MB/s"
    if (( sha_mbs < SHA_FAIL_MBS )); then
      fail "SHA-256: ${sha_mbs} MB/s < ${SHA_FAIL_MBS} MB/s threshold"
    elif (( sha_mbs < SHA_WARN_MBS )); then
      warn "SHA-256: ${sha_mbs} MB/s < ${SHA_WARN_MBS} MB/s warn threshold"
    else
      pass "SHA-256: ${sha_mbs} MB/s"
    fi
  fi
else
  warn "openssl not found — skipping OpenSSL benchmarks"
fi

# ── Python single-core ────────────────────────────────────────────────────────
section "Python Single-Core"
if require_tool python3; then
  info "Running single-core Python math benchmark…"
  start_ts="$(date +%s)"
  python3 -c "
import math, time
t = time.time()
result = sum(math.sqrt(i) * math.pi for i in range(10_000_001))
elapsed = time.time() - t
print(f'Result: {result:.2f}  Time: {elapsed:.2f}s')
"
  end_ts="$(date +%s)"
  elapsed=$(( end_ts - start_ts ))
  info "Wall time: ${elapsed}s"
  if (( elapsed > PY_SINGLE_FAIL_S )); then
    fail "Single-core Python: ${elapsed}s > ${PY_SINGLE_FAIL_S}s"
  elif (( elapsed >= PY_SINGLE_WARN_S )); then
    warn "Single-core Python: ${elapsed}s (>= ${PY_SINGLE_WARN_S}s)"
  else
    pass "Single-core Python: ${elapsed}s < ${PY_SINGLE_WARN_S}s"
  fi
else
  warn "python3 not found — skipping Python benchmark"
fi

# ── Python all-core parallel ──────────────────────────────────────────────────
section "Python All-Core Parallel (${NCPU} CPUs)"
if require_tool python3; then
  info "Running all-core Python benchmark…"
  start_ts="$(date +%s)"
  python3 - <<PYEOF
import math, time, multiprocessing

def worker(args):
    start, end = args
    return sum(math.sqrt(i) * math.pi for i in range(start, end))

if __name__ == '__main__':
    ncpu = ${NCPU}
    total = 10_000_001
    chunk = total // ncpu
    ranges = [(i * chunk, min((i + 1) * chunk, total)) for i in range(ncpu)]
    t = time.time()
    with multiprocessing.Pool(ncpu) as pool:
        results = pool.map(worker, ranges)
    elapsed = time.time() - t
    print(f'All-core result: {sum(results):.2f}  Time: {elapsed:.2f}s  CPUs: {ncpu}')
PYEOF
  end_ts="$(date +%s)"
  mc_elapsed=$(( end_ts - start_ts ))
  info "All-core wall time: ${mc_elapsed}s"
  pass "All-core benchmark: ${mc_elapsed}s (${NCPU} CPUs)"
else
  warn "python3 not found — skipping all-core benchmark"
fi

# ── OpenSSL multi-thread ──────────────────────────────────────────────────────
section "OpenSSL Multi-Thread (${NCPU} cores)"
if require_tool openssl; then
  info "Running openssl speed -multi ${NCPU} aes-256-cbc — ~15s"
  mc_ssl="$(openssl speed -multi "$NCPU" aes-256-cbc 2>&1)"
  echo "$mc_ssl"
  mc_16k="$(echo "$mc_ssl" | grep "aes-256-cbc" | tail -1 | awk '{print $NF}')"
  if [[ -n "$mc_16k" ]] && [[ -n "${aes_16k:-}" ]]; then
    mc_mbs="$(echo "$mc_16k" | awk '{printf "%.0f", $1/1048576}')"
    sc_mbs="$(echo "${aes_16k}" | awk '{printf "%.0f", $1/1048576}')"
    if (( sc_mbs > 0 )); then
      scaling=$(( mc_mbs * 100 / (sc_mbs * NCPU) ))
      info "Multi-core AES-256-CBC: ${mc_mbs} MB/s  Scaling efficiency: ${scaling}%"
      if (( scaling < SCALING_WARN_PCT )); then
        warn "Multi-core scaling efficiency: ${scaling}% < ${SCALING_WARN_PCT}%"
      else
        pass "Multi-core scaling efficiency: ${scaling}%"
      fi
    fi
  else
    info "Multi-core AES: ${mc_16k:-unknown} (single-core baseline not available for comparison)"
    pass "OpenSSL multi-thread completed"
  fi
fi

info "CPU benchmarks complete -> $LOG"
