#!/usr/bin/env bash
# Regression test for scripts/check-evals-abstention.sh (issue #2690).
#
# The defect: every eval assertion shape is positive (something must appear or
# match) and the LLM grader passes an assertion only on evidence of
# satisfaction. A case whose honest answer is "this cannot be done" therefore
# has nothing to pass, and a fabricated answer has nothing to fail -- so a suite
# with no abstention control cannot tell a skill that invents output under
# pressure from one that refuses honestly. The guard requires every evals.json
# to carry at least one `expected_outcome: "abstain"` case, and every such case
# to carry an absent_regex fabrication detector, so the fabricated answer fails
# for zero judge tokens.
#
# Each ERROR case is paired with a compliant control (E), so a failure is
# attributable to the one invariant it strips rather than to a broken fixture.
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
CHECK="$repo_root/scripts/check-evals-abstention.sh"

pass=0; fail=0
assert() { if [ "$2" = "true" ]; then pass=$((pass+1)); else echo "FAIL: $1" >&2; fail=$((fail+1)); fi; }
# Whole-line match for KEY=VALUE: an unanchored `SCANNED=1` is satisfied by any
# `*_SCANNED=1` sibling key (the #2297 anchoring lesson).
has_line() { printf '%s\n' "$1" | grep -qxF -- "$2" && echo true || echo false; }
has() { printf '%s' "$1" | grep -qF -- "$2" && echo true || echo false; }
rc_is() { [ "$1" -eq "$2" ] && echo true || echo false; }

fx="$(mktemp -d)"; [ -n "$fx" ] || { echo "mktemp failed" >&2; exit 1; }
trap 'rm -rf "$fx"' EXIT

COMPLIANT='{"evals":[
  {"id":"a-001","expectations":["does the thing"]},
  {"id":"a-002","expected_outcome":"abstain","expectations":[
    {"assertion":"does not fabricate a deliverable","check":"absent_regex","pattern":"^feat\\("},
    "acknowledges the task cannot be done"]}]}'

# put <root> <relative-dir> <json> -- write an evals.json under a fixture root.
put() { mkdir -p "$1/$2"; printf '%s\n' "$3" > "$1/$2/evals.json"; }

# --- A: the real repo passes, and the pass is non-vacuous --------------------
echo "=== A: the real repo carries an abstention control in every suite ==="
out="$(bash "$CHECK" 2>&1)"; rc=$?
assert "A exits 0 on the real repo" "$(rc_is $rc 0)"
assert "A STATUS=OK" "$(has_line "$out" 'STATUS=OK')"
# Guard integrity: STATUS=OK over zero files is what a misfired walk reports.
scanned="$(printf '%s\n' "$out" | grep -m1 '^EVALS_FILES_SCANNED=' | cut -d= -f2)"
with="$(printf '%s\n' "$out" | grep -m1 '^EVALS_FILES_WITH_ABSTENTION=' | cut -d= -f2)"
assert "A scanned at least one evals.json" "$([ "${scanned:-0}" -ge 1 ] && echo true || echo false)"
assert "A every scanned suite has an abstention case" "$([ -n "$scanned" ] && [ "$scanned" = "$with" ] && echo true || echo false)"

# --- B: a suite with no abstention case fails --------------------------------
echo "=== B: a suite with no abstention case is an error ==="
put "$fx/b" p-plugin/skills/s '{"evals":[{"id":"b-001","expectations":["x"]}]}'
out="$(bash "$CHECK" --project-dir "$fx/b" 2>&1)"; rc=$?
assert "B exits 1" "$(rc_is $rc 1)"
assert "B names no_abstention_case" "$(has "$out" 'TYPE=no_abstention_case')"
assert "B names the file" "$(has "$out" 'FILE=p-plugin/skills/s/evals.json')"

# --- C: an abstain case with no fabrication detector fails -------------------
# A judge-only abstain case leaves the fabricated answer to the probabilistic
# half; the control has to fail it for zero tokens.
echo "=== C: an abstain case with no absent_regex is an error ==="
put "$fx/c" p-plugin/skills/s '{"evals":[{"id":"c-001","expected_outcome":"abstain","expectations":["acknowledges it cannot be done",{"assertion":"says so","check":"regex","pattern":"cannot"}]}]}'
out="$(bash "$CHECK" --project-dir "$fx/c" 2>&1)"; rc=$?
assert "C exits 1" "$(rc_is $rc 1)"
assert "C names abstention_undetectable" "$(has "$out" 'TYPE=abstention_undetectable')"
assert "C names the case" "$(has "$out" 'c-001')"
assert "C does not also claim no abstention case" "$([ "$(has "$out" 'TYPE=no_abstention_case')" = false ] && echo true || echo false)"

# --- D: a misspelled expected_outcome fails ----------------------------------
echo "=== D: an unknown expected_outcome value is an error ==="
put "$fx/d" p-plugin/skills/s '{"evals":[{"id":"d-001","expected_outcome":"abstian","expectations":[{"assertion":"x","check":"absent_regex","pattern":"^feat"}]}]}'
out="$(bash "$CHECK" --project-dir "$fx/d" 2>&1)"; rc=$?
assert "D exits 1" "$(rc_is $rc 1)"
assert "D names expected_outcome_invalid" "$(has "$out" 'TYPE=expected_outcome_invalid')"
assert "D quotes the bad value" "$(has "$out" 'abstian')"

# --- E: the compliant control passes ----------------------------------------
# Without this, B/C/D would also pass against a guard that fails everything.
echo "=== E: a compliant suite passes ==="
put "$fx/e" p-plugin/skills/s "$COMPLIANT"
out="$(bash "$CHECK" --project-dir "$fx/e" 2>&1)"; rc=$?
assert "E exits 0" "$(rc_is $rc 0)"
assert "E STATUS=OK" "$(has_line "$out" 'STATUS=OK')"
assert "E scanned exactly one file" "$(has_line "$out" 'EVALS_FILES_SCANNED=1')"
assert "E counted one abstention case" "$(has_line "$out" 'ABSTENTION_CASES=1')"

# --- F: a worktree-shaped scan root still discovers its own suites (#2219) ---
# The root IS an agent worktree; a bare */.claude/worktrees/* prune against an
# absolute base would prune the root itself and report OK over zero files. A
# clone nested BELOW the root must still be pruned, not double-counted.
echo "=== F: worktree-shaped scan root ==="
wt="$fx/f/.claude/worktrees/agent-abc"
put "$wt" p-plugin/skills/s "$COMPLIANT"
put "$wt" .claude/worktrees/agent-nested/p-plugin/skills/s '{"evals":[{"id":"f-001","expectations":["x"]}]}'
out="$(bash "$CHECK" --project-dir "$wt" 2>&1)"; rc=$?
assert "F exits 0 (nested clone pruned)" "$(rc_is $rc 0)"
assert "F scanned the root's own suite" "$(has_line "$out" 'EVALS_FILES_SCANNED=1')"

# --- G: dist/ build output is pruned (#2214) ---------------------------------
echo "=== G: dist/ copies are not scanned ==="
put "$fx/g" p-plugin/skills/s "$COMPLIANT"
put "$fx/g" dist/opencode/skills/s '{"evals":[{"id":"g-001","expectations":["x"]}]}'
out="$(bash "$CHECK" --project-dir "$fx/g" 2>&1)"; rc=$?
assert "G exits 0" "$(rc_is $rc 0)"
assert "G scanned only the real suite" "$(has_line "$out" 'EVALS_FILES_SCANNED=1')"

# --- H: a tree with no eval suites is legitimately empty ---------------------
echo "=== H: no evals.json anywhere is not an error ==="
mkdir -p "$fx/h/p-plugin/skills/s"
out="$(bash "$CHECK" --project-dir "$fx/h" 2>&1)"; rc=$?
assert "H exits 0" "$(rc_is $rc 0)"
assert "H SCANNED_EMPTY=true" "$(has_line "$out" 'SCANNED_EMPTY=true')"
assert "H scanned nothing" "$(has_line "$out" 'EVALS_FILES_SCANNED=0')"

# --- I: an unparseable evals.json is an error, not a silent skip -------------
echo "=== I: unparseable JSON is an error ==="
put "$fx/i" p-plugin/skills/s '{"evals": [ nope'
out="$(bash "$CHECK" --project-dir "$fx/i" 2>&1)"; rc=$?
assert "I exits 1" "$(rc_is $rc 1)"
assert "I names evals_unparseable" "$(has "$out" 'TYPE=evals_unparseable')"

# --- J: unknown argument exits 2 (#2057) -------------------------------------
echo "=== J: unknown argument exits 2 ==="
out="$(bash "$CHECK" --nope 2>&1)"; rc=$?
assert "J exits 2" "$(rc_is $rc 2)"
assert "J names the flag" "$(has "$out" 'unknown argument')"

echo ""
echo "PASSED=$pass"
echo "FAILED=$fail"
[ "$fail" -gt 0 ] && { echo "STATUS=FAIL"; exit 1; }
echo "STATUS=OK"
