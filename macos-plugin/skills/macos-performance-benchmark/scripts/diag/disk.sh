#!/usr/bin/env bash
# diag/disk.sh — Disk & storage diagnostics.
export SCRIPT_SECTION="diag-disk"
# shellcheck disable=SC1091
source "$(dirname "$0")/../lib/common.sh"

LOG="${RUN_DIR}/disk_diag.txt"
exec > >(tee "$LOG") 2>&1

# ── SMART status ──────────────────────────────────────────────────────────────
section "SMART Status"
if require_tool diskutil; then
  smart="$(diskutil info disk0 2>/dev/null | grep "SMART Status" || echo "SMART Status: Unknown")"
  info "$smart"
  if echo "$smart" | grep -q "Verified"; then
    pass "SMART status: Verified"
  else
    fail "SMART status not Verified: $smart"
  fi
fi

# ── TRIM ──────────────────────────────────────────────────────────────────────
section "TRIM Support"
if require_tool system_profiler; then
  trim="$(system_profiler SPNVMeDataType 2>/dev/null | grep -i "TRIM" | head -1 || echo "")"
  info "TRIM: ${trim:-not found in SPNVMeDataType}"
  if echo "$trim" | grep -qi "Yes"; then
    pass "TRIM enabled"
  elif [[ -z "$trim" ]]; then
    info "TRIM status not found (may not apply to this storage type)"
  else
    warn "TRIM may not be enabled: $trim"
  fi
fi

# ── Disk space ────────────────────────────────────────────────────────────────
section "Disk Space"
df_out="$(df -H / 2>/dev/null)"
info "$df_out"
use_pct="$(echo "$df_out" | awk 'NR==2{gsub(/%/,"",$5); print $5}')"
avail="$(echo "$df_out" | awk 'NR==2{print $4}')"
if [[ -n "$use_pct" ]]; then
  free_pct=$(( 100 - use_pct ))
  if (( free_pct < DISK_FREE_FAIL_PCT )); then
    fail "Disk / free: ${free_pct}% (${avail} available) — critical"
  elif (( free_pct < DISK_FREE_WARN_PCT )); then
    warn "Disk / free: ${free_pct}% (${avail} available)"
  else
    pass "Disk / free: ${free_pct}% (${avail} available)"
  fi
fi

# ── Large files ───────────────────────────────────────────────────────────────
section "Large Files (> 1 GB in home)"
if require_tool mdfind; then
  large_files="$(mdfind -onlyin "$HOME" 'kMDItemFSSize > 1073741824' 2>/dev/null | head -50 || true)"
  if [[ -z "$large_files" ]]; then
    pass "No files > 1 GB found in home directory"
  else
    info "Files > 1 GB in ~:"
    any_huge=0
    while IFS= read -r f; do
      sz_bytes="$(stat -f%z "$f" 2>/dev/null || echo 0)"
      sz_gb=$(( sz_bytes / 1073741824 ))
      echo "  ${sz_gb}G  $f"
      if (( sz_gb >= LARGE_FILE_WARN_GB )); then
        warn "File >= ${LARGE_FILE_WARN_GB} GB: $f (${sz_gb} GB)"
        any_huge=1
      fi
    done <<< "$large_files"
    if (( any_huge == 0 )); then
      pass "No individual files >= ${LARGE_FILE_WARN_GB} GB found"
    fi
  fi
fi

# ── Spotlight ─────────────────────────────────────────────────────────────────
section "Spotlight"
if require_tool mdutil; then
  spotlight="$(mdutil -s / 2>/dev/null || echo "")"
  info "$spotlight"
  if echo "$spotlight" | grep -q "enabled"; then
    pass "Spotlight indexing enabled"
  else
    warn "Spotlight may be disabled or not indexed"
  fi
fi

# ── I/O activity baseline ─────────────────────────────────────────────────────
section "Disk I/O Baseline (3s)"
if require_tool iostat; then
  info "iostat disk0 (3 samples):"
  iostat -d disk0 -c 3 -w 1 2>/dev/null || iostat -d -c 3 2>/dev/null || true
  pass "I/O baseline collected"
fi

info "Disk diagnostics complete -> $LOG"
