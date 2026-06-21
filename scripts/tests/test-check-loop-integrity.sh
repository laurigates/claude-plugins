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
[ -n "$WORK" ] && [ -d "$WORK" ] || { echo "bad sandbox dir" >&2; exit 1; }
trap 'rm -rf "$WORK"' EXIT

# Build a fixture root with all four files carrying the required tokens.
seed_clean() {
  local root="$1"
  mkdir -p "$root/.claude/rules"
  mkdir -p "$root/workflow-orchestration-plugin/skills/workflow-checkpoint-refactor"
  mkdir -p "$root/project-plugin/skills/project-test-loop"
  mkdir -p "$root/agent-patterns-plugin/skills/adversarial-review"

  cat > "$root/.claude/rules/loop-integrity.md" <<'EOF'
The stop condition is judged independently.
Every iteration leaves a compact state packet.
Fields: Verifier result, Changed since last run.
EOF

  cat > "$root/workflow-orchestration-plugin/skills/workflow-checkpoint-refactor/SKILL.md" <<'EOF'
Exit condition: all phases done.
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
