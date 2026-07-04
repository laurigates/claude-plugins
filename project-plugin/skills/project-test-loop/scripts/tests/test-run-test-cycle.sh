#!/usr/bin/env bash
# shellcheck disable=SC2016   # file-level: the SKILL.md guards grep for the LITERAL '$ARGUMENTS' string
# Regression test for run-test-cycle.sh — the deterministic per-cycle driver
# added for issue #1920 (project-test-loop scored 2.5/5 on determinism offload
# because the loop was prose the model re-derived every invocation).
#
# Asserts the mechanical verdicts the model branches on:
#   GREEN        — suite passes (exit 0)
#   CONTINUE     — suite failing, ceiling not hit
#   CAP_REACHED  — cycle count reached --max-cycles
#   STUCK        — same failing signature N cycles running (no progress)
#   SETUP_ERROR  — no test command could be detected
# Plus a semantic guard that SKILL.md keeps wiring its declared arguments
# ($ARGUMENTS parse, --max-cycles, the driver-script reference) so a future
# bulk edit can't silently revert the skill to argument-less prose.
#
# Exit 0 on success, non-zero on failure.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
driver="${script_dir}/../run-test-cycle.sh"
skill_md="${script_dir}/../../SKILL.md"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }

[ -f "$driver" ] || fail "run-test-cycle.sh not found at $driver"

verdict_of() { echo "$1" | grep -E '^VERDICT=' | head -n1 | cut -d= -f2; }

proj="$(mktemp -d)"
trap 'rm -rf "$proj"' EXIT

# -----------------------------------------------------------------------------
# Case 1: green suite → VERDICT=GREEN, STATUS=OK
# -----------------------------------------------------------------------------
sf="$(mktemp -u)"
out="$(bash "$driver" --test-cmd "true" --project-dir "$proj" --state-file "$sf")"
[ "$(verdict_of "$out")" = "GREEN" ] || fail "green suite should yield GREEN, got:\n$out"
echo "$out" | grep -q "^STATUS=OK$" || fail "green suite should be STATUS=OK, got:\n$out"
[ -f "$sf" ] && fail "green suite must reset state file, but it still exists"
pass "green suite → GREEN and resets state"

# -----------------------------------------------------------------------------
# Case 2: failing suite below the cap → VERDICT=CONTINUE
# -----------------------------------------------------------------------------
sf="$(mktemp -u)"
out="$(bash "$driver" --test-cmd "echo fail-A; false" --project-dir "$proj" --state-file "$sf" --max-cycles 5)"
[ "$(verdict_of "$out")" = "CONTINUE" ] || fail "first failing cycle under cap should be CONTINUE, got:\n$out"
echo "$out" | grep -q "^CYCLE=1$" || fail "first cycle should report CYCLE=1, got:\n$out"
rm -f "$sf"
pass "failing suite under cap → CONTINUE"

# -----------------------------------------------------------------------------
# Case 3: cycle count reaches --max-cycles → VERDICT=CAP_REACHED
# Vary output each cycle so STUCK does not pre-empt the cap.
# -----------------------------------------------------------------------------
sf="$(mktemp -u)"
v=""
for n in 1 2 3; do
  out="$(bash "$driver" --test-cmd "echo attempt-$n; false" --project-dir "$proj" --state-file "$sf" --max-cycles 3)"
  v="$(verdict_of "$out")"
done
[ "$v" = "CAP_REACHED" ] || fail "3rd cycle at --max-cycles 3 should be CAP_REACHED, got:\n$out"
echo "$out" | grep -q "^CYCLE=3$" || fail "cap verdict should report CYCLE=3, got:\n$out"
rm -f "$sf"
pass "cycle == --max-cycles → CAP_REACHED"

# -----------------------------------------------------------------------------
# Case 4: identical failure 3× → VERDICT=STUCK (before the cap)
# Same output every cycle → same signature → no-progress detection fires.
# High cap so CAP_REACHED cannot pre-empt STUCK.
# -----------------------------------------------------------------------------
sf="$(mktemp -u)"
v=""
for n in 1 2 3; do
  out="$(bash "$driver" --test-cmd "echo always-the-same-failure; false" --project-dir "$proj" --state-file "$sf" --max-cycles 20 --stuck-threshold 3)"
  v="$(verdict_of "$out")"
done
[ "$v" = "STUCK" ] || fail "identical failure 3× should be STUCK, got:\n$out"
rm -f "$sf"
pass "same failure 3× → STUCK"

# -----------------------------------------------------------------------------
# Case 5: no detectable test command → VERDICT=SETUP_ERROR, exit 1
# -----------------------------------------------------------------------------
empty="$(mktemp -d)"
sf="$(mktemp -u)"
if out="$(bash "$driver" --project-dir "$empty" --state-file "$sf")"; then
  fail "undetectable test command should exit non-zero, but exit was 0:\n$out"
fi
[ "$(verdict_of "$out")" = "SETUP_ERROR" ] || fail "undetectable test command should be SETUP_ERROR, got:\n$out"
rm -rf "$empty"; rm -f "$sf"
pass "no test command detected → SETUP_ERROR (exit 1)"

# -----------------------------------------------------------------------------
# Case 6: detection picks up a Makefile test target
# -----------------------------------------------------------------------------
mk="$(mktemp -d)"
printf 'test:\n\t@true\n' > "$mk/Makefile"
sf="$(mktemp -u)"
out="$(bash "$driver" --project-dir "$mk" --state-file "$sf")"
echo "$out" | grep -q "^TEST_COMMAND=make test$" || fail "Makefile test target should detect 'make test', got:\n$out"
rm -rf "$mk"; rm -f "$sf"
pass "Makefile test target detected as 'make test'"

# -----------------------------------------------------------------------------
# Case 7: SKILL.md semantic guard — the declared args stay wired into the body.
# Protects against a bulk edit reverting to argument-less prose (the #1920 gap).
# -----------------------------------------------------------------------------
if [ -f "$skill_md" ]; then
  grep -qF '$ARGUMENTS' "$skill_md" || fail "SKILL.md must parse \$ARGUMENTS (declared args were unused before #1920)"
  grep -qF -- '--max-cycles' "$skill_md" || fail "SKILL.md must reference --max-cycles (the runaway ceiling)"
  grep -qF 'run-test-cycle.sh' "$skill_md" || fail "SKILL.md must invoke the run-test-cycle.sh driver (determinism offload)"
  grep -qF 'loop-integrity.md' "$skill_md" || fail "SKILL.md must keep its loop-integrity.md cross-reference"
  pass "SKILL.md keeps \$ARGUMENTS parse, --max-cycles, driver reference, loop-integrity link"
else
  echo "SKIP: SKILL.md not found at $skill_md"
fi

echo "ALL PASS"
