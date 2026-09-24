#!/usr/bin/env bash
# Regression tests for scripts/check-structured-output-contract.sh (#2691).
#
# Two halves, matching the guard's two modes:
#   sweep      -- planted scripts/check-*.sh fixtures: vocabulary drift (literal,
#                 shell-variable, python-variable, inline $(...)), missing
#                 REASON=, missing ISSUE_COUNT=, the pending ratchet in both
#                 directions, an empty scan, and the real repo.
#   --validate -- mutants of a captured output block: every runtime rule, plus
#                 the #2714 shape (ISSUE_COUNT=0 beneath populated rows).
# Each ERROR case is paired with a clean control so a guard that flags
# everything cannot pass.
#
# Run: bash scripts/tests/test-check-structured-output-contract.sh
# Exit 0 = all tests pass, Exit 1 = failures
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GUARD="$SCRIPT_DIR/check-structured-output-contract.sh"
PASS=0
FAIL=0

WORK=$(mktemp -d) || { echo "mktemp -d failed" >&2; exit 1; }
if [ -z "$WORK" ] || [ ! -d "$WORK" ]; then echo "bad sandbox dir" >&2; exit 1; fi
trap 'rm -rf "$WORK"' EXIT

ok() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

# Whole-line KEY=VALUE match: a substring match would let TARGET_STATUS=OK
# satisfy STATUS=OK (the #2219/#2297 anchoring lesson).
has_line() { grep -qxF -- "$2" <<<"$1"; }
has_text() { grep -qF -- "$2" <<<"$1"; }

expect_line() { # name output line
  if has_line "$2" "$3"; then ok "$1"; else bad "$1 (missing line: $3)"; fi
}
expect_text() { # name output text
  if has_text "$2" "$3"; then ok "$1"; else bad "$1 (missing text: $3)"; fi
}
expect_no_text() { # name output text
  if has_text "$2" "$3"; then bad "$1 (unexpected text: $3)"; else ok "$1"; fi
}
expect_exit() { # name got want
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (exit $2, want $3)"; fi
}

# new_root NAME -> fresh fixture root with an empty scripts/ dir
new_root() {
  local root="$WORK/$1"
  mkdir -p "$root/scripts"
  printf '%s\n' "$root"
}

# A compliant emitter: canonical vocabulary, ISSUE_COUNT=, REASON= on non-OK.
write_clean() {
  cat > "$1" <<'EOF'
#!/usr/bin/env bash
issue_count=0
status="OK"
[ "$issue_count" -gt 0 ] && status="ERROR"
echo "=== CLEAN ==="
echo "STATUS=$status"
[ "$status" != "OK" ] && echo "REASON=first failure"
echo "ISSUE_COUNT=$issue_count"
echo "=== END CLEAN ==="
EOF
}

sweep() { # root [extra args...]
  local root="$1"; shift
  bash "$GUARD" --project-dir "$root" "$@" 2>&1
}

echo "=== A: real repo sweep (--strict) ==="
out="$(bash "$GUARD" --project-dir "$REPO_ROOT" --strict 2>&1)"; rc=$?
expect_exit "A1: real repo --strict exits 0" "$rc" 0
expect_line "A2: real repo STATUS=OK" "$out" "STATUS=OK"
expect_line "A3: real repo scanned something" "$out" "SCANNED_EMPTY=false"
emitters="$(grep -m1 '^STATUS_EMITTERS=' <<<"$out" | cut -d= -f2)"
if [ "${emitters:-0}" -ge 30 ]; then ok "A4: STATUS_EMITTERS >= 30 ($emitters)"; else bad "A4: STATUS_EMITTERS=$emitters"; fi
pending_lines="$(grep -cvE '^[[:space:]]*(#|$)' "$REPO_ROOT/scripts/structured-output-reason-pending.txt")"
expect_line "A5: REASON_PENDING matches the pending file" "$out" "REASON_PENDING=$pending_lines"
reason_emitters="$(grep -m1 '^REASON_EMITTERS=' <<<"$out" | cut -d= -f2)"
if [ "${reason_emitters:-0}" -ge 6 ]; then ok "A6: REASON_EMITTERS >= 6 ($reason_emitters)"; else bad "A6: REASON_EMITTERS=$reason_emitters"; fi

echo "=== B: clean fixture (control) ==="
root="$(new_root clean)"
write_clean "$root/scripts/check-clean.sh"
# A script that PARSES another script's STATUS= line is not an emitter.
cat > "$root/scripts/check-parser.sh" <<'EOF'
#!/usr/bin/env bash
out="$(bash other.sh)"
st="$(printf '%s\n' "$out" | grep -m1 '^STATUS=' | cut -d= -f2)"
EOF
# Non-check scripts are out of scope even if they drift.
cat > "$root/scripts/lint-other.sh" <<'EOF'
#!/usr/bin/env bash
echo "STATUS=FAIL"
EOF
out="$(sweep "$root" --strict)"; rc=$?
expect_exit "B1: clean fixture --strict exits 0" "$rc" 0
expect_line "B2: clean fixture STATUS=OK" "$out" "STATUS=OK"
expect_line "B3: only the real emitter counts" "$out" "STATUS_EMITTERS=1"
expect_line "B4: both check-*.sh scanned" "$out" "SCRIPTS_SCANNED=2"
if grep -q '^REASON=' <<<"$out"; then bad "B5: OK sweep carries no REASON line"; else ok "B5: OK sweep carries no REASON line"; fi

echo "=== C: vocabulary drift ==="
root="$(new_root vocab)"
printf '#!/usr/bin/env bash\necho "ISSUE_COUNT=1"\necho "REASON=x"\necho "STATUS=FAIL"\n' > "$root/scripts/check-literal.sh"
cat > "$root/scripts/check-shellvar.sh" <<'EOF'
#!/usr/bin/env bash
status="PASS"
[ -n "${X:-}" ] && status="WARN"
echo "STATUS=$status"
echo "REASON=x"
echo "ISSUE_COUNT=0"
EOF
cat > "$root/scripts/check-pyvar.sh" <<'EOF'
#!/usr/bin/env bash
python3 - <<'PY'
issues = []
status = "FAIL" if issues else "OK"
print("STATUS=%s" % status)
print("REASON=x")
print("ISSUE_COUNT=%d" % len(issues))
PY
EOF
cat > "$root/scripts/check-inline.sh" <<'EOF'
#!/usr/bin/env bash
n=0
echo "ISSUE_COUNT=$n"
echo "REASON=x"
echo "STATUS=$([ "$n" -gt 0 ] && echo FAIL || echo OK)"
EOF
cat > "$root/scripts/check-pyternary.sh" <<'EOF'
#!/usr/bin/env bash
python3 - <<'PY'
failed = False
print("STATUS=%s" % ("GOOD" if not failed else "ERROR"))
print("REASON=x")
print("ISSUE_COUNT=0")
PY
EOF
out="$(sweep "$root")"; rc=$?
expect_exit "C1: non-strict sweep exits 0 despite findings" "$rc" 0
expect_line "C2: STATUS=ERROR" "$out" "STATUS=ERROR"
expect_text "C3: literal FAIL flagged" "$out" "scripts/check-literal.sh emits STATUS=FAIL"
expect_text "C4: shell-variable PASS flagged" "$out" "scripts/check-shellvar.sh emits STATUS=PASS"
expect_text "C5: python-variable FAIL flagged" "$out" "scripts/check-pyvar.sh emits STATUS=FAIL"
expect_text "C6: inline \$(...) FAIL flagged" "$out" "scripts/check-inline.sh emits STATUS=FAIL"
expect_text "C7: python ternary GOOD flagged" "$out" "scripts/check-pyternary.sh emits STATUS=GOOD"
expect_no_text "C8: canonical WARN not flagged" "$out" "emits STATUS=WARN"
expect_no_text "C9: canonical OK not flagged" "$out" "emits STATUS=OK"
expect_line "C10: ISSUE_COUNT agrees with 5 rows" "$out" "ISSUE_COUNT=5"
expect_text "C11: REASON names the first finding" "$out" "REASON=noncanonical_status: scripts/check-inline.sh"
out="$(sweep "$root" --strict)"; rc=$?
expect_exit "C12: --strict exits 1 on drift" "$rc" 1

echo "=== D: missing REASON / ISSUE_COUNT, and the pending ratchet ==="
root="$(new_root reason)"
cat > "$root/scripts/check-noreason.sh" <<'EOF'
#!/usr/bin/env bash
echo "STATUS=ERROR"
echo "ISSUE_COUNT=1"
EOF
printf '#!/usr/bin/env bash\necho "STATUS=OK"\necho "REASON=x"\n' > "$root/scripts/check-nocount.sh"
out="$(sweep "$root" --strict)"; rc=$?
expect_exit "D1: missing REASON fails --strict" "$rc" 1
expect_text "D2: missing_reason reported" "$out" "TYPE=missing_reason MSG=scripts/check-noreason.sh"
expect_text "D3: missing_issue_count reported" "$out" "TYPE=missing_issue_count MSG=scripts/check-nocount.sh"
expect_no_text "D4: REASON-emitting script not flagged missing_reason" "$out" "missing_reason MSG=scripts/check-nocount.sh"
printf 'scripts/check-noreason.sh  # awaiting rollout\n' > "$root/scripts/structured-output-reason-pending.txt"
printf '#!/usr/bin/env bash\necho "STATUS=OK"\necho "REASON=x"\necho "ISSUE_COUNT=0"\n' > "$root/scripts/check-nocount.sh"
out="$(sweep "$root" --strict)"; rc=$?
expect_exit "D5: pending-listed script passes --strict" "$rc" 0
expect_line "D6: REASON_PENDING=1" "$out" "REASON_PENDING=1"

echo "=== E: stale pending entries (ratchet only shrinks) ==="
root="$(new_root stale)"
write_clean "$root/scripts/check-migrated.sh"
printf 'scripts/check-migrated.sh\nscripts/check-gone.sh\n' > "$root/scripts/structured-output-reason-pending.txt"
out="$(sweep "$root" --strict)"; rc=$?
expect_exit "E1: stale pending fails --strict" "$rc" 1
expect_text "E2: migrated script still listed is stale" "$out" "scripts/check-migrated.sh now emits REASON="
expect_text "E3: missing script still listed is stale" "$out" "scripts/check-gone.sh is in"
expect_line "E4: ISSUE_COUNT=2" "$out" "ISSUE_COUNT=2"

echo "=== F: empty scan is an error, not a clean pass ==="
root="$WORK/empty"; mkdir -p "$root"
out="$(sweep "$root" --strict)"; rc=$?
expect_exit "F1: nothing scanned fails --strict" "$rc" 1
expect_line "F2: SCANNED_EMPTY=true" "$out" "SCANNED_EMPTY=true"
expect_text "F3: nothing_scanned reported" "$out" "TYPE=nothing_scanned"

echo "=== G: argument handling ==="
bash "$GUARD" --bogus >/dev/null 2>&1; rc=$?
expect_exit "G1: unknown argument exits 2" "$rc" 2
bash "$GUARD" --project-dir "$WORK/no-such-dir" >/dev/null 2>&1; rc=$?
expect_exit "G2: missing --project-dir exits 2" "$rc" 2

echo "=== V: --validate mutants ==="
validate() { printf '%s\n' "$1" | bash "$GUARD" --validate 2>&1; }
# mutate SED_EXPR BLOCK -> BLOCK with one line-anchored edit applied
mutate() { printf '%s\n' "$2" | sed "$1"; }

good_ok=$'=== X ===\nSTATUS=OK\nISSUE_COUNT=0\n=== END X ==='
out="$(validate "$good_ok")"; rc=$?
expect_exit "V1: valid OK block passes" "$rc" 0
expect_line "V1b: validation STATUS=OK" "$out" "STATUS=OK"
expect_line "V1c: target status read" "$out" "TARGET_STATUS=OK"

good_err=$'=== X ===\nSTATUS=ERROR\nREASON=broken_thing: a.sh (+1 more)\nISSUE_COUNT=2\nISSUES:\n  - SEVERITY=ERROR TYPE=broken_thing MSG=a.sh\n  - SEVERITY=ERROR TYPE=broken_thing MSG=b.sh\n=== END X ==='
out="$(validate "$good_err")"; rc=$?
expect_exit "V2: valid ERROR block passes" "$rc" 0
expect_line "V2b: rows counted" "$out" "TARGET_ISSUE_ROWS=2"

out="$(validate "$(mutate '/^REASON=/d' "$good_err")")"; rc=$?
expect_exit "V3: ERROR without REASON fails" "$rc" 1
expect_text "V3b: missing_reason" "$out" "TYPE=missing_reason"

out="$(validate $'=== X ===\nSTATUS=OK\nREASON=spurious\nISSUE_COUNT=0\n=== END X ===')"; rc=$?
expect_exit "V4: OK with REASON fails" "$rc" 1
expect_text "V4b: reason_on_ok" "$out" "TYPE=reason_on_ok"

out="$(validate "$(mutate 's/^STATUS=ERROR$/STATUS=FAIL/' "$good_err")")"; rc=$?
expect_exit "V5: STATUS=FAIL fails" "$rc" 1
expect_text "V5b: noncanonical_status" "$out" "TYPE=noncanonical_status"

# The #2714 shape: ISSUE_COUNT=0 beneath populated issue rows.
out="$(validate "$(mutate 's/^ISSUE_COUNT=2$/ISSUE_COUNT=0/' "$good_err")")"; rc=$?
expect_exit "V6: ISSUE_COUNT=0 under 2 rows fails" "$rc" 1
expect_text "V6b: issue_count_mismatch" "$out" "TYPE=issue_count_mismatch"

long="$(printf 'x%.0s' $(seq 1 250))"
out="$(validate "$(mutate "s/^REASON=.*/REASON=$long/" "$good_err")")"; rc=$?
expect_exit "V7: 250-char REASON fails" "$rc" 1
expect_text "V7b: reason_too_long" "$out" "TYPE=reason_too_long"

out="$(validate "$good_ok"$'\nSTATUS=OK')"; rc=$?
expect_exit "V8: two STATUS lines fail" "$rc" 1
expect_text "V8b: status_line_count" "$out" "TYPE=status_line_count"

out="$(validate "$(sed '/^ISSUE_COUNT=/d' <<<"$good_ok")")"; rc=$?
expect_exit "V9: missing ISSUE_COUNT fails" "$rc" 1
expect_text "V9b: issue_count_line_count" "$out" "TYPE=issue_count_line_count"

out="$(validate "$(mutate 's/^REASON=.*/REASON=/' "$good_err")")"; rc=$?
expect_exit "V10: empty REASON fails" "$rc" 1
expect_text "V10b: empty_reason" "$out" "TYPE=empty_reason"

out="$(validate $'STATUS=ERROR\nREASON=first\nREASON=second\nISSUE_COUNT=1')"; rc=$?
expect_exit "V11: two REASON lines fail" "$rc" 1
expect_text "V11b: reason_line_count" "$out" "TYPE=reason_line_count"

out="$(validate "$(mutate 's/^ISSUE_COUNT=2$/ISSUE_COUNT=two/' "$good_err")")"; rc=$?
expect_exit "V12: non-integer ISSUE_COUNT fails" "$rc" 1
expect_text "V12b: bad_issue_count" "$out" "TYPE=bad_issue_count"

# A WARN block with no ISSUES: block carries no row count to disagree with.
warn_block=$'STATUS=WARN\nREASON=stranded_no_pr owner/repo:feat/x\nISSUE_COUNT=1'
out="$(validate "$warn_block")"; rc=$?
expect_exit "V13: WARN without an ISSUES block passes" "$rc" 0
expect_line "V13b: rows reported as none" "$out" "TARGET_ISSUE_ROWS=none"

printf '%s\n' "$good_err" > "$WORK/block.txt"
out="$(bash "$GUARD" --validate "$WORK/block.txt" 2>&1)"; rc=$?
expect_exit "V14: --validate FILE passes" "$rc" 0
expect_line "V14b: target named" "$out" "TARGET=$WORK/block.txt"
bash "$GUARD" --validate "$WORK/no-such-file" >/dev/null 2>&1; rc=$?
expect_exit "V15: unreadable --validate FILE exits 2" "$rc" 2

echo ""
echo "Passed: $PASS, Failed: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
