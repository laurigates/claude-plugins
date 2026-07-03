#!/usr/bin/env bash
# Portable regression checks for the macos-performance-benchmark suite.
# Runs on any platform (Linux CI included) — it never executes the Darwin-only
# diagnostics, only static invariants that guard the port's key fixes.
set -uo pipefail

DIR="$(cd "$(dirname "$0")/.." && pwd)"
fails=0
check() { if eval "$2"; then echo "PASS: $1"; else echo "FAIL: $1"; fails=$((fails+1)); fi; }

# 1. Every script parses.
for f in "$DIR"/run.sh "$DIR"/config.sh "$DIR"/lib/common.sh "$DIR"/report/generate.sh "$DIR"/diag/*.sh "$DIR"/bench/*.sh; do
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

# 8. Thresholds are env-overridable (not machine-locked).
check "thresholds are MACOS_PERF_* overridable" "grep -q 'MACOS_PERF_AES_WARN_MBS' '$DIR/config.sh'"

echo "---"
if (( fails == 0 )); then echo "ALL PASS"; exit 0; else echo "$fails FAILED"; exit 1; fi
