#!/usr/bin/env bash
# Regression test for issue #3043: mutation probes tripped the `sed-inplace`
# block in bash-antipatterns.sh because verifier agents were told to run
# `cp <f> <snap>` + `sed -i ... <f>` + gate + `cp <snap> <f>` by hand. The
# helper mutation-check.sh owns the snapshot, the mutation and the restore.
#
# The load-bearing property is that the target file is byte-identical after the
# run on EVERY exit path: gate passes, gate fails, gate dies to a signal, the
# helper itself is terminated, the sed expression is a no-op. A restore that
# only ran on the happy path is the bug this suite pins.
#
# MUTATION_CHECK_SCRIPT overrides the script under test, so a deliberately
# broken copy can prove each assertion has teeth.
#
# Run: bash agent-patterns-plugin/skills/parallel-agent-dispatch/scripts/tests/test-mutation-check.sh

set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
script="${MUTATION_CHECK_SCRIPT:-$here/../mutation-check.sh}"

sandbox=$(mktemp -d "${TMPDIR:-/tmp}/test-mutation-check.XXXXXX") || exit 1
if [ -z "$sandbox" ] || [ ! -d "$sandbox" ]; then
  echo "FAIL: mktemp -d produced no directory" >&2
  exit 1
fi
cleanup() { rm -rf "$sandbox"; }
trap cleanup EXIT

pass=0
fail=0

ok() { printf 'PASS %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf 'FAIL %s\n' "$1"; fail=$((fail + 1)); }

assert_eq() {
  local label="$1" actual="$2" expected="$3"
  if [ "$actual" = "$expected" ]; then ok "$label"; else bad "$label (expected '$expected', got '$actual')"; fi
}

assert_contains() {
  local label="$1" haystack="$2" needle="$3"
  if grep -qF -- "$needle" <<<"$haystack"; then ok "$label"; else bad "$label (missing '$needle' in: $haystack)"; fi
}

assert_not_contains() {
  local label="$1" haystack="$2" needle="$3"
  if grep -qF -- "$needle" <<<"$haystack"; then bad "$label (unexpected '$needle')"; else ok "$label"; fi
}

# Fresh target file with known content; prints its path.
new_target() {
  local name="$1"
  local f="$sandbox/$name"
  printf 'limit >= 3\nkeep\n' >"$f"
  printf '%s' "$f"
}

original=$(printf 'limit >= 3\nkeep\n')

content_of() { cat "$1"; }

# Positive control: the script under test is runnable at all.
[ -f "$script" ] || { echo "FAIL: script under test not found: $script" >&2; exit 1; }

# --- A. gate fails on the mutant -> killed, file restored ---
f=$(new_target a.txt)
out=$(bash "$script" "$f" 's/>= 3/>= 4/' -- grep -q '>= 3' "$f" 2>/dev/null); rc=$?
assert_eq "A1 killed: exit 0" "$rc" "0"
assert_contains "A2 killed: MUTANT=killed" "$out" "MUTANT=killed"
assert_contains "A3 killed: STATUS=OK" "$out" "STATUS=OK"
assert_contains "A4 killed: RESTORED=true" "$out" "RESTORED=true"
assert_eq "A5 killed: file restored byte-for-byte" "$(content_of "$f")" "$original"

# --- B. gate passes on the mutant -> survived, file restored ---
f=$(new_target b.txt)
out=$(bash "$script" "$f" 's/>= 3/>= 4/' -- true 2>/dev/null); rc=$?
assert_eq "B1 survived: exit 0" "$rc" "0"
assert_contains "B2 survived: MUTANT=survived" "$out" "MUTANT=survived"
assert_contains "B3 survived: STATUS=WARN" "$out" "STATUS=WARN"
assert_contains "B4 survived: REASON line" "$out" "REASON=mutant_survived"
assert_contains "B5 survived: ISSUE_COUNT=1" "$out" "ISSUE_COUNT=1"
assert_eq "B6 survived: file restored byte-for-byte" "$(content_of "$f")" "$original"

# --- C. the gate really sees the mutated content ---
f=$(new_target c.txt)
out=$(bash "$script" "$f" 's/>= 3/>= 4/' -- grep -q '>= 4' "$f" 2>/dev/null)
assert_contains "C1 gate saw the mutant (>= 4 present => gate passed => survived)" "$out" "MUTANT=survived"
assert_eq "C2 file restored after gate read mutant" "$(content_of "$f")" "$original"

# --- D. gate killed by a signal -> still restored, reported as killed ---
f=$(new_target d.txt)
out=$(bash "$script" "$f" 's/>= 3/>= 4/' -- sh -c 'kill -KILL $$' 2>/dev/null); rc=$?
assert_eq "D1 gate SIGKILLed: helper exit 0" "$rc" "0"
assert_contains "D2 gate SIGKILLed: MUTANT=killed" "$out" "MUTANT=killed"
assert_contains "D3 gate SIGKILLed: GATE_EXIT=137" "$out" "GATE_EXIT=137"
assert_eq "D4 gate SIGKILLed: file restored" "$(content_of "$f")" "$original"

# --- E. the helper itself is terminated mid-gate -> restored, exit 143 ---
f=$(new_target e.txt)
e_out="$sandbox/e.out"
bash "$script" "$f" 's/>= 3/>= 4/' -- sleep 30 >"$e_out" 2>/dev/null &
helper_pid=$!
# Wait until the mutation is on disk (the gate is then running), bounded.
waited=0
while ! grep -q '>= 4' "$f" 2>/dev/null; do
  sleep 0.1
  waited=$((waited + 1))
  [ "$waited" -lt 100 ] || break
done
assert_contains "E0 precondition: mutant was on disk while the gate ran" "$(content_of "$f")" ">= 4"
kill -TERM "$helper_pid" 2>/dev/null
wait "$helper_pid" 2>/dev/null; rc=$?
assert_eq "E1 helper SIGTERMed: exit 143" "$rc" "143"
assert_eq "E2 helper SIGTERMed: file restored" "$(content_of "$f")" "$original"
e_text=$(cat "$e_out")
assert_contains "E3 helper SIGTERMed: STATUS=ERROR" "$e_text" "STATUS=ERROR"
assert_contains "E4 helper SIGTERMed: RESTORED=true" "$e_text" "RESTORED=true"
assert_not_contains "E5 helper SIGTERMed: no MUTANT verdict" "$e_text" "MUTANT="

# --- F. no-op sed expression is rejected, file untouched ---
f=$(new_target f.txt)
out=$(bash "$script" "$f" 's/does-not-appear/x/' -- true 2>/dev/null); rc=$?
assert_eq "F1 no-op mutation: exit 1" "$rc" "1"
assert_contains "F2 no-op mutation: STATUS=ERROR" "$out" "STATUS=ERROR"
assert_contains "F3 no-op mutation: TYPE no_op_mutation" "$out" "no_op_mutation"
assert_not_contains "F4 no-op mutation: no verdict emitted" "$out" "MUTANT="
assert_eq "F5 no-op mutation: file untouched" "$(content_of "$f")" "$original"

# --- G. missing file is rejected ---
out=$(bash "$script" "$sandbox/does-not-exist" 's/a/b/' -- true 2>/dev/null); rc=$?
assert_eq "G1 missing file: exit 1" "$rc" "1"
assert_contains "G2 missing file: STATUS=ERROR" "$out" "STATUS=ERROR"
assert_contains "G3 missing file: TYPE missing_file" "$out" "missing_file"
if [ -e "$sandbox/does-not-exist" ]; then bad "G4 missing file: not created"; else ok "G4 missing file: not created"; fi

# --- H. usage errors exit 2 and never run the gate ---
f=$(new_target h.txt)
marker="$sandbox/h.gate-ran"
bash "$script" "$f" 's/>= 3/>= 4/' touch "$marker" >/dev/null 2>&1; rc=$?
assert_eq "H1 missing '--': exit 2" "$rc" "2"
if [ -e "$marker" ]; then bad "H2 missing '--': gate must not run"; else ok "H2 missing '--': gate must not run"; fi
assert_eq "H3 missing '--': file untouched" "$(content_of "$f")" "$original"
bash "$script" "$f" 's/>= 3/>= 4/' -- >/dev/null 2>&1; rc=$?
assert_eq "H4 empty gate command: exit 2" "$rc" "2"

# --- I. file mode survives the mutate-and-restore cycle ---
f=$(new_target i.txt)
chmod 750 "$f"
bash "$script" "$f" 's/>= 3/>= 4/' -- true >/dev/null 2>&1
# ls -l is the one mode read that prints the same on BSD and GNU (stat flags differ).
# shellcheck disable=SC2012
mode=$(ls -l "$f" | cut -c1-10)
assert_eq "I1 mode preserved" "$mode" "-rwxr-x---"

# --- J. -E selects extended regex (portable across BSD and GNU sed) ---
f=$(new_target j.txt)
out=$(bash "$script" -E "$f" 's/(>=) (3)/\1 9/' -- grep -q '>= 9' "$f" 2>/dev/null)
assert_contains "J1 -E: mutant applied (gate passed on >= 9 => survived)" "$out" "MUTANT=survived"
assert_eq "J2 -E: file restored" "$(content_of "$f")" "$original"

# --- K. a malformed sed expression is an ERROR, file untouched ---
f=$(new_target k.txt)
out=$(bash "$script" "$f" 's/unterminated' -- true 2>/dev/null); rc=$?
assert_eq "K1 bad sed: exit 1" "$rc" "1"
assert_contains "K2 bad sed: TYPE sed_failed" "$out" "sed_failed"
assert_eq "K3 bad sed: file untouched" "$(content_of "$f")" "$original"

printf '%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
