#!/usr/bin/env bash
# macOS Incident Postmortem — deterministic signal gathering + reboot/hang classifier.
#
# Extracts the mechanical procedure of the macos-incident-postmortem skill
# (issue #1557): reboot-vs-hang signal detection, DiagnosticReports timeline,
# per-category report counts, CPU-event offender histogram, jetsam victim list,
# and the fixed reboot/hang decision tree. The model still reads panic
# backtraces, names suspect kexts, and writes the narrative — those are judgment,
# not procedure, and stay with the agent.
#
# Every macOS-only system probe sits behind an injectable seam so this runs
# offline on Linux CI against PLANTED fixture files:
#   --reports-dir <path>   DiagnosticReports source (repeatable). Defaults to
#                          /Library/Logs/DiagnosticReports and
#                          ~/Library/Logs/DiagnosticReports.
#   MACOS_PM_UNAME         override `uname -s` (default: real uname).
#   MACOS_PM_LAST_REBOOT   command emitting `last reboot`-style lines.
#   MACOS_PM_LAST_SHUTDOWN command emitting `last shutdown`-style lines.
#   MACOS_PM_BOOTTIME      kern.boottime unix epoch (overrides sysctl probe).
#   MACOS_PM_INCIDENT_EPOCH  unix epoch of the incident time T (optional; enables
#                            the reboot-vs-hang classifier when boottime is known).
#
# Emits the structured KEY=value / STATUS= convention
# (.claude/rules/structured-script-output.md).
#
# Usage:
#   macos-incident-postmortem.sh [--home-dir <path>] [--project-dir <path>]
#                                [--reports-dir <path> ...] [--verbose]
set -uo pipefail

home_dir=""
project_dir=""
verbose_mode=false
reports_dirs=()

while [ $# -gt 0 ]; do
  case "$1" in
    --home-dir) home_dir="$2"; shift 2 ;;
    --project-dir) project_dir="$2"; shift 2 ;;
    --reports-dir) reports_dirs+=("$2"); shift 2 ;;
    --verbose) verbose_mode=true; shift ;;
    *) shift ;;
  esac
done

: "${home_dir:=$HOME}"
: "${project_dir:=$(pwd)}"

# Default report sources when none injected.
if [ "${#reports_dirs[@]}" -eq 0 ]; then
  reports_dirs=(
    "/Library/Logs/DiagnosticReports"
    "${home_dir}/Library/Logs/DiagnosticReports"
  )
fi

echo "=== MACOS INCIDENT POSTMORTEM ==="

issue_count=0
check_status="OK"
issues_list=""

add_issue() {
  # $1 severity, $2 type, $3 message
  issues_list="${issues_list}  - SEVERITY=$1 TYPE=$2 MSG=$3\n"
  issue_count=$((issue_count + 1))
  case "$1" in
    ERROR) check_status="ERROR" ;;
    WARN) [ "$check_status" = "OK" ] && check_status="WARN" ;;
  esac
}

# --- Platform note (do not hard-fail offline; CI runs on Linux) -------------
host_uname="${MACOS_PM_UNAME:-$(uname -s 2>/dev/null || echo unknown)}"
echo "HOST_UNAME=${host_uname}"
if [ "$host_uname" != "Darwin" ]; then
  echo "PLATFORM=non-darwin"
  add_issue WARN non_darwin "not running on Darwin; system probes inert, scanning injected report dirs only"
fi

# --- Resolve which report dirs actually exist ------------------------------
present_dirs=()
for d in "${reports_dirs[@]}"; do
  if [ -d "$d" ]; then
    present_dirs+=("$d")
    [ "$verbose_mode" = true ] && echo "REPORTS_DIR_PRESENT=${d}"
  else
    [ "$verbose_mode" = true ] && echo "REPORTS_DIR_ABSENT=${d}"
  fi
done

echo "REPORTS_DIRS_PRESENT=${#present_dirs[@]}"

if [ "${#present_dirs[@]}" -eq 0 ]; then
  # Degrade gracefully — a missing source is a known, non-fatal state.
  echo "REPORT_COUNT=0"
  add_issue WARN no_reports_dir "no DiagnosticReports directory found; cannot reconstruct timeline from report files"
fi

# --- Category counts + CPU histogram + jetsam list -------------------------
# Walk each present dir once, classify by filename suffix.
report_total=0
panic_count=0
hang_count=0
spindump_count=0
cpu_count=0
wakeups_count=0
diskwrites_count=0
jetsam_count=0
crash_count=0
ips_count=0

# CPU offender histogram: process -> count.
declare -A cpu_offenders=()
# Jetsam victim histogram from "name":"<proc>" lines in JetsamEvent files.
declare -A jetsam_victims=()

latest_panic=""
latest_panic_epoch=0
latest_hang=""
latest_hang_epoch=0

# Portable mtime epoch (BSD stat -f vs GNU stat -c).
file_mtime_epoch() {
  stat -f '%m' "$1" 2>/dev/null || stat -c '%Y' "$1" 2>/dev/null || echo 0
}

for d in "${present_dirs[@]}"; do
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    base="${f##*/}"
    report_total=$((report_total + 1))
    case "$base" in
      *.panic)
        panic_count=$((panic_count + 1))
        e="$(file_mtime_epoch "$f")"
        if [ "$e" -ge "$latest_panic_epoch" ]; then
          latest_panic_epoch="$e"; latest_panic="$f"
        fi
        ;;
      *.spindump.txt)
        spindump_count=$((spindump_count + 1))
        ;;
      *.hang)
        hang_count=$((hang_count + 1))
        e="$(file_mtime_epoch "$f")"
        if [ "$e" -ge "$latest_hang_epoch" ]; then
          latest_hang_epoch="$e"; latest_hang="$f"
        fi
        ;;
      *.cpu_resource.diag)
        cpu_count=$((cpu_count + 1))
        # Offender = leading token before the first '-' in the filename.
        proc="${base%%-*}"
        cpu_offenders["$proc"]=$(( ${cpu_offenders["$proc"]:-0} + 1 ))
        ;;
      *.wakeups_resource.diag)
        wakeups_count=$((wakeups_count + 1))
        ;;
      *.diskwrites_resource.diag)
        diskwrites_count=$((diskwrites_count + 1))
        ;;
      JetsamEvent-*)
        jetsam_count=$((jetsam_count + 1))
        # Collect victim process names from "name":"<proc>" occurrences.
        while IFS= read -r victim; do
          [ -n "$victim" ] || continue
          jetsam_victims["$victim"]=$(( ${jetsam_victims["$victim"]:-0} + 1 ))
        done < <(grep -hoE '"name"[[:space:]]*:[[:space:]]*"[^"]+"' "$f" 2>/dev/null \
                   | sed -E 's/.*"name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')
        ;;
      *.crash)
        crash_count=$((crash_count + 1))
        ;;
      *.ips)
        ips_count=$((ips_count + 1))
        ;;
    esac
  done < <(find "$d" -type f 2>/dev/null)
done

echo "REPORT_COUNT=${report_total}"
echo "PANIC_COUNT=${panic_count}"
echo "HANG_COUNT=${hang_count}"
echo "SPINDUMP_COUNT=${spindump_count}"
echo "CPU_RESOURCE_COUNT=${cpu_count}"
echo "WAKEUPS_RESOURCE_COUNT=${wakeups_count}"
echo "DISKWRITES_RESOURCE_COUNT=${diskwrites_count}"
echo "JETSAM_COUNT=${jetsam_count}"
echo "CRASH_COUNT=${crash_count}"
echo "IPS_COUNT=${ips_count}"

[ -n "$latest_panic" ] && echo "LATEST_PANIC=${latest_panic}"
[ -n "$latest_hang" ] && echo "LATEST_HANG=${latest_hang}"

# CPU offender histogram (descending by count). One row per offender.
if [ "${#cpu_offenders[@]}" -gt 0 ]; then
  echo "CPU_OFFENDERS:"
  for proc in "${!cpu_offenders[@]}"; do
    printf '%d\t%s\n' "${cpu_offenders[$proc]}" "$proc"
  done | sort -rn | while IFS=$'\t' read -r cnt proc; do
    echo "  - PROC=${proc} COUNT=${cnt}"
  done
fi

# Jetsam victim histogram (descending by count).
if [ "${#jetsam_victims[@]}" -gt 0 ]; then
  echo "JETSAM_VICTIMS:"
  for victim in "${!jetsam_victims[@]}"; do
    printf '%d\t%s\n' "${jetsam_victims[$victim]}" "$victim"
  done | sort -rn | while IFS=$'\t' read -r cnt victim; do
    echo "  - PROC=${victim} COUNT=${cnt}"
  done
fi

# --- Reboot-vs-hang signal detection ---------------------------------------
# Boot time: injected epoch wins; else parse `sysctl -n kern.boottime`.
boot_epoch=""
if [ -n "${MACOS_PM_BOOTTIME:-}" ]; then
  boot_epoch="$MACOS_PM_BOOTTIME"
elif [ "$host_uname" = "Darwin" ] && command -v sysctl >/dev/null 2>&1; then
  # sysctl emits e.g. "{ sec = 1714723200, usec = 0 } Tue Apr 22 ..."
  boot_raw="$(sysctl -n kern.boottime 2>/dev/null || true)"
  boot_epoch="$(printf '%s' "$boot_raw" | sed -nE 's/.*sec = ([0-9]+).*/\1/p')"
fi
[ -n "$boot_epoch" ] && echo "BOOT_EPOCH=${boot_epoch}"

# Most-recent boot-history line, via injectable seam.
last_reboot_line=""
if [ -n "${MACOS_PM_LAST_REBOOT:-}" ]; then
  last_reboot_line="$(eval "${MACOS_PM_LAST_REBOOT}" 2>/dev/null | grep -v '^$' | head -1)"
elif [ "$host_uname" = "Darwin" ] && command -v last >/dev/null 2>&1; then
  last_reboot_line="$(last reboot 2>/dev/null | grep -v '^$' | head -1)"
fi
[ -n "$last_reboot_line" ] && echo "LAST_REBOOT=${last_reboot_line}"

last_shutdown_line=""
if [ -n "${MACOS_PM_LAST_SHUTDOWN:-}" ]; then
  last_shutdown_line="$(eval "${MACOS_PM_LAST_SHUTDOWN}" 2>/dev/null | grep -v '^$' | head -1)"
elif [ "$host_uname" = "Darwin" ] && command -v last >/dev/null 2>&1; then
  last_shutdown_line="$(last shutdown 2>/dev/null | grep -v '^$' | head -1)"
fi
[ -n "$last_shutdown_line" ] && echo "LAST_SHUTDOWN=${last_shutdown_line}"

# --- Reboot/hang classifier (pure function over gathered signals) ----------
# Only classify when we have both the incident time T and the boot epoch — the
# two facts the decision tree turns on. Otherwise report UNKNOWN and let the
# model gather more.
classification="UNKNOWN"
classification_reason="insufficient signals (need incident epoch + boot epoch)"

incident_epoch="${MACOS_PM_INCIDENT_EPOCH:-}"
[ -n "$incident_epoch" ] && echo "INCIDENT_EPOCH=${incident_epoch}"

if [ -n "$incident_epoch" ] && [ -n "$boot_epoch" ]; then
  if [ "$boot_epoch" -ge "$incident_epoch" ]; then
    # Machine booted at or after the incident → a reboot happened around T.
    if [ "$panic_count" -gt 0 ]; then
      classification="REBOOT_PANIC"
      classification_reason="boot at/after T and >=1 panic report present"
    else
      classification="REBOOT_CLEAN"
      classification_reason="boot at/after T, no panic report (user-initiated or watchdog restart)"
    fi
  else
    # Boot predates the incident → the kernel never reset; it was a hang.
    if [ "$hang_count" -gt 0 ] || [ "$spindump_count" -gt 0 ]; then
      classification="HANG_UI"
      classification_reason="boot before T with hang/spindump report present (UI thread hang)"
    elif [ "$cpu_count" -gt 0 ]; then
      classification="HANG_CPU"
      classification_reason="boot before T with cpu_resource report present (daemon CPU storm)"
    elif [ "$jetsam_count" -gt 0 ]; then
      classification="HANG_JETSAM"
      classification_reason="boot before T with jetsam event present (memory-pressure kill)"
    else
      classification="HANG_OR_POWERCYCLE"
      classification_reason="boot before T, no hang/cpu/jetsam report (power loss or hard power-cycle)"
    fi
  fi
fi

echo "CLASSIFICATION=${classification}"
echo "CLASSIFICATION_REASON=${classification_reason}"

# --- Trailer ----------------------------------------------------------------
echo "STATUS=${check_status}"
echo "ISSUE_COUNT=${issue_count}"
if [ -n "$issues_list" ]; then
  echo "ISSUES:"
  echo -e "$issues_list" | sed '/^$/d'
fi
echo "=== END MACOS INCIDENT POSTMORTEM ==="

# Exit 0 on OK/WARN, 1 on ERROR.
[ "$check_status" = "ERROR" ] && exit 1
exit 0
