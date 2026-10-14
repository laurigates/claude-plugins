#!/usr/bin/env bash
# shellcheck disable=SC2015  # file-level: `[ -n ] && [ -d ] || die` is a guard, not if-then-else (must precede the first command)
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

# 8. Unguarded `mktemp -d` + git op inside the gitignored dist/ OpenCode export build
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

# Rule 2 (issues #1745, #3080): a `*-plugin/hooks/test-*.sh` suite running git
# must unset GIT_DIR first — in ANY plugin, not only hooks-plugin. Every fixture
# here guards its mktemp, so only rule 2 can fire.
mk_suite() { # mk_suite <root> <plugin> <name> <body>
  mkdir -p "$1/$2/hooks"
  printf '#!/usr/bin/env bash\nset -euo pipefail\n%s\n' "$4" > "$1/$2/hooks/$3"
# Rule 2 (issue #1745, PR #3077): a hooks-plugin/hooks/test-*.sh suite running
# git must unset GIT_DIR first. Every fixture here guards its mktemp, so only
# rule 2 can fire.
mk_suite() { # mk_suite <root> <name> <body>
  mkdir -p "$1/hooks-plugin/hooks"
  printf '#!/usr/bin/env bash\nset -euo pipefail\n%s\n' "$3" > "$1/hooks-plugin/hooks/$2"
}
# shellcheck disable=SC2016  # fixture text: the $ is literal script source
SBX_LINES='SBX=$(mktemp -d) || exit 1
git -C "$SBX" init -q'

# 9. hooks-plugin suite runs git with no unset → FLAGGED.
d9="$WORK/r2-missing"; mk_suite "$d9" hooks-plugin test-x.sh "$SBX_LINES"
assert_count "hooks-plugin suite running git without unset GIT_DIR is flagged" 1 "$d9"

# 10. The widened scope (#3080): a suite in another plugin is FLAGGED too.
d10="$WORK/r2-other-plugin"; mk_suite "$d10" session-plugin test-y.sh "$SBX_LINES"
assert_count "non-hooks-plugin suite running git without unset GIT_DIR is flagged" 1 "$d10"

# 11. Same suite with the unset before the first git command → NOT flagged.
d11="$WORK/r2-ok"; mk_suite "$d11" session-plugin test-y.sh "unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR
$SBX_LINES"
assert_count "suite with unset GIT_DIR first is not flagged" 0 "$d11"

# 12. Unset placed AFTER the first git command → FLAGGED (too late).
d12="$WORK/r2-late"; mk_suite "$d12" git-plugin test-z.sh "$SBX_LINES
unset GIT_DIR GIT_WORK_TREE"
assert_count "unset GIT_DIR after the first git command is flagged" 1 "$d12"

# 13. A git command only quoted inside a test-case string → NOT flagged.
d13="$WORK/r2-string"; mk_suite "$d13" kubernetes-plugin test-k.sh 'assert_deny "git commit on main" "git commit -m x"'
assert_count "git quoted in a test-case string is not flagged" 0 "$d13"

# 14. A hook script named test-*.sh that its plugin's manifest registers → NOT
#     flagged; a test-*.sh outside */hooks/ → NOT flagged (rule 2 is scoped).
d14="$WORK/r2-registered"; mk_suite "$d14" hooks-plugin test-verification.sh "$SBX_LINES"
mkdir -p "$d14/hooks-plugin/.claude-plugin"
printf '{"hooks":{"TaskCompleted":[{"hooks":[{"type":"command","command":"bash hooks/test-verification.sh"}]}]}}\n' \
  > "$d14/hooks-plugin/.claude-plugin/plugin.json"
mkdir -p "$d14/other-plugin/scripts"
printf '#!/usr/bin/env bash\n%s\n' "$SBX_LINES" > "$d14/other-plugin/scripts/test-y.sh"
assert_count "registered hook script and out-of-scope test script are not flagged" 0 "$d14"
# 9. Suite runs git with no unset → FLAGGED.
d9="$WORK/r2-missing"; mk_suite "$d9" test-x.sh "$SBX_LINES"
assert_count "hook suite running git without unset GIT_DIR is flagged" 1 "$d9"

# 10. Same suite with the unset before the first git command → NOT flagged.
d10="$WORK/r2-ok"; mk_suite "$d10" test-x.sh "unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR
$SBX_LINES"
assert_count "hook suite with unset GIT_DIR first is not flagged" 0 "$d10"

# 11. Unset placed AFTER the first git command → FLAGGED (too late).
d11="$WORK/r2-late"; mk_suite "$d11" test-x.sh "$SBX_LINES
unset GIT_DIR GIT_WORK_TREE"
assert_count "unset GIT_DIR after the first git command is flagged" 1 "$d11"

# 12. A git command only quoted inside a test-case string → NOT flagged.
d12="$WORK/r2-string"; mk_suite "$d12" test-x.sh 'assert_deny "git commit on main" "git commit -m x"'
assert_count "git quoted in a test-case string is not flagged" 0 "$d12"

# 13. A hook script named test-*.sh that the manifest registers → NOT flagged;
#     the same file outside hooks-plugin/hooks → NOT flagged (rule 2 is scoped).
d13="$WORK/r2-registered"; mk_suite "$d13" test-verification.sh "$SBX_LINES"
mkdir -p "$d13/hooks-plugin/.claude-plugin"
printf '{"hooks":{"TaskCompleted":[{"hooks":[{"type":"command","command":"bash hooks/test-verification.sh"}]}]}}\n' \
  > "$d13/hooks-plugin/.claude-plugin/plugin.json"
mkdir -p "$d13/other-plugin/hooks"
printf '#!/usr/bin/env bash\n%s\n' "$SBX_LINES" > "$d13/other-plugin/hooks/test-y.sh"
assert_count "registered hook script and out-of-scope suite are not flagged" 0 "$d13"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
