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
    aes_mbs="$(ossl_mbs "$aes_16k")"
    score_hib bench_aes_mbs "AES-256-CBC @16KB" "$aes_mbs" " MB/s"
  fi

  sha_line="$(echo "$ssl_out" | grep "^sha256 " | tail -1 || true)"
  if [[ -n "$sha_line" ]]; then
    sha_16k="$(echo "$sha_line" | awk '{print $NF}')"
    sha_mbs="$(ossl_mbs "$sha_16k")"
    score_hib bench_sha_mbs "SHA-256 @16KB" "$sha_mbs" " MB/s"
  fi
else
  warn "openssl not found — skipping OpenSSL benchmarks"
fi

# ── Python single-core ────────────────────────────────────────────────────────
section "Python Single-Core"
if require_tool python3; then
  info "Running single-core Python math benchmark…"
  py_ms="$(python3 -c "
import math, time
t = time.perf_counter()
sum(math.sqrt(i) * math.pi for i in range(10_000_001))
print(int((time.perf_counter() - t) * 1000))
")"
  info "Single-core wall time: ${py_ms} ms"
  score_lob bench_py_single_ms "Single-core Python" "$py_ms" " ms"
else
  warn "python3 not found — skipping Python benchmark"
fi

# ── Python all-core parallel ──────────────────────────────────────────────────
section "Python All-Core Parallel (${NCPU} CPUs)"
if require_tool python3; then
  info "Running all-core Python benchmark…"
  start_ms="$(now_ms)"
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
    # Force 'fork': macOS defaults to 'spawn', which re-imports __main__ and
    # cannot resolve a stdin-fed script (FileNotFoundError on '<stdin>').
    with multiprocessing.get_context('fork').Pool(ncpu) as pool:
        results = pool.map(worker, ranges)
    elapsed = time.time() - t
    print(f'All-core result: {sum(results):.2f}  Time: {elapsed:.2f}s  CPUs: {ncpu}')
PYEOF
  end_ms="$(now_ms)"
  mc_ms=$(( end_ms - start_ms ))
  info "All-core wall time: ${mc_ms} ms"
  score_lob bench_py_allcore_ms "All-core Python (${NCPU} CPUs)" "$mc_ms" " ms"
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
  if [[ -n "$mc_16k" ]]; then
    mc_mbs="$(ossl_mbs "$mc_16k")"
    # The absolute multi-core throughput IS scored — it self-calibrates against
    # this machine's own baseline, so it carries no cross-topology assumption.
    score_hib bench_aes_mc_mbs "AES-256-CBC multi-core (${NCPU} threads)" "$mc_mbs" " MB/s"
    # The scaling *ratio* is reported only — see report_scaling() (issue #2183).
    if [[ -n "${aes_16k:-}" ]]; then
      sc_mbs="$(ossl_mbs "$aes_16k")"
      report_scaling "$mc_mbs" "$sc_mbs" "$NCPU"
    else
      info "Single-core AES baseline unavailable — scaling efficiency not computed"
    fi
  else
    info "Multi-core AES throughput could not be parsed from openssl output"
    pass "OpenSSL multi-thread completed"
  fi
fi

info "CPU benchmarks complete -> $LOG"
