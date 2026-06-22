#!/usr/bin/env bash
# Regression tests for scripts/check-git-sandbox-guards.sh (issue #1692).
#
# Run: bash scripts/tests/test-check-git-sandbox-guards.sh
# Exit 0 = all tests pass, Exit 1 = failures
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LINTER="$SCRIPT_DIR/check-git-sandbox-guards.sh"
PASS=0
FAIL=0

WORK=$(mktemp -d) || { echo "mktemp -d failed" >&2; exit 1; }
[ -n "$WORK" ] && [ -d "$WORK" ] || { echo "bad sandbox dir" >&2; exit 1; }
trap 'rm -rf "$WORK"' EXIT

# Run the linter against an isolated root containing a single fixture script.
# Returns the ISSUE_COUNT line value.
run_count() {
  local fixture_dir="$1"
  bash "$LINTER" "$fixture_dir" 2>&1 | grep -E '^ISSUE_COUNT=' | cut -d= -f2
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

echo "=== check-git-sandbox-guards regression tests ==="

# 1. Unguarded `mktemp -d` feeding `git -C "$VAR" init` → FLAGGED.
d1="$WORK/unguarded"; mkdir -p "$d1"
cat > "$d1/test-bad.sh" <<'EOF'
#!/usr/bin/env bash
SBX=$(mktemp -d)
git -C "$SBX" init -q -b main
EOF
assert_count "unguarded mktemp -d + git -C is flagged" 1 "$d1"

# 2. Same script, but guarded on the assignment line → NOT flagged.
d2="$WORK/guarded"; mkdir -p "$d2"
cat > "$d2/test-good.sh" <<'EOF'
#!/usr/bin/env bash
SBX=$(mktemp -d) || { echo "mktemp -d failed" >&2; exit 1; }
git -C "$SBX" init -q -b main
EOF
assert_count "guarded mktemp -d (|| exit) is not flagged" 0 "$d2"

# 3. Guarded via a [ -n "$VAR" ] test on a following line → NOT flagged.
d3="$WORK/guarded-test"; mkdir -p "$d3"
cat > "$d3/test-good2.sh" <<'EOF'
#!/usr/bin/env bash
SBX=$(mktemp -d)
[ -n "$SBX" ] && [ -d "$SBX" ] || exit 1
git -C "$SBX" init -q
EOF
assert_count "guarded mktemp -d ([ -n ] next line) is not flagged" 0 "$d3"

# 4. A temp FILE (mktemp without -d) in a git script → NOT flagged (can't be a repo/cd target).
d4="$WORK/tempfile"; mkdir -p "$d4"
cat > "$d4/test-file.sh" <<'EOF'
#!/usr/bin/env bash
TMP=$(mktemp)
git init -q
echo data > "$TMP"
EOF
assert_count "unguarded mktemp (file, no -d) is not flagged" 0 "$d4"

# 5. Unguarded `mktemp -d` in a script with NO git op at all → NOT flagged.
d5="$WORK/nogit"; mkdir -p "$d5"
cat > "$d5/test-nogit.sh" <<'EOF'
#!/usr/bin/env bash
SBX=$(mktemp -d)
cp foo "$SBX/"
EOF
assert_count "unguarded mktemp -d with no git op is not flagged" 0 "$d5"

# 6. Unguarded `mktemp -d` reaching git via a loop variable (indirection) → FLAGGED
#    (the file-level gate catches this even though the var is used indirectly).
d6="$WORK/indirect"; mkdir -p "$d6"
cat > "$d6/test-indirect.sh" <<'EOF'
#!/usr/bin/env bash
A=$(mktemp -d)
B=$(mktemp -d)
for d in "$A" "$B"; do git -C "$d" init -q; done
EOF
assert_count "unguarded mktemp -d reaching git via a loop var is flagged" 2 "$d6"

# 7. `git init --bare "$VAR"` with an unguarded dir → FLAGGED.
d7="$WORK/bare"; mkdir -p "$d7"
cat > "$d7/test-bare.sh" <<'EOF'
#!/usr/bin/env bash
ORIGIN=$(mktemp -d)
git init -q --bare "$ORIGIN"
EOF
assert_count "unguarded mktemp -d + git init --bare is flagged" 1 "$d7"

# 8. Unguarded `mktemp -d` + git op inside the gitignored dist/ rulesync build
#    output → NOT flagged (pruned, mirroring the #1492/#1548 worktrees prune). A
#    control copy OUTSIDE dist/ in the same root IS flagged, proving the prune is
#    scoped (count == 1, not 0 or 2).
d8="$WORK/dist-prune"; mkdir -p "$d8/dist/opencode/skills/x/scripts/tests"
cat > "$d8/dist/opencode/skills/x/scripts/tests/test-leak.sh" <<'EOF'
#!/usr/bin/env bash
SBX=$(mktemp -d)
git -C "$SBX" init -q
EOF
cat > "$d8/real-bad.sh" <<'EOF'
#!/usr/bin/env bash
SBX=$(mktemp -d)
git -C "$SBX" init -q
EOF
assert_count "dist/ build output is pruned (only the non-dist script is flagged)" 1 "$d8"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
