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

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
