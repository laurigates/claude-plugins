#!/usr/bin/env bash
# Regression tests for scripts/check-loop-integrity.sh (loop-integrity convention).
#
# Run: bash scripts/tests/test-check-loop-integrity.sh
# Exit 0 = all tests pass, Exit 1 = failures
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUARD="$SCRIPT_DIR/check-loop-integrity.sh"
PASS=0
FAIL=0

WORK=$(mktemp -d) || { echo "mktemp -d failed" >&2; exit 1; }
if [ -z "$WORK" ] || [ ! -d "$WORK" ]; then echo "bad sandbox dir" >&2; exit 1; fi
trap 'rm -rf "$WORK"' EXIT

# Build a fixture root with all four files carrying the required tokens.
seed_clean() {
  local root="$1"
  mkdir -p "$root/.claude/rules"
  mkdir -p "$root/workflow-orchestration-plugin/skills/workflow-checkpoint-refactor"
  mkdir -p "$root/project-plugin/skills/project-test-loop"
  mkdir -p "$root/agent-patterns-plugin/skills/adversarial-review"
  mkdir -p "$root/agent-patterns-plugin/skills/execution-grounded-review"

  cat > "$root/.claude/rules/loop-integrity.md" <<'EOF'
The stop condition is judged independently.
Every iteration leaves a compact state packet.
Fields: Verifier result, Changed since last run.
- Ordering / preconditions: which steps must precede which
- Next target: what the last iteration chose to do next
EOF

  cat > "$root/workflow-orchestration-plugin/skills/workflow-checkpoint-refactor/SKILL.md" <<'EOF'
Exit condition: all phases done.
Next target: Phase 2
- Ordering / preconditions: after Phase 1
- Verifier result: PASS
- Changed since last run: nothing
gate done on an independent verifier.
See .claude/rules/loop-integrity.md
EOF

  cat > "$root/project-plugin/skills/project-test-loop/SKILL.md" <<'EOF'
See .claude/rules/loop-integrity.md
EOF

  cat > "$root/agent-patterns-plugin/skills/adversarial-review/SKILL.md" <<'EOF'
See .claude/rules/loop-integrity.md
EOF

  cat > "$root/agent-patterns-plugin/skills/execution-grounded-review/SKILL.md" <<'EOF'
See .claude/rules/loop-integrity.md
"evidenceSpan": { "type": "string" }
**Attribution bound:** at most 3 search rounds
"limitations": { "type": "array", "minItems": 1 }
LIMITATIONS:
single entry "none" — never omit the field. Be honest in your response.
**and** every Step 1 step ran to completion
stop: emit no ledger and no `VERDICT` line, name the missing
Speculative risks
passes on the merge-base fails on the head
separate new failures from pre-existing ones
EOF
}

run_count() {
  bash "$GUARD" "$1" 2>&1 | grep -E '^ISSUE_COUNT=' | cut -d= -f2
}

assert_count() {
  local desc="$1" expected="$2" dir="$3" got
  got=$(run_count "$dir")
  if [ "$got" = "$expected" ]; then
    printf "  PASS: %s\n" "$desc"; PASS=$((PASS + 1))
  else
    printf "  FAIL: %s (expected ISSUE_COUNT=%s, got %s)\n" "$desc" "$expected" "$got"; FAIL=$((FAIL + 1))
  fi
}

echo "=== check-loop-integrity regression tests ==="

# 1. Fully-populated fixture → no issues.
clean="$WORK/clean"; seed_clean "$clean"
assert_count "clean fixture (all tokens present)" 0 "$clean"

# 2. Checkpoint skill loses the Verifier-result field → flagged (self-judged revert).
no_verifier="$WORK/no_verifier"; seed_clean "$no_verifier"
ck="$no_verifier/workflow-orchestration-plugin/skills/workflow-checkpoint-refactor/SKILL.md"
# Strip the Verifier-result line.
grep -v 'Verifier result' "$ck" > "$ck.tmp" && mv "$ck.tmp" "$ck"
assert_count "checkpoint missing Verifier-result is flagged" 1 "$no_verifier"

# 3. Rule file loses Pillar 1 (independent stop condition) → flagged.
no_pillar1="$WORK/no_pillar1"; seed_clean "$no_pillar1"
rule="$no_pillar1/.claude/rules/loop-integrity.md"
grep -v 'independently' "$rule" > "$rule.tmp" && mv "$rule.tmp" "$rule"
assert_count "rule missing Pillar 1 is flagged" 1 "$no_pillar1"

# 4. Sibling skill loses its cross-reference → flagged.
no_xref="$WORK/no_xref"; seed_clean "$no_xref"
tl="$no_xref/project-plugin/skills/project-test-loop/SKILL.md"
: > "$tl"   # empty out the cross-reference
assert_count "test-loop missing cross-reference is flagged" 1 "$no_xref"

# 4b. execution-grounded-review (behaviour verifier sibling) loses its xref → flagged.
no_egr="$WORK/no_egr"; seed_clean "$no_egr"
egr="$no_egr/agent-patterns-plugin/skills/execution-grounded-review/SKILL.md"
grep -v 'loop-integrity.md' "$egr" > "$egr.tmp" && mv "$egr.tmp" "$egr"   # strip only the cross-reference
assert_count "execution-grounded-review missing cross-reference is flagged" 1 "$no_egr"

# strip_mutant NAME RELPATH TOKEN DESC — one fixture per token, stripping only the
# line that carries TOKEN, so each case is a single-token mutant (expects exactly 1).
strip_mutant() {
  local name="$1" rel="$2" token="$3" desc="$4" dir f
  dir="$WORK/$name"; seed_clean "$dir"
  f="$dir/$rel"
  grep -vF "$token" "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  assert_count "$desc" 1 "$dir"
}

RULE_REL=".claude/rules/loop-integrity.md"
CK_REL="workflow-orchestration-plugin/skills/workflow-checkpoint-refactor/SKILL.md"
EGR_REL="agent-patterns-plugin/skills/execution-grounded-review/SKILL.md"

# 4c-4f. Pillar 2 ordering / next-target fields (#2693): the rule names them and
# the checkpoint plan template (the loop's state packet) carries them.
strip_mutant rule_no_ordering "$RULE_REL" "Ordering / preconditions" \
  "rule missing the Ordering / preconditions field is flagged (#2693)"
strip_mutant rule_no_next "$RULE_REL" "Next target" \
  "rule missing the Next target field is flagged (#2693)"
strip_mutant ck_no_ordering "$CK_REL" "Ordering / preconditions" \
  "checkpoint plan missing Ordering / preconditions is flagged (#2693)"
strip_mutant ck_no_next "$CK_REL" "Next target" \
  "checkpoint plan missing Next target is flagged (#2693)"

# 4g-4h. execution-grounded-review attribution step (#2694): the stated upper
# bound on the trace search, and the ledger's checkable evidence span.
strip_mutant egr_no_bound "$EGR_REL" "Attribution bound" \
  "execution-grounded-review missing the attribution bound is flagged (#2694)"
strip_mutant egr_no_span "$EGR_REL" "evidenceSpan" \
  "execution-grounded-review missing the evidenceSpan ledger field is flagged (#2694)"

# 4h'. Narrative-changing limitations (#2870): the LEDGER field and the report
# block that must precede the verdict.
strip_mutant egr_no_limitations "$EGR_REL" '"limitations"' \
  "execution-grounded-review missing the limitations ledger field is flagged (#2870)"
strip_mutant egr_no_limits_block "$EGR_REL" "LIMITATIONS:" \
  "execution-grounded-review missing the LIMITATIONS report block is flagged (#2870)"
strip_mutant egr_no_honesty "$EGR_REL" "never omit the field. Be honest in your response." \
  "execution-grounded-review missing the honesty instruction is flagged (#2870)"
strip_mutant egr_no_step1_gate "$EGR_REL" "every Step 1 step ran to completion" \
  "execution-grounded-review missing the Step 1 verdict gate is flagged (#2871)"
strip_mutant egr_no_abstain "$EGR_REL" "stop: emit no ledger and no" \
  "execution-grounded-review missing the no-inputs abstain path is flagged (#2871)"
strip_mutant egr_no_grounding "$EGR_REL" "Speculative risks" \
  "execution-grounded-review missing the grounded-limitations rule is flagged (#2871)"
strip_mutant egr_no_noregress "$EGR_REL" "passes on the merge-base fails on the head" \
  "execution-grounded-review missing the no-regression criterion is flagged"
strip_mutant egr_no_basecmp "$EGR_REL" "separate new failures from pre-existing ones" \
  "execution-grounded-review missing the merge-base comparison is flagged"

# 4i. Guard integrity: the real repository satisfies every token the guard
# requires, so the fixture tokens above are the ones the shipped files carry.
real_root="$(cd "$SCRIPT_DIR/.." && pwd)"
if bash "$GUARD" --strict "$real_root" >/dev/null 2>&1; then
  printf "  PASS: real repository passes --strict\n"; PASS=$((PASS + 1))
else
  printf "  FAIL: real repository should pass --strict\n"; FAIL=$((FAIL + 1))
fi

# 5. --strict exits non-zero on issues, zero when clean.
if bash "$GUARD" --strict "$clean" >/dev/null 2>&1; then
  printf "  PASS: --strict exits 0 on clean fixture\n"; PASS=$((PASS + 1))
else
  printf "  FAIL: --strict should exit 0 on clean fixture\n"; FAIL=$((FAIL + 1))
fi
if bash "$GUARD" --strict "$no_pillar1" >/dev/null 2>&1; then
  printf "  FAIL: --strict should exit 1 when issues found\n"; FAIL=$((FAIL + 1))
else
  printf "  PASS: --strict exits 1 when issues found\n"; PASS=$((PASS + 1))
fi

# 6. REASON= on ERROR names the first finding, is absent on OK, and both outputs
#    satisfy the structured-output contract (#2760).
CONTRACT="$SCRIPT_DIR/check-structured-output-contract.sh"
check_true() { # desc, condition-result
  if [ "$2" = "true" ]; then printf "  PASS: %s\n" "$1"; PASS=$((PASS + 1)); else
    printf "  FAIL: %s\n" "$1"; FAIL=$((FAIL + 1)); fi
}
out_bad="$(bash "$GUARD" "$no_pillar1" 2>&1)"
out_ok="$(bash "$GUARD" "$clean" 2>&1)"
grep -qxF 'REASON=missing_token: .claude/rules/loop-integrity.md: Pillar 1 (independent stop condition) dropped from the rule' <<<"$out_bad" && r=true || r=false
check_true "ERROR output carries REASON= naming the first finding, opened by its TYPE= (#3165)" "$r"
grep -q '^  - SEVERITY=ERROR TYPE=missing_token FILE=.claude/rules/loop-integrity.md TOKEN=' <<<"$out_bad" && r=true || r=false
check_true "missing-token ISSUES row carries TYPE=missing_token (#3165)" "$r"
nofile="$WORK/no_file"; seed_clean "$nofile"; rm -f "$nofile/$CK_REL"
out_nofile="$(bash "$GUARD" "$nofile" 2>&1)"
grep -q "^REASON=missing_file: $CK_REL: missing file (" <<<"$out_nofile" && r=true || r=false
check_true "missing-file REASON= opens with TYPE=missing_file (#3165)" "$r"
grep -q "^  - SEVERITY=ERROR TYPE=missing_file FILE=$CK_REL MSG=" <<<"$out_nofile" && r=true || r=false
check_true "missing-file ISSUES row carries TYPE=missing_file (#3165)" "$r"
printf '%s\n' "$out_nofile" | bash "$CONTRACT" --validate - >/dev/null 2>&1 && r=true || r=false
check_true "missing-file ERROR output satisfies the structured-output contract" "$r"
two="$WORK/two_findings"; seed_clean "$two"
grep -v 'independently' "$two/$RULE_REL" > "$two/$RULE_REL.tmp" && mv "$two/$RULE_REL.tmp" "$two/$RULE_REL"
grep -v 'Verifier result' "$two/$CK_REL" > "$two/$CK_REL.tmp" && mv "$two/$CK_REL.tmp" "$two/$CK_REL"
out_two="$(bash "$GUARD" "$two" 2>&1)"
grep -q '^REASON=.* (+[1-9][0-9]* more)$' <<<"$out_two" && r=true || r=false
check_true "REASON= appends (+N more) when several findings exist" "$r"
grep -q '^REASON=' <<<"$out_ok" && r=false || r=true
check_true "OK output carries no REASON=" "$r"
printf '%s\n' "$out_bad" | bash "$CONTRACT" --validate - >/dev/null 2>&1 && r=true || r=false
check_true "ERROR output satisfies the structured-output contract" "$r"
printf '%s\n' "$out_ok" | bash "$CONTRACT" --validate - >/dev/null 2>&1 && r=true || r=false
check_true "OK output satisfies the structured-output contract" "$r"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
