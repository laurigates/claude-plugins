#!/usr/bin/env bash
# shellcheck disable=SC2016  # file-level: fixture bodies are single-quoted on purpose — they must reach the file unexpanded
# Regression tests for scripts/check-mktemp-canonical.sh (issues #2939, #2949).
#
# Each case builds an isolated root holding one fixture test (and, where the
# case needs one, a script under test), runs the guard against it, and checks
# ISSUE_COUNT. Positive cases are paired with the near-miss that must stay
# silent, so the suite fails an over-reporting guard and a mute one alike.
#
# Run: bash scripts/tests/test-check-mktemp-canonical.sh
# Exit 0 = all tests pass, Exit 1 = failures
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GUARD="$repo_root/scripts/check-mktemp-canonical.sh"
CONTRACT="$repo_root/scripts/check-structured-output-contract.sh"
PASS=0
FAIL=0

WORK=$(mktemp -d) || { echo "mktemp -d failed" >&2; exit 1; }
if [ -z "$WORK" ] || [ ! -d "$WORK" ]; then echo "bad sandbox dir" >&2; exit 1; fi
trap 'rm -rf "$WORK"' EXIT

ok()    { printf '  PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
notok() { printf '  FAIL: %s\n' "$1"; FAIL=$((FAIL + 1)); }

# new_case <name>: a root with a canonicalising script under test (sut.sh).
new_case() {
  local d="$WORK/$1"
  mkdir -p "$d/plug/scripts/tests"
  cat > "$d/plug/scripts/sut.sh" <<'EOF'
#!/usr/bin/env bash
cd "$1" && pwd -P
EOF
  printf '%s\n' "$d"
}

# write_test <root> <body>: the fixture test, named so discovery finds it.
write_test() {
  printf '#!/usr/bin/env bash\n%s\n' "$2" > "$1/plug/scripts/tests/test-fixture.sh"
}

field() { grep -m1 "^$2=" <<<"$1" | cut -d= -f2-; }

assert_count() {
  local desc="$1" want="$2" dir="$3" out got
  out=$(bash "$GUARD" "$dir" 2>&1)
  got=$(field "$out" ISSUE_COUNT)
  if [ "$got" = "$want" ]; then ok "$desc"; else notok "$desc (want ISSUE_COUNT=$want, got '$got')"; fi
}

echo "=== check-mktemp-canonical regression tests ==="

# 1. The #2939 shape: raw root is the grep pattern, the SUT reports pwd -P.
d=$(new_case raw-grep)
write_test "$d" 'root=$(mktemp -d) || exit 1
out=$(bash "$HERE/../sut.sh" "$root")
grep -q "$root" <<<"$out" || exit 1'
assert_count "raw root as a grep pattern beside a pwd -P SUT is flagged" 1 "$d"

# 2. Same test, root canonicalised right after creation: silent.
d=$(new_case canonical)
write_test "$d" 'root=$(mktemp -d) || exit 1
root=$(cd -P -- "$root" && pwd -P) || exit 1
out=$(bash "$HERE/../sut.sh" "$root")
grep -q "$root" <<<"$out" || exit 1'
assert_count "root canonicalised with cd -P/pwd -P is not flagged" 0 "$d"

# 3. Created canonical in one step: silent.
d=$(new_case canonical-inline)
write_test "$d" 'root=$(cd "$(mktemp -d)" && pwd -P)
out=$(bash "$HERE/../sut.sh" "$root")
grep -q "$root" <<<"$out" || exit 1'
assert_count "root created canonical via cd \$(mktemp -d) && pwd -P is not flagged" 0 "$d"

# 4. Same comparison, but nothing in reach canonicalises: string-built both sides.
d=$(new_case no-reach)
printf '#!/usr/bin/env bash\necho "$1"\n' > "$d/plug/scripts/sut.sh"
write_test "$d" 'root=$(mktemp -d) || exit 1
out=$(bash "$HERE/../sut.sh" "$root")
grep -q "$root" <<<"$out" || exit 1'
assert_count "no canonicalising code path in reach is not flagged" 0 "$d"

# 5. A derived variable carries the root into the comparison (the
#    test-configure-antigravity shape: target_g="$fixture/target_g").
d=$(new_case derived)
write_test "$d" 'fixture=$(mktemp -d) || exit 1
target="$fixture/target"
bash "$HERE/../sut.sh" "$target" > "$fixture/out"
grep -q "$target/run.py" "$fixture/out" || exit 1'
assert_count "a var derived from the raw root, used as a grep pattern, is flagged" 1 "$d"

# 6. The root only as grep's FILE argument (not the pattern): silent.
d=$(new_case grep-file)
write_test "$d" 'root=$(mktemp -d) || exit 1
bash "$HERE/../sut.sh" "$root" > "$root/out"
grep -q "needle" "$root/out" || exit 1'
assert_count "raw root as grep's file argument is not flagged" 0 "$d"

# 7. A comparing assertion helper with the root as its EXPECTED argument (the
#    test-repo-deletion-safety shape) is flagged ...
d=$(new_case assert-expected)
write_test "$d" 'WORK=$(mktemp -d) || exit 1
assert_stderr_contains "names the path" "$WORK/lonely" "$(bash "$HERE/../sut.sh" "$WORK")"'
assert_count "raw root as a comparing assertion's expected argument is flagged" 1 "$d"

# 8. ... but not when the root is only an input inside \$(…), or only in the label.
d=$(new_case assert-input)
write_test "$d" 'WORK=$(mktemp -d) || exit 1
assert_eq "label mentions $WORK" "$(bash "$HERE/../sut.sh" "$WORK/x")" "ok"'
assert_count "raw root only inside \$(…) or the label is not flagged" 0 "$d"

# 9. A generic check/expect helper (argument roles unknown) is not read as a comparison.
d=$(new_case generic-check)
write_test "$d" 'WORK=$(mktemp -d) || exit 1
check "file emitted" test -f "$WORK/out"
expect "A: clean" 0 -- "$WORK/clean"'
assert_count "generic check/expect with the root as an input is not flagged" 0 "$d"

# 10. An operand of = inside [ ] at top level is flagged; inside \$(…) it is not.
d=$(new_case test-bracket)
write_test "$d" 'root=$(mktemp -d) || exit 1
got=$(bash "$HERE/../sut.sh" "$root")
[ "$got" = "$root" ] || exit 1'
assert_count "raw root as an operand of = in [ ] is flagged" 1 "$d"
d=$(new_case test-bracket-input)
write_test "$d" 'root=$(mktemp -d) || exit 1
[ "$(bash "$HERE/../sut.sh" "$root" | wc -l)" = "1" ] || exit 1'
assert_count "raw root only inside \$(…) within [ ] is not flagged" 0 "$d"

# 11. mktemp under an already-canonical parent returns a canonical path.
d=$(new_case canonical-parent)
write_test "$d" 'sandbox=$(mktemp -d) || exit 1
sandbox=$(cd "$sandbox" && pwd -P)
run_dir=$(mktemp -d "$sandbox/run.XXXXXX") || exit 1
grep -q "$run_dir" <<<"$(bash "$HERE/../sut.sh" "$run_dir")" || exit 1'
assert_count "mktemp -d under a canonical parent is not flagged" 0 "$d"

# 12. The declared escape hatch for a deliberately logical comparison.
d=$(new_case escape-hatch)
write_test "$d" 'root=$(mktemp -d) || exit 1
out=$(bash "$HERE/../sut.sh" "$root")
grep -q "$root" <<<"$out" || exit 1  # mktemp-canonical: ok (echoed verbatim)'
assert_count "a line marked mktemp-canonical: ok is not flagged" 0 "$d"

# 13. Comments never count as comparisons.
d=$(new_case comment)
write_test "$d" 'root=$(mktemp -d) || exit 1
bash "$HERE/../sut.sh" "$root" >/dev/null
# grep -q "$root" would fail on macOS'
assert_count "a commented-out comparison is not flagged" 0 "$d"

# 14. Discovery: a fixture outside the runner's globs is not scanned.
d=$(new_case not-a-test)
mkdir -p "$d/plug/lib"
printf '#!/usr/bin/env bash\nroot=$(mktemp -d)\ngrep -q "$root" x\n' > "$d/plug/lib/test-fixture.sh"
assert_count "a test-*.sh outside tests/ and hooks/ is not scanned" 0 "$d"

# 15. Zero-scan is distinguishable from a clean scan.
mkdir -p "$WORK/empty"
out=$(bash "$GUARD" "$WORK/empty" 2>&1)
if [ "$(field "$out" SCANNED_EMPTY)" = "true" ] && [ "$(field "$out" TESTS_SCANNED)" = "0" ]; then
  ok "an empty corpus reports SCANNED_EMPTY=true"
else
  notok "an empty corpus reports SCANNED_EMPTY=true"
fi

# 16. --strict exit codes, and both outputs satisfy the structured-output contract.
d="$WORK/raw-grep"
bash "$GUARD" --strict "$d" >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 1 ]; then ok "--strict exits 1 on a finding"; else notok "--strict exits 1 on a finding (got $rc)"; fi
bash "$GUARD" --strict "$WORK/canonical" >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 0 ]; then ok "--strict exits 0 when clean"; else notok "--strict exits 0 when clean (got $rc)"; fi
for case_dir in raw-grep canonical; do
  if bash "$GUARD" "$WORK/$case_dir" 2>&1 | bash "$CONTRACT" --validate >/dev/null 2>&1; then
    ok "$case_dir output passes check-structured-output-contract --validate"
  else
    notok "$case_dir output passes check-structured-output-contract --validate"
  fi
done

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
