#!/usr/bin/env bash
# diag/memory.sh — Memory & swap diagnostics.
export SCRIPT_SECTION="diag-memory"
# shellcheck disable=SC1091
source "$(dirname "$0")/../lib/common.sh"

LOG="${RUN_DIR}/memory_diag.txt"
exec > >(tee "$LOG") 2>&1

# ── Total RAM ─────────────────────────────────────────────────────────────────
section "RAM"
total_bytes="$(sysctl -n hw.memsize)"
total_gb=$(( total_bytes / 1073741824 ))
info "Total RAM: ${total_gb} GB"
if (( total_gb >= RAM_MIN_GB )); then
  pass "RAM: ${total_gb} GB installed"
else
  warn "RAM: ${total_gb} GB (less than ${RAM_MIN_GB} GB)"
fi

# ── Memory pressure ───────────────────────────────────────────────────────────
section "Memory Pressure"
if require_tool memory_pressure; then
  mp_out="$(memory_pressure 2>/dev/null)"
  info "$mp_out"
  free_pct="$(echo "$mp_out" | grep -i "System-wide memory free percentage" | grep -o '[0-9]*%' | tr -d '%')"
  if [[ -n "$free_pct" ]]; then
    if (( free_pct < MEM_FREE_FAIL_PCT )); then
      fail "Memory free: ${free_pct}% (< ${MEM_FREE_FAIL_PCT}%)"
    elif (( free_pct < MEM_FREE_WARN_PCT )); then
      warn "Memory free: ${free_pct}% (< ${MEM_FREE_WARN_PCT}%)"
    else
      pass "Memory free: ${free_pct}%"
    fi
  else
    info "Could not parse memory_pressure free percentage"
  fi
fi

# ── Swap ──────────────────────────────────────────────────────────────────────
section "Swap Usage"
swap_out="$(sysctl vm.swapusage 2>/dev/null)"
info "$swap_out"
swap_used="$(echo "$swap_out" | grep -o 'used = [0-9.]*' | awk '{print $3}')"
if [[ -n "$swap_used" ]]; then
  swap_used_int="${swap_used%.*}"
  if (( swap_used_int > 0 )); then
    warn "Swap in use: ${swap_used}M — notable on ${total_gb} GB system"
  else
    pass "No swap in use"
  fi
fi

# ── vm_stat wired % ───────────────────────────────────────────────────────────
section "Wired Memory"
vmstat_out="$(vm_stat 2>/dev/null)"
info "$vmstat_out"
page_size="$(sysctl -n hw.pagesize)"
pages_wired="$(echo "$vmstat_out" | grep "Pages wired down" | grep -o '[0-9]*')"
pages_total=$(( total_bytes / page_size ))
if [[ -n "$pages_wired" ]] && (( pages_total > 0 )); then
  wired_pct=$(( pages_wired * 100 / pages_total ))
  if (( wired_pct > WIRED_WARN_PCT )); then
    warn "Wired memory: ${wired_pct}% (> ${WIRED_WARN_PCT}%)"
  else
    pass "Wired memory: ${wired_pct}%"
  fi
fi

# ── Top RSS consumers ─────────────────────────────────────────────────────────
section "Top RSS Consumers"
ps_out="$(ps -eo pid,rss,comm -r 2>/dev/null | head -21)"
info "Top 20 processes by RSS:"
echo "$ps_out"
while IFS= read -r line; do
  rss_kb="$(echo "$line" | awk '{print $2}')"
  comm="$(echo "$line" | awk '{print $3}')"
  [[ "$rss_kb" =~ ^[0-9]+$ ]] || continue
  rss_gb=$(( rss_kb / 1048576 ))
  if (( rss_gb >= RSS_FAIL_GB )); then
    fail "Process $comm RSS: ${rss_gb} GB (>= ${RSS_FAIL_GB} GB)"
  elif (( rss_gb >= RSS_WARN_GB )); then
    warn "Process $comm RSS: ${rss_gb} GB (>= ${RSS_WARN_GB} GB)"
  fi
done < <(echo "$ps_out" | tail -n +2)

info "Memory diagnostics complete -> $LOG"
