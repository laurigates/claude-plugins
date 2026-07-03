#!/usr/bin/env bash
# diag/cpu.sh — CPU & thermal diagnostics for Apple Silicon.
export SCRIPT_SECTION="diag-cpu"
# shellcheck disable=SC1091
source "$(dirname "$0")/../lib/common.sh"

LOG="${RUN_DIR}/cpu_diag.txt"
exec > >(tee "$LOG") 2>&1

# ── CPU topology ──────────────────────────────────────────────────────────────
section "CPU Topology"
info "Model: $(sysctl -n machdep.cpu.brand_string 2>/dev/null || sysctl -n hw.model)"
info "Physical CPUs: $(sysctl -n hw.physicalcpu)"
info "Logical CPUs:  $(sysctl -n hw.logicalcpu)"
info "P-cores:       $(sysctl -n hw.perflevel0.physicalcpu 2>/dev/null || echo 'n/a')"
info "E-cores:       $(sysctl -n hw.perflevel1.physicalcpu 2>/dev/null || echo 'n/a')"
info "L2 cache:      $(sysctl -n hw.l2cachesize 2>/dev/null | awk '{printf "%.0f MB\n", $1/1048576}' || echo 'n/a')"
info "Page size:     $(sysctl -n hw.pagesize) bytes"
pass "CPU topology collected"

# ── Power mode ────────────────────────────────────────────────────────────────
section "Power Mode"
if require_tool pmset; then
  pmset_out="$(pmset -g)"
  info "pmset summary:"
  echo "$pmset_out" | head -20
  # Low Power Mode reports as `lowpowermode 1`; the `powermode` key is the
  # current (normal/automatic/high) mode and is NOT a Low Power Mode signal.
  if echo "$pmset_out" | grep -qE 'lowpowermode[[:space:]]+1'; then
    warn "Low Power Mode is active (lowpowermode=1) — may limit CPU performance"
  else
    pass "Low Power Mode is not active"
  fi
fi

# ── Top CPU consumers ─────────────────────────────────────────────────────────
section "Top CPU Consumers"
top_out="$(ps -eo pid,pcpu,comm -r 2>/dev/null | head -21)"
info "Top 20 processes by CPU%:"
echo "$top_out"
while IFS= read -r line; do
  cpu="$(echo "$line" | awk '{print $2}' | cut -d. -f1)"
  comm="$(echo "$line" | awk '{print $3}')"
  [[ "$cpu" =~ ^[0-9]+$ ]] || continue
  if [[ "$comm" == kernel_task ]] || [[ "$comm" == launchd ]]; then continue; fi
  if (( cpu >= CPU_PROC_FAIL_PCT )); then
    fail "Process $comm using ${cpu}% CPU (>= ${CPU_PROC_FAIL_PCT}%)"
  elif (( cpu >= CPU_PROC_WARN_PCT )); then
    warn "Process $comm using ${cpu}% CPU (>= ${CPU_PROC_WARN_PCT}%)"
  fi
done < <(echo "$top_out" | tail -n +2)

# ── Power & thermals: macmon first (sudo-free), powermetrics fallback ─────────
# macmon reads the same per-cluster power/temp counters as powermetrics via a
# private IOReport API, WITHOUT sudo. Prefer it; fall back to sudo powermetrics.
section "Power & Thermals"
power_covered=0
if require_tool macmon && require_tool jq; then
  info "Sampling macmon (sudo-free)…"
  mm="$(macmon pipe -s 1 2>/dev/null | tail -1 || true)"
  if [[ -n "$mm" ]]; then
    cpu_w="$(echo "$mm" | jq -r '.cpu_power // empty' 2>/dev/null)"
    gpu_w="$(echo "$mm" | jq -r '.gpu_power // empty' 2>/dev/null)"
    cpu_temp="$(echo "$mm" | jq -r '.temp.cpu_temp_avg // empty' 2>/dev/null)"
    [[ -n "$gpu_w" ]] && info "GPU power: ${gpu_w} W"
    [[ -n "$cpu_temp" ]] && info "CPU temp (avg): ${cpu_temp} C"
    if [[ -n "$cpu_w" ]]; then
      cpu_int="${cpu_w%.*}"
      if (( cpu_int >= CPU_POWER_FAIL_W )); then
        fail "CPU Power ${cpu_w}W >= ${CPU_POWER_FAIL_W}W (macmon)"
      elif (( cpu_int >= CPU_POWER_WARN_W )); then
        warn "CPU Power ${cpu_w}W >= ${CPU_POWER_WARN_W}W (macmon)"
      else
        pass "CPU Power ${cpu_w}W nominal (macmon)"
      fi
      power_covered=1
    fi
  else
    info "macmon produced no sample — falling back to powermetrics"
  fi
else
  info "macmon not installed — install sudo-free with: brew install macmon jq"
fi

# ── powermetrics (sudo only) — CPU power fallback + thermal pressure ──────────
# Thermal pressure is a powermetrics-only signal (macmon does not expose it), so
# this block runs under sudo even when macmon already covered CPU power.
section "Thermal Pressure (requires sudo)"
if require_sudo; then
  if require_tool powermetrics; then
    pm_out="$(sudo powermetrics --samplers cpu_power,thermal -n 1 -i 1000 2>/dev/null)"
    info "powermetrics output:"
    echo "$pm_out"
    if (( power_covered == 0 )); then
      cpu_w="$(echo "$pm_out" | grep -i "CPU Power" | head -1 | grep -o '[0-9.]*' | head -1)"
      if [[ -n "$cpu_w" ]]; then
        cpu_int="${cpu_w%.*}"
        if (( cpu_int >= CPU_POWER_FAIL_W )); then
          fail "CPU Power ${cpu_w}W >= ${CPU_POWER_FAIL_W}W (powermetrics)"
        elif (( cpu_int >= CPU_POWER_WARN_W )); then
          warn "CPU Power ${cpu_w}W >= ${CPU_POWER_WARN_W}W (powermetrics)"
        else
          pass "CPU Power ${cpu_w}W nominal (powermetrics)"
        fi
      fi
    fi
    pressure="$(echo "$pm_out" | grep -i "thermal pressure" | head -1 | awk -F: '{print $2}' | xargs)"
    case "${pressure,,}" in
      nominal)  pass "Thermal pressure: Nominal" ;;
      moderate) warn "Thermal pressure: Moderate" ;;
      heavy|*)  [[ -n "$pressure" ]] && fail "Thermal pressure: $pressure" ;;
    esac
  fi
fi

info "CPU diagnostics complete -> $LOG"
