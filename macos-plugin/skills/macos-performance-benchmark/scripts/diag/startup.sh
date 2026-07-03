#!/usr/bin/env bash
# diag/startup.sh — Startup items & background process diagnostics.
export SCRIPT_SECTION="diag-startup"
# shellcheck disable=SC1091
source "$(dirname "$0")/../lib/common.sh"

LOG="${RUN_DIR}/startup_diag.txt"
exec > >(tee "$LOG") 2>&1

# ── BTM (Background Task Manager) ─────────────────────────────────────────────
section "Background Task Manager (BTM)"
if require_tool sfltool; then
  # sfltool dumpbtm can stall indefinitely without Full Disk Access; bound it.
  btm_out="$(run_bounded 10 sfltool dumpbtm 2>/dev/null || true)"
  if [[ -n "$btm_out" ]]; then
    info "BTM items:"
    echo "$btm_out" | head -60
    btm_count="$(echo "$btm_out" | grep -c "enabled" 2>/dev/null || echo 0)"
    apple_count="$(echo "$btm_out" | grep "enabled" | grep -c "com\.apple\." 2>/dev/null || echo 0)"
    third_party=$(( btm_count - apple_count ))
    info "Estimated third-party BTM items (enabled): $third_party"
    if (( third_party > BTM_THIRD_PARTY_WARN )); then
      warn "BTM has $third_party enabled third-party items (> ${BTM_THIRD_PARTY_WARN})"
    else
      pass "BTM third-party items: $third_party"
    fi
  else
    info "sfltool dumpbtm returned no output (may require full disk access)"
  fi
else
  info "sfltool not available — skipping BTM check"
fi

# ── LaunchAgents / LaunchDaemons ──────────────────────────────────────────────
section "Launch Items"
count_plist_dir() {
  local dir="$1"
  if [[ -d "$dir" ]]; then
    find "$dir" -maxdepth 1 -name "*.plist" 2>/dev/null | wc -l | tr -d ' '
  else
    echo 0
  fi
}
sys_agents="$(count_plist_dir /Library/LaunchAgents)"
sys_daemons="$(count_plist_dir /Library/LaunchDaemons)"
user_agents="$(count_plist_dir "${HOME}/Library/LaunchAgents")"
info "  /Library/LaunchAgents:        $sys_agents plists"
info "  /Library/LaunchDaemons:       $sys_daemons plists"
info "  ~/Library/LaunchAgents:       $user_agents plists"
total_launch=$(( sys_agents + sys_daemons + user_agents ))
info "  Combined total (third-party dir): $total_launch"
if (( total_launch > LAUNCH_ITEMS_WARN )); then
  warn "Combined LaunchAgents/Daemons: $total_launch (> ${LAUNCH_ITEMS_WARN})"
else
  pass "Combined LaunchAgents/Daemons: $total_launch"
fi

# ── Running launchctl services ────────────────────────────────────────────────
section "Running launchctl Services"
if require_tool launchctl; then
  all_services="$(launchctl list 2>/dev/null | wc -l | tr -d ' ')"
  third_party_services="$(launchctl list 2>/dev/null | grep -v "com\.apple\." | grep -cv "^PID")"
  info "Total launchctl entries: $all_services"
  info "Third-party (non-apple) services: $third_party_services"
  if (( third_party_services > LAUNCHCTL_FAIL )); then
    fail "Third-party launchctl services: $third_party_services (> ${LAUNCHCTL_FAIL})"
  elif (( third_party_services > LAUNCHCTL_WARN )); then
    warn "Third-party launchctl services: $third_party_services (> ${LAUNCHCTL_WARN})"
  else
    pass "Third-party launchctl services: $third_party_services"
  fi
  info "Non-apple services:"
  launchctl list 2>/dev/null | grep -v "com\.apple\." | grep -v "^PID" | head -40
fi

# ── Scheduled wakes ───────────────────────────────────────────────────────────
section "Scheduled Wakes"
if require_tool pmset; then
  sched="$(pmset -g sched 2>/dev/null || true)"
  if [[ -z "$sched" ]] || echo "$sched" | grep -q "No scheduled"; then
    pass "No scheduled wakes"
  else
    info "Scheduled wakes:"
    echo "$sched"
    wake_count="$(echo "$sched" | grep -ic "wake\|poweron" || true)"
    if (( wake_count > 0 )); then
      warn "Scheduled wakes found — review if more frequent than hourly"
    fi
  fi
fi

# ── Sleep assertions ──────────────────────────────────────────────────────────
section "Sleep Assertions"
if require_tool pmset; then
  assertions="$(pmset -g assertions 2>/dev/null || true)"
  info "Current assertions:"
  echo "$assertions"
  if echo "$assertions" | grep -q "PreventUserIdleSystemSleep.*1\|PreventSystemSleep.*1"; then
    warn "Something is asserting PreventSystemSleep — system may not sleep normally"
  else
    pass "No assertions preventing system sleep"
  fi
fi

info "Startup diagnostics complete -> $LOG"
