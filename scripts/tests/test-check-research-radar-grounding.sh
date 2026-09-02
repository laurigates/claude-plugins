#!/usr/bin/env bash
# shellcheck disable=SC2015  # file-level: `[ -n ] && [ -d ] || die` is a guard, not if-then-else (must precede the first command)
# Regression tests for scripts/check-research-radar-grounding.sh (#2507).
#
# The guard pins the research-radar prompt's TOKEN-LEVEL grounding requirement:
# every surfaced suggestion is probed with one `Grep` against the surface it
# claims exists, and the old blanket "Do not read plugin source files" clause
# stays gone. Both directions are tested — a present-clause fixture must report
# STATUS=OK, and each mutant must be flagged — so the guard cannot pass
# vacuously by emitting nothing (.claude/rules/regression-testing.md).
#
# Run: bash scripts/tests/test-check-research-radar-grounding.sh
# Exit 0 = all tests pass, Exit 1 = failures
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GUARD="$SCRIPT_DIR/check-research-radar-grounding.sh"
REAL_WORKFLOW="$REPO_ROOT/.github/workflows/research-radar.yml"
PASS=0
FAIL=0

WORK=$(mktemp -d) || { echo "mktemp -d failed" >&2; exit 1; }
[ -n "$WORK" ] && [ -d "$WORK" ] || { echo "bad sandbox dir" >&2; exit 1; }
trap 'rm -rf "$WORK"' EXIT

[ -f "$REAL_WORKFLOW" ] || { echo "missing $REAL_WORKFLOW" >&2; exit 1; }

# Seed a fixture repo root holding a copy of the real workflow.
seed() {
  local root="$1"
  mkdir -p "$root/.github/workflows"
  cp "$REAL_WORKFLOW" "$root/.github/workflows/research-radar.yml"
}

run_key() {
  # run_key DIR KEY -> value of KEY= from the guard's report
  bash "$GUARD" "$1" 2>&1 | grep -E "^$2=" | cut -d= -f2-
}

assert_eq() {
  local desc="$1" expected="$2" got="$3"
  if [ "$got" = "$expected" ]; then
    printf "  PASS: %s\n" "$desc"; PASS=$((PASS + 1))
  else
    printf "  FAIL: %s (expected '%s', got '%s')\n" "$desc" "$expected" "$got"; FAIL=$((FAIL + 1))
  fi
}

echo "=== check-research-radar-grounding regression tests ==="

# 0. Guard integrity: the report is actually emitted (a silent script would make
#    every ISSUE_COUNT assertion below pass on an empty string).
clean="$WORK/clean"; seed "$clean"
report="$(bash "$GUARD" "$clean" 2>&1)"
case "$report" in
  *"=== RESEARCH RADAR GROUNDING ==="*"=== END RESEARCH RADAR GROUNDING ==="*)
    printf "  PASS: guard emits its structured report block\n"; PASS=$((PASS + 1)) ;;
  *)
    printf "  FAIL: guard emitted no structured report block\n"; FAIL=$((FAIL + 1)) ;;
esac

# 1. Positive control — the real workflow, copied verbatim, is grounded.
assert_eq "grounded workflow reports STATUS=OK" "OK" "$(run_key "$clean" STATUS)"
assert_eq "grounded workflow reports ISSUE_COUNT=0" "0" "$(run_key "$clean" ISSUE_COUNT)"
assert_eq "grounded workflow reports WORKFLOW_PRESENT=true" "true" "$(run_key "$clean" WORKFLOW_PRESENT)"

# 2. The live repo (default project dir) is grounded too.
assert_eq "live repo reports STATUS=OK" "OK" "$(bash "$GUARD" 2>&1 | grep -E '^STATUS=' | cut -d= -f2)"

# 3. Grounding requirement stripped → flagged.
no_ground="$WORK/no_ground"; seed "$no_ground"
wf="$no_ground/.github/workflows/research-radar.yml"
grep -vF 'Ground every surfaced suggestion' "$wf" > "$wf.tmp" && mv "$wf.tmp" "$wf"
assert_eq "missing grounding requirement is flagged" "1" "$(run_key "$no_ground" ISSUE_COUNT)"
assert_eq "missing grounding requirement sets STATUS=ERROR" "ERROR" "$(run_key "$no_ground" STATUS)"

# 4. Drop-or-re-target instruction stripped → flagged.
no_drop="$WORK/no_drop"; seed "$no_drop"
wf="$no_drop/.github/workflows/research-radar.yml"
grep -vF 'or drop the paper' "$wf" > "$wf.tmp" && mv "$wf.tmp" "$wf"
assert_eq "missing drop-or-re-target instruction is flagged" "1" "$(run_key "$no_drop" ISSUE_COUNT)"

# 5. Evidence-disclosure instruction stripped → flagged.
no_evidence="$WORK/no_evidence"; seed "$no_evidence"
wf="$no_evidence/.github/workflows/research-radar.yml"
grep -vF 'State the exact file(s) and pattern grepped' "$wf" > "$wf.tmp" && mv "$wf.tmp" "$wf"
assert_eq "missing grounding-evidence disclosure is flagged" "1" "$(run_key "$no_evidence" ISSUE_COUNT)"

# 6. The #2507 root-cause clause re-introduced → flagged (absence assertion).
regressed="$WORK/regressed"; seed "$regressed"
wf="$regressed/.github/workflows/research-radar.yml"
printf '            - Do not read plugin source files — mapping ideas to plugin names only.\n' >> "$wf"
assert_eq "re-introduced no-source-read clause is flagged" "1" "$(run_key "$regressed" ISSUE_COUNT)"

# 7. Missing workflow entirely → every assertion reports.
empty="$WORK/empty"; mkdir -p "$empty"
assert_eq "absent workflow reports WORKFLOW_PRESENT=false" "false" "$(run_key "$empty" WORKFLOW_PRESENT)"
assert_eq "absent workflow flags all four assertions" "4" "$(run_key "$empty" ISSUE_COUNT)"

# 8. --strict exit codes.
if bash "$GUARD" --strict "$clean" >/dev/null 2>&1; then
  printf "  PASS: --strict exits 0 on a grounded workflow\n"; PASS=$((PASS + 1))
else
  printf "  FAIL: --strict should exit 0 on a grounded workflow\n"; FAIL=$((FAIL + 1))
fi
if bash "$GUARD" --strict "$no_ground" >/dev/null 2>&1; then
  printf "  FAIL: --strict should exit 1 when the grounding clause is missing\n"; FAIL=$((FAIL + 1))
else
  printf "  PASS: --strict exits 1 when the grounding clause is missing\n"; PASS=$((PASS + 1))
fi

# 9. Unknown argument is rejected with exit 2, never swallowed.
bash "$GUARD" --bogus >/dev/null 2>&1
if [ "$?" -eq 2 ]; then
  printf "  PASS: unknown argument exits 2\n"; PASS=$((PASS + 1))
else
  printf "  FAIL: unknown argument should exit 2\n"; FAIL=$((FAIL + 1))
fi

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
