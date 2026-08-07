#!/usr/bin/env bash
# Regression: multi-core scaling efficiency must never produce a verdict.
#
# Issue #2183 — bench/cpu.sh gated PASS/WARN on a 70% scaling-efficiency floor
# (MACOS_PERF_SCALING_WARN_PCT). That floor assumes symmetric cores; on Apple
# Silicon's P+E topology a healthy 10P+4E machine measures 24–27%, so the
# benchmark WARNed on every healthy asymmetric Mac. The metric is now emitted as
# an info line by report_scaling() and is structurally incapable of scoring.
#
# This is a SEMANTIC gate: it EXECUTES report_scaling() in a sandbox and asserts
# the emitted summary.tsv rows, rather than grepping for the fix's text. A
# syntactic pin would pass against a re-introduced floor spelled differently.
#
# Portable: report_scaling() and the emitters are pure shell, so this runs on
# Linux CI too. core_topology() degrades to empty where sysctl has no
# hw.perflevel* keys, which is exactly the Intel-Mac path.
#
# File-level (must precede the first command): assertions run through `eval` in
# check(), so shellcheck cannot see that $out and tsv_rows() are used.
# shellcheck disable=SC2034,SC2317,SC2329
set -uo pipefail

DIR="$(cd "$(dirname "$0")/.." && pwd)"
fails=0
check() { if eval "$2"; then echo "PASS: $1"; else echo "FAIL: $1"; fails=$((fails+1)); fi; }

SANDBOX="$(mktemp -d)"
if [ -z "${SANDBOX:-}" ] || [ ! -d "$SANDBOX" ]; then
  echo "FAIL: could not create sandbox dir" >&2
  exit 1
fi
trap 'rm -rf "$SANDBOX"' EXIT

# emit_in_sandbox <run-dir> <shell-snippet> — source lib/common.sh against the
# given run dir and execute the snippet. Stdout is returned; the run's
# summary.tsv is left in <run-dir> for row assertions. The run dir is passed in
# (not derived inside) because callers capture stdout in a command substitution,
# whose subshell cannot export a path back out.
emit_in_sandbox() {
  MACOS_PERF_RESULTS_DIR="${SANDBOX}/results" RUN_DIR="$1" \
    bash -c 'source "$1/lib/common.sh"; eval "$2"' _ "$DIR" "$2" 2>&1
}

tsv_rows() { awk -F'\t' -v s="$2" '$1 == s' "${1}/summary.tsv" 2>/dev/null | wc -l | tr -d ' '; }

# ── 1. The measured ratio is still reported, as INFO ──────────────────────────
# 336 / (100 * 14) = 24% — the value the issue measured on a real 10P+4E Mac.
asym_dir="$SANDBOX/asymmetric"
out="$(emit_in_sandbox "$asym_dir" 'report_scaling 336 100 14')"
check "asymmetric 24% is reported"            "printf '%s' \"\$out\" | grep -q '24%'"
check "asymmetric 24% is emitted as INFO"     "printf '%s' \"\$out\" | grep -q '\\[INFO\\]'"
check "asymmetric 24% writes exactly one row" "[ \"\$(awk 'END{print NR}' '$asym_dir/summary.tsv')\" = 1 ]"
check "asymmetric 24% row is INFO"            "[ \"\$(tsv_rows '$asym_dir' INFO)\" = 1 ]"
check "asymmetric 24% emits no WARN"          "[ \"\$(tsv_rows '$asym_dir' WARN)\" = 0 ]"
check "asymmetric 24% emits no FAIL"          "[ \"\$(tsv_rows '$asym_dir' FAIL)\" = 0 ]"

# ── 2. No input can make the metric score, in either direction ────────────────
worst_dir="$SANDBOX/worst"
out="$(emit_in_sandbox "$worst_dir" 'report_scaling 1 100 14')"   # 0% — worst case
check "0% scaling still emits no WARN"  "[ \"\$(tsv_rows '$worst_dir' WARN)\" = 0 ]"
check "0% scaling still emits no FAIL"  "[ \"\$(tsv_rows '$worst_dir' FAIL)\" = 0 ]"
check "0% scaling still reports INFO"   "[ \"\$(tsv_rows '$worst_dir' INFO)\" = 1 ]"

best_dir="$SANDBOX/best"
out="$(emit_in_sandbox "$best_dir" 'report_scaling 1300 100 14')"  # 92% — symmetric-like
check "92% scaling emits no PASS"       "[ \"\$(tsv_rows '$best_dir' PASS)\" = 0 ]"
check "92% scaling reports INFO"        "[ \"\$(tsv_rows '$best_dir' INFO)\" = 1 ]"

# ── 3. Guard integrity — the harness CAN record a WARN/PASS ───────────────────
# Without this, every "emits no WARN" assertion above would also pass against a
# broken sandbox that never wrote summary.tsv at all.
ctrl_dir="$SANDBOX/control"
out="$(emit_in_sandbox "$ctrl_dir" 'warn "synthetic warn"; pass "synthetic pass"')"
check "control: emitters do write WARN rows" "[ \"\$(tsv_rows '$ctrl_dir' WARN)\" = 1 ]"
check "control: emitters do write PASS rows" "[ \"\$(tsv_rows '$ctrl_dir' PASS)\" = 1 ]"

# ── 4. Degenerate inputs are silent, not crashes ──────────────────────────────
degen_dir="$SANDBOX/degenerate"
out="$(emit_in_sandbox "$degen_dir" 'report_scaling "" 100 14; report_scaling 336 0 14; report_scaling 336 abc 14')"
check "degenerate inputs emit nothing"       "[ -d '$degen_dir' ] && [ ! -s '$degen_dir/summary.tsv' ]"
check "degenerate inputs raise no bash error" "! printf '%s' \"\$out\" | grep -qiE 'unbound variable|syntax error'"

# ── 5. The removed floor stays removed ────────────────────────────────────────
check "config.sh defines no SCALING_WARN_PCT" \
  "! grep -Eq '^[[:space:]]*SCALING_WARN_PCT=' '$DIR/config.sh'"
check "bench/cpu.sh never reads SCALING_WARN_PCT" \
  "! grep -q 'SCALING_WARN_PCT' '$DIR/bench/cpu.sh'"
check "bench/cpu.sh scores nothing on scaling" \
  "! grep -Eq '(warn|pass|fail)[^#]*scaling' '$DIR/bench/cpu.sh'"
check "bench/cpu.sh delegates to report_scaling" \
  "grep -q 'report_scaling' '$DIR/bench/cpu.sh'"
check "report_scaling emits info only" \
  "! awk '/^report_scaling\\(\\)/,/^}/' '$DIR/lib/common.sh' | grep -Eq '^[[:space:]]*(warn|pass|fail) '"

echo "---"
if (( fails == 0 )); then echo "ALL PASS"; exit 0; else echo "$fails FAILED"; exit 1; fi
