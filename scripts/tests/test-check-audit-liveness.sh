#!/usr/bin/env bash
# Regression test for scripts/check-audit-liveness.sh.
#
# The bug this guards: research-radar.yml ran 15 times green between 2026-06-15
# and 2026-09-02 and filed 5 issues, with nine consecutive silent weeks in the
# middle. Every `gh issue create` was denied because the run carried no
# `allowedTools` grant, and the SDK exits 0 on a denial -- so the runs were green
# and the silence looked exactly like "nothing cleared the bar", which the
# radar's prompt explicitly blesses as a common outcome.
#
# The fixtures are the REAL run and issue history, not invented data, so the
# assertions below say what the check would actually have done at the time.
#
# Cases B and C carry the weight and pull in opposite directions: B is the
# mid-gap state that must FAIL, C is a genuine two-week quiet stretch from the
# same history that must stay green. Without C, a check hardwired to fail would
# pass B; without B, a check that never fires would pass C.
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
checker="$repo_root/scripts/check-audit-liveness.sh"
fx="$script_dir/fixtures/audit-liveness"

pass_count=0
fail_count=0
assert() {
  if [ "$2" = "true" ]; then
    pass_count=$((pass_count + 1))
  else
    echo "FAIL: $1" >&2
    fail_count=$((fail_count + 1))
  fi
}
is_true() { [ "$1" = "true" ] && echo true || echo false; }
contains() { printf '%s' "$1" | grep -q -- "$2" && echo true || echo false; }

# --- TEST A: today's state (radar filing again) ------------------------------
echo "=== TEST A: a workflow that is filing is not reported ==="
out="$(bash "$checker" --fixture "$fx/current.json" 2>&1)"; rc=$?
assert "A exits 0" "$(is_true "$([ $rc -eq 0 ] && echo true)")"
assert "A STATUS=OK" "$(contains "$out" 'STATUS=OK')"
assert "A streak is 0" "$(contains "$out" 'SILENT_STREAK=0')"
# Guard integrity: a checker that parsed nothing would also print STATUS=OK.
assert "A examined the real run history" "$(contains "$out" 'RUNS=14')"
assert "A saw the filed issues" "$(contains "$out" 'ISSUES=5')"
assert "A is not SCANNED_EMPTY" "$(contains "$out" 'SCANNED_EMPTY=false')"

# --- TEST B: mid-gap, 2026-08-19 (the failure) -------------------------------
echo "=== TEST B: nine silent weeks is reported ==="
out="$(bash "$checker" --fixture "$fx/mid-gap.json" 2>&1)"; rc=$?
assert "B exits 1" "$(is_true "$([ $rc -eq 1 ] && echo true)")"
assert "B STATUS=FAIL" "$(contains "$out" 'STATUS=FAIL')"
assert "B counts the whole streak" "$(contains "$out" 'SILENT_STREAK=8')"
assert "B names the workflow" "$(contains "$out" 'SILENT=research-radar.yml')"
# The remedy has to name the actual cause, or the finding is a puzzle.
assert "B remedy points at allowedTools" "$(contains "$out" 'allowedTools')"
assert "B remedy points at the denial count" "$(contains "$out" 'permission_denials_count')"

# --- TEST C: a legitimate two-week quiet stretch (the counter-case) ----------
# Same real history, truncated to 2026-07-08. The radar was already broken here,
# but only two runs deep -- and two silent weeks is indistinguishable from a
# quiet fortnight, so the check must NOT fire. This is what stops the guard
# becoming noise that gets switched off.
echo "=== TEST C: two silent runs stays green ==="
out="$(bash "$checker" --fixture "$fx/quiet-two.json" 2>&1)"; rc=$?
assert "C exits 0" "$(is_true "$([ $rc -eq 0 ] && echo true)")"
assert "C streak is 2" "$(contains "$out" 'SILENT_STREAK=2')"
assert "C reports no finding" "$(contains "$out" 'ISSUE_COUNT=0')"
# Non-vacuity: C must have actually examined runs, not skipped the fixture.
assert "C examined runs" "$(contains "$out" 'RUNS=6')"

# --- TEST D: the threshold is the lever, and it moves both ways --------------
echo "=== TEST D: --max-silent shifts the boundary ==="
out="$(bash "$checker" --fixture "$fx/quiet-two.json" --max-silent 1 2>&1)"; rc=$?
assert "D tighter threshold fires on the same data" "$(is_true "$([ $rc -eq 1 ] && echo true)")"
out="$(bash "$checker" --fixture "$fx/mid-gap.json" --max-silent 20 2>&1)"; rc=$?
assert "D looser threshold clears the gap" "$(is_true "$([ $rc -eq 0 ] && echo true)")"

# --- TEST E: --issue-body is empty on a clean sweep --------------------------
# The scheduled-audits skeleton files an issue from stdout, so a non-empty body
# on a healthy repo would open a monthly issue saying nothing is wrong.
echo "=== TEST E: --issue-body emits nothing when clean ==="
out="$(bash "$checker" --fixture "$fx/current.json" --issue-body 2>&1)"; rc=$?
assert "E exits 0" "$(is_true "$([ $rc -eq 0 ] && echo true)")"
assert "E body is empty" "$(is_true "$([ -z "$out" ] && echo true)")"
out="$(bash "$checker" --fixture "$fx/mid-gap.json" --issue-body 2>&1)"
assert "E body is written when silent" "$(contains "$out" 'consecutive successful runs')"

# --- TEST F: unknown argument exits 2 (#2057) --------------------------------
echo "=== TEST F: unknown argument exits 2 ==="
out="$(bash "$checker" --not-a-real-flag 2>&1)"; rc=$?
assert "F exits 2" "$(is_true "$([ $rc -eq 2 ] && echo true)")"
assert "F names the flag" "$(contains "$out" 'unknown argument')"
out="$(bash "$checker" --fixture "$fx/current.json" --max-silent abc 2>&1)"; rc=$?
assert "F rejects a non-integer threshold" "$(is_true "$([ $rc -eq 2 ] && echo true)")"

# --- TEST G: the second watched workflow, also from real history -------------
# changelog-review.yml has the identical signature and was found the moment the
# check was pointed at it: 22 successful runs, last tracking issue 2026-06-21.
# It is here because one example reads as an anecdote -- a second independent
# instance is what makes the check worth running.
echo "=== TEST G: changelog-review's real history is reported ==="
out="$(bash "$checker" --fixture "$fx/changelog-review.json" 2>&1)"; rc=$?
assert "G exits 1" "$(is_true "$([ $rc -eq 1 ] && echo true)")"
assert "G counts 13 silent runs" "$(contains "$out" 'SILENT_STREAK=13')"
assert "G names changelog-review" "$(contains "$out" 'SILENT=changelog-review.yml')"
# Non-vacuity: the fixture must carry the issues it DID file, or a streak of 13
# would just mean "no issues anywhere" and prove nothing about the correlation.
assert "G saw the issues it did file" "$(contains "$out" 'ISSUES=8')"
assert "G examined every successful run" "$(contains "$out" 'RUNS=22')"

# --- TEST H: both workflows in one sweep -------------------------------------
# The production WATCHED list has two entries, so the multi-workflow path is the
# one that actually runs. A single-entry check would never exercise it.
echo "=== TEST H: a sweep reports per workflow, not in aggregate ==="
cat "$fx/current.json" "$fx/changelog-review.json" > "$fx/../../../.tmp-both.json" 2>/dev/null || true
both="$(mktemp)"; cat "$fx/current.json" "$fx/changelog-review.json" > "$both"
out="$(bash "$checker" --fixture "$both" 2>&1)"; rc=$?
rm -f "$both" "$fx/../../../.tmp-both.json"
assert "H exits 1 when one of two is silent" "$(is_true "$([ $rc -eq 1 ] && echo true)")"
assert "H watches both" "$(contains "$out" 'WORKFLOWS_WATCHED=2')"
assert "H reports exactly one finding" "$(contains "$out" 'ISSUE_COUNT=1')"
# The healthy one must NOT be dragged down by its silent neighbour.
assert "H clears the healthy workflow" "$(contains "$out" 'WORKFLOW=research-radar.yml	RUNS=14	ISSUES=5	SILENT_STREAK=0	OVER=false')"

echo ""
echo "=== RESULTS ==="
echo "PASSED=$pass_count"
echo "FAILED=$fail_count"
if [ "$fail_count" -gt 0 ]; then echo "STATUS=FAIL"; exit 1; fi
echo "STATUS=OK"
