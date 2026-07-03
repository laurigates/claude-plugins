#!/usr/bin/env bash
# lib/baseline.sh — self-calibrating per-machine benchmark baseline.
#
# Benchmarks have no repo-shipped thresholds (they'd be wrong on every machine
# but the author's). Instead the FIRST run records each score as this machine's
# baseline (best-seen), stored in $BASELINE_FILE; later runs compare against it
# and RATCHET the baseline up whenever a score improves. The verdict is relative
# degradation from best, so it tracks a machine drifting below its own peak.
#
# Sourced by lib/common.sh (which sets BASELINE_FILE and defines pass/warn/fail).

baseline_get() {  # key -> stored value, or empty
  [[ -f "$BASELINE_FILE" ]] || return 0
  grep -E "^$1=" "$BASELINE_FILE" 2>/dev/null | tail -1 | cut -d= -f2
}

baseline_set() {  # key value — upsert
  mkdir -p "$(dirname "$BASELINE_FILE")"
  local tmp
  tmp="$(mktemp)"
  [[ -f "$BASELINE_FILE" ]] && grep -vE "^$1=" "$BASELINE_FILE" > "$tmp" 2>/dev/null
  printf '%s=%s\n' "$1" "$2" >> "$tmp"
  mv "$tmp" "$BASELINE_FILE"
}

# score_hib — higher-is-better metric (throughput). Args: key label value unit
score_hib() {
  local key="$1" label="$2" val="$3" unit="$4"
  local base; base="$(baseline_get "$key")"
  if [[ -z "$base" || "$base" -le 0 ]]; then
    baseline_set "$key" "$val"
    pass "$label: ${val}${unit} (baseline established)"
    return
  fi
  if (( val > base )); then
    baseline_set "$key" "$val"
    pass "$label: ${val}${unit} — new best (was ${base}${unit})"
    return
  fi
  local warn_floor=$(( base * (100 - BENCH_WARN_DEGRADE) / 100 ))
  local fail_floor=$(( base * (100 - BENCH_FAIL_DEGRADE) / 100 ))
  if (( val >= warn_floor )); then
    pass "$label: ${val}${unit} (baseline ${base}${unit})"
  elif (( val >= fail_floor )); then
    warn "$label: ${val}${unit} — ${BENCH_WARN_DEGRADE}%+ below baseline ${base}${unit}"
  else
    fail "$label: ${val}${unit} — ${BENCH_FAIL_DEGRADE}%+ below baseline ${base}${unit}"
  fi
}

# score_lob — lower-is-better metric (wall time). Args: key label value unit
score_lob() {
  local key="$1" label="$2" val="$3" unit="$4"
  local base; base="$(baseline_get "$key")"
  if [[ -z "$base" || "$base" -le 0 ]]; then
    baseline_set "$key" "$val"
    pass "$label: ${val}${unit} (baseline established)"
    return
  fi
  if (( val < base )); then
    baseline_set "$key" "$val"
    pass "$label: ${val}${unit} — new best (was ${base}${unit})"
    return
  fi
  local warn_ceil=$(( base * (100 + BENCH_WARN_DEGRADE) / 100 ))
  local fail_ceil=$(( base * (100 + BENCH_FAIL_DEGRADE) / 100 ))
  if (( val <= warn_ceil )); then
    pass "$label: ${val}${unit} (baseline ${base}${unit})"
  elif (( val <= fail_ceil )); then
    warn "$label: ${val}${unit} — ${BENCH_WARN_DEGRADE}%+ above baseline ${base}${unit}"
  else
    fail "$label: ${val}${unit} — ${BENCH_FAIL_DEGRADE}%+ above baseline ${base}${unit}"
  fi
}
