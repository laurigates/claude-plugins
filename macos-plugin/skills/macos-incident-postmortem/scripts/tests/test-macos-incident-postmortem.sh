#!/usr/bin/env bash
# Regression test for macos-incident-postmortem.sh (issue #1557).
#
# Runs entirely offline on Linux CI against PLANTED fixture report files via the
# injectable seams (--reports-dir + MACOS_PM_* env vars) — never against the
# real macOS system. Asserts the SEMANTIC invariants:
#   - A planted reboot scenario (boot at/after T) classifies as a reboot, with
#     correct per-category report counts and CPU/jetsam histograms.
#   - A planted hang scenario (boot before T, hang report present) classifies as
#     a UI hang.
#   - A missing/empty reports dir degrades gracefully (STATUS without crashing).
# Exit 0 on success ("ALL TESTS PASSED"); non-zero on any failure.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pm_script="${script_dir}/../macos-incident-postmortem.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

pass() {
  echo "PASS: $1"
}

# Hard deps: find, sed, grep, sort. Skip cleanly if missing (CI determinism).
for dep in find sed grep sort; do
  if ! command -v "$dep" >/dev/null 2>&1; then
    echo "SKIP: $dep not installed; cannot run macos-incident-postmortem tests"
    exit 0
  fi
done

[ -f "$pm_script" ] || fail "macos-incident-postmortem.sh not found at $pm_script"

fixture_root="$(mktemp -d)"
trap 'rm -rf "$fixture_root"' EXIT

# -----------------------------------------------------------------------------
# Case 1: REBOOT scenario — boot AT/AFTER T, a panic + CPU + jetsam present.
# Decision tree: boot_epoch >= incident_epoch AND panic_count > 0 → REBOOT_PANIC.
# -----------------------------------------------------------------------------
reboot_dir="${fixture_root}/reboot"
mkdir -p "$reboot_dir"
# A panic report.
printf 'panic(cpu 0 caller 0xdead): fake panic for fixture\nBacktrace (CPU 0):\n' \
  > "${reboot_dir}/Kernel-2026-04-22-081500.panic"
# Two CPU-resource diags for the same offender, one for another.
printf '{}' > "${reboot_dir}/hungdaemon-2026-04-22-081000.cpu_resource.diag"
printf '{}' > "${reboot_dir}/hungdaemon2-2026-04-22-081100.cpu_resource.diag"
# Note: offender token is everything before the first '-'.
printf '{}' > "${reboot_dir}/coreaudiod-2026-04-22-081200.cpu_resource.diag"
# A jetsam event naming two victim processes.
printf '{ "killed": 1, "name":"Safari" }\n{ "name":"Mail" }\n' \
  > "${reboot_dir}/JetsamEvent-2026-04-22-081300.ips"
# A legacy crash + a modern ips, to exercise both counters.
printf 'legacy crash\n' > "${reboot_dir}/SomeApp-2026-04-22.crash"

incident_epoch=1714723200          # the incident time T
boot_after=$((incident_epoch + 60)) # booted 60s after T → reboot

out1="$(MACOS_PM_UNAME=Linux \
        MACOS_PM_BOOTTIME="$boot_after" \
        MACOS_PM_INCIDENT_EPOCH="$incident_epoch" \
        MACOS_PM_LAST_REBOOT='printf "reboot ~ Tue Apr 22 08:16\n"' \
        bash "$pm_script" --home-dir "$fixture_root" --reports-dir "$reboot_dir")"
rc1=$?

[ "$rc1" -eq 0 ] || fail "reboot case should exit 0 (WARN on non-darwin), got rc=$rc1:\n$out1"
echo "$out1" | grep -q "^CLASSIFICATION=REBOOT_PANIC$" \
  || fail "expected CLASSIFICATION=REBOOT_PANIC, got:\n$out1"
echo "$out1" | grep -q "^PANIC_COUNT=1$" \
  || fail "expected PANIC_COUNT=1, got:\n$out1"
echo "$out1" | grep -q "^CPU_RESOURCE_COUNT=3$" \
  || fail "expected CPU_RESOURCE_COUNT=3, got:\n$out1"
echo "$out1" | grep -q "^JETSAM_COUNT=1$" \
  || fail "expected JETSAM_COUNT=1, got:\n$out1"
echo "$out1" | grep -q "^CRASH_COUNT=1$" \
  || fail "expected CRASH_COUNT=1, got:\n$out1"
echo "$out1" | grep -q "^STATUS=" \
  || fail "expected a STATUS= line, got:\n$out1"
# CPU offender histogram: the top offender 'hungdaemon2'/'hungdaemon' each have 1
# — assert the histogram block exists and lists a known offender.
echo "$out1" | grep -q "^CPU_OFFENDERS:$" \
  || fail "expected CPU_OFFENDERS histogram block, got:\n$out1"
echo "$out1" | grep -q "PROC=coreaudiod COUNT=1" \
  || fail "expected coreaudiod offender row, got:\n$out1"
# Jetsam victims histogram lists Safari and Mail.
echo "$out1" | grep -q "^JETSAM_VICTIMS:$" \
  || fail "expected JETSAM_VICTIMS histogram block, got:\n$out1"
echo "$out1" | grep -q "PROC=Safari COUNT=1" \
  || fail "expected Safari jetsam victim row, got:\n$out1"
pass "planted reboot fixture classifies REBOOT_PANIC with correct counts/histograms"

# -----------------------------------------------------------------------------
# Case 2: HANG scenario — boot BEFORE T, a .hang report present, no panic.
# Decision tree: boot_epoch < incident_epoch AND hang_count > 0 → HANG_UI.
# -----------------------------------------------------------------------------
hang_dir="${fixture_root}/hang"
mkdir -p "$hang_dir"
printf 'WindowServer hang detected\n' > "${hang_dir}/WindowServer-2026-04-22-081500.hang"
printf 'spindump capture\n' > "${hang_dir}/WindowServer-2026-04-22-081500.spindump.txt"

boot_before=$((incident_epoch - 3600)) # booted 1h before T → no reboot

out2="$(MACOS_PM_UNAME=Linux \
        MACOS_PM_BOOTTIME="$boot_before" \
        MACOS_PM_INCIDENT_EPOCH="$incident_epoch" \
        bash "$pm_script" --home-dir "$fixture_root" --reports-dir "$hang_dir")"
rc2=$?

[ "$rc2" -eq 0 ] || fail "hang case should exit 0, got rc=$rc2:\n$out2"
echo "$out2" | grep -q "^CLASSIFICATION=HANG_UI$" \
  || fail "expected CLASSIFICATION=HANG_UI, got:\n$out2"
echo "$out2" | grep -q "^HANG_COUNT=1$" \
  || fail "expected HANG_COUNT=1, got:\n$out2"
echo "$out2" | grep -q "^SPINDUMP_COUNT=1$" \
  || fail "expected SPINDUMP_COUNT=1, got:\n$out2"
echo "$out2" | grep -q "^PANIC_COUNT=0$" \
  || fail "expected PANIC_COUNT=0 in hang case, got:\n$out2"
pass "planted hang fixture classifies HANG_UI with correct counts"

# -----------------------------------------------------------------------------
# Case 3: missing reports dir → graceful degradation (STATUS, no crash).
# -----------------------------------------------------------------------------
missing_dir="${fixture_root}/does-not-exist"

out3="$(MACOS_PM_UNAME=Linux \
        bash "$pm_script" --home-dir "$fixture_root" --reports-dir "$missing_dir")"
rc3=$?

[ "$rc3" -eq 0 ] || fail "missing-dir case should exit 0 (WARN, not ERROR), got rc=$rc3:\n$out3"
echo "$out3" | grep -q "^REPORTS_DIRS_PRESENT=0$" \
  || fail "expected REPORTS_DIRS_PRESENT=0 for missing dir, got:\n$out3"
echo "$out3" | grep -q "^REPORT_COUNT=0$" \
  || fail "expected REPORT_COUNT=0 for missing dir, got:\n$out3"
echo "$out3" | grep -q "^STATUS=WARN$" \
  || fail "expected STATUS=WARN for missing reports dir, got:\n$out3"
echo "$out3" | grep -q "TYPE=no_reports_dir" \
  || fail "expected a no_reports_dir issue row, got:\n$out3"
echo "$out3" | grep -q "=== END MACOS INCIDENT POSTMORTEM ===" \
  || fail "expected closing section delimiter, got:\n$out3"
pass "missing reports dir degrades gracefully with STATUS=WARN, no crash"

# -----------------------------------------------------------------------------
# Case 4: insufficient signals (no incident epoch) → UNKNOWN, not a guess.
# -----------------------------------------------------------------------------
out4="$(MACOS_PM_UNAME=Linux \
        MACOS_PM_BOOTTIME="$boot_before" \
        bash "$pm_script" --home-dir "$fixture_root" --reports-dir "$hang_dir")"
rc4=$?

[ "$rc4" -eq 0 ] || fail "no-incident-epoch case should exit 0, got rc=$rc4:\n$out4"
echo "$out4" | grep -q "^CLASSIFICATION=UNKNOWN$" \
  || fail "expected CLASSIFICATION=UNKNOWN without incident epoch, got:\n$out4"
pass "without incident epoch the classifier reports UNKNOWN rather than guessing"

echo "ALL TESTS PASSED"
