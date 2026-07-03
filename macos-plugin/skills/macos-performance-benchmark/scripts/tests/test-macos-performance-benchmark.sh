#!/usr/bin/env bash
# Portable regression checks for the macos-performance-benchmark suite.
# Runs on any platform (Linux CI included) — it never executes the Darwin-only
# diagnostics, only static invariants that guard the port's key fixes.
set -uo pipefail

DIR="$(cd "$(dirname "$0")/.." && pwd)"
fails=0
check() { if eval "$2"; then echo "PASS: $1"; else echo "FAIL: $1"; fails=$((fails+1)); fi; }

# 1. Every script parses.
for f in "$DIR"/run.sh "$DIR"/config.sh "$DIR"/lib/common.sh "$DIR"/lib/baseline.sh "$DIR"/report/generate.sh "$DIR"/diag/*.sh "$DIR"/bench/*.sh; do
  check "syntax: ${f##*/}" "bash -n '$f'"
done

# 2. run.sh keeps the Darwin platform guard.
check "run.sh has Darwin guard" "grep -q 'uname -s' '$DIR/run.sh' && grep -q 'refusing' '$DIR/run.sh'"

# 3. common.sh uses 'set -u' (not 'set -e'/pipefail — the SIGPIPE-141 fix).
check "common.sh uses 'set -u' only" "grep -Eq '^set -u\\b' '$DIR/lib/common.sh'"
check "common.sh does NOT re-enable pipefail" "! grep -Eq '^set .*pipefail' '$DIR/lib/common.sh'"

# 4. Emitters sanitize newlines into the TSV (one well-formed row per emit).
check "TSV emitter collapses newlines/tabs" "grep -q \"tr '\\\\\\\\n\\\\\\\\t'\" '$DIR/lib/common.sh'"

# 5. sfltool dumpbtm is bounded (the hang fix).
check "sfltool dumpbtm is bounded" "grep -q 'run_bounded' '$DIR/diag/startup.sh'"

# 6. Low Power Mode uses lowpowermode, not the powermode false positive.
check "LPM detection uses lowpowermode" "grep -q 'lowpowermode' '$DIR/diag/cpu.sh'"

# 7. macmon-first sudo-free power path is present.
check "macmon-first power path" "grep -q 'macmon pipe' '$DIR/diag/cpu.sh'"

# 8. Diagnostic thresholds are env-overridable (not machine-locked).
check "diag thresholds are MACOS_PERF_* overridable" "grep -q 'MACOS_PERF_RAM_MIN_GB' '$DIR/config.sh'"

# 9. Benchmarks are self-calibrating (baseline, not fixed thresholds).
check "baseline scorers exist" "grep -q 'score_hib' '$DIR/lib/baseline.sh' && grep -q 'score_lob' '$DIR/lib/baseline.sh'"
check "benches call the baseline scorer" "grep -q 'score_hib' '$DIR/bench/cpu.sh'"
check "no fixed bench MB/s thresholds remain" "! grep -q 'AES_FAIL_MBS' '$DIR/config.sh'"
check "degrade fractions configurable" "grep -q 'MACOS_PERF_BENCH_WARN_DEGRADE' '$DIR/config.sh'"
check "run.sh exposes baseline-show/reset" "grep -q 'baseline-show' '$DIR/run.sh' && grep -q 'baseline-reset' '$DIR/run.sh'"

# 10. Sub-second timing avoids BSD date %N; multiprocessing forces fork.
check "ms timing via now_ms (not date %N)" "grep -q 'now_ms' '$DIR/lib/common.sh' && ! grep -q 'date +%s%3N' '$DIR/bench/disk.sh'"
check "openssl unit helper present" "grep -q 'ossl_mbs' '$DIR/lib/common.sh'"
check "all-core pool forces fork start method" "grep -q \"get_context('fork')\" '$DIR/bench/cpu.sh'"

echo "---"
if (( fails == 0 )); then echo "ALL PASS"; exit 0; else echo "$fails FAILED"; exit 1; fi
