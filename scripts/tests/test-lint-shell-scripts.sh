#!/usr/bin/env bash
# Regression tests for scripts/lint-shell-scripts.sh.
#
# The linter enforces .claude/rules/shell-scripting.md across every *.sh file:
# #!/usr/bin/env bash shebang, error-handling flags, the standard block()
# function, and TOOL_NAME (not TOOL) variable naming. The severity split is
# load-bearing: missing `set` flags are an ERROR for hook scripts (path contains
# /hooks/) and only a WARN for other scripts — matching the rule, which mandates
# the flags only for hooks. This test pins that split plus the always-ERROR
# checks so a future edit can't silently relax them.
#
# Run: bash scripts/tests/test-lint-shell-scripts.sh
# Exit 0 = all tests pass, Exit 1 = failures
# shellcheck disable=SC2015   # file-level: `[ -n ] && [ -d ] || { exit }` sandbox
#                             # guard is a deliberate idiom here (see shell-scripting.md)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LINTER="$SCRIPT_DIR/lint-shell-scripts.sh"
PASS=0
FAIL=0

WORK=$(mktemp -d) || { echo "mktemp -d failed" >&2; exit 1; }
[ -n "$WORK" ] && [ -d "$WORK" ] || { echo "bad sandbox dir" >&2; exit 1; }
trap 'rm -rf "$WORK"' EXIT

# Run the linter against an isolated fixture root. Echoes "<errors> <warnings> <exit>".
run_lint() {
  local dir="$1" out rc
  out=$(bash "$LINTER" "$dir" 2>&1); rc=$?
  local summary errors warnings
  summary=$(printf '%s\n' "$out" | grep -E '^Shell script lint:')
  errors=$(printf '%s' "$summary" | sed -E 's/.* ([0-9]+) error.*/\1/')
  warnings=$(printf '%s' "$summary" | sed -E 's/.* ([0-9]+) warning.*/\1/')
  printf '%s %s %s' "${errors:-?}" "${warnings:-?}" "$rc"
}

# assert_lint <desc> <expected "errors warnings exit"> <dir>
assert_lint() {
  local desc="$1" expected="$2" dir="$3" got
  got=$(run_lint "$dir")
  if [ "$got" = "$expected" ]; then
    printf "  PASS: %s\n" "$desc"; PASS=$((PASS + 1))
  else
    printf "  FAIL: %s (expected '%s', got '%s')\n" "$desc" "$expected" "$got"; FAIL=$((FAIL + 1))
  fi
}

echo "=== lint-shell-scripts regression tests ==="

# 1. Fully compliant script → 0 errors, 0 warnings, exit 0.
d1="$WORK/good"; mkdir -p "$d1"
cat > "$d1/good.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "hello"
EOF
assert_lint "compliant script passes clean" "0 0 0" "$d1"

# 2. #!/bin/bash shebang → ERROR (always), exit 1. The bad-shebang non-hook
#    script also lacks set flags, so it additionally WARNs (1 error, 1 warning).
d2="$WORK/badshebang"; mkdir -p "$d2"
cat > "$d2/bad.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
echo "wrong shebang"
EOF
assert_lint "#!/bin/bash shebang is an error" "1 0 1" "$d2"

# 3. Non-hook script missing set flags → WARN only, exit 0 (severity split).
d3="$WORK/noset-nonhook"; mkdir -p "$d3"
cat > "$d3/util.sh" <<'EOF'
#!/usr/bin/env bash
echo "no set flags, but not a hook"
EOF
assert_lint "non-hook missing set flags is a warning, not an error" "0 1 0" "$d3"

# 4. Hook script missing set flags → ERROR, exit 1. Nested so REL_PATH contains
#    "/hooks/" (the linter's hook detector needs the leading slash).
d4="$WORK/noset-hook"; mkdir -p "$d4/plugin/hooks"
cat > "$d4/plugin/hooks/guard.sh" <<'EOF'
#!/usr/bin/env bash
echo "a hook with no set flags"
EOF
assert_lint "hook missing set flags is an error" "1 0 1" "$d4"

# 5. Hook using a non-standard block function name → ERROR. The body's
#    `echo >&2` + `exit 2` also trips the inline-block WARN, so the count is
#    1 error + 1 warning, exit 1.
d5="$WORK/badblock"; mkdir -p "$d5/plugin/hooks"
cat > "$d5/plugin/hooks/block.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
block_with_reminder() {
    echo "$1" >&2
    exit 2
}
block_with_reminder "nope"
EOF
assert_lint "non-standard block_with_reminder() is an error (+inline-block warn)" "1 1 1" "$d5"

# 6. TOOL= (instead of TOOL_NAME=) jq tool-name extraction → ERROR, exit 1.
d6="$WORK/badvar"; mkdir -p "$d6"
cat > "$d6/var.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')
echo "$TOOL"
EOF
assert_lint "TOOL (not TOOL_NAME) variable is an error" "1 0 1" "$d6"

# 7-11. Check 5: portable in-place sed. Each single-platform spelling fails on
#    the other platform WITHOUT editing, so both are errors; the attached-suffix
#    form and the two documented exemptions must stay clean.

# 7. BSD-only empty suffix -> ERROR (GNU sed would exit 2 without editing).
d7="$WORK/sed-bsd"; mkdir -p "$d7"
cat > "$d7/bsd.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
sed -i '' "s/a/b/" f.txt
EOF
assert_lint "BSD-only in-place sed is an error" "1 0 1" "$d7"

# 8. GNU-only detached script -> ERROR (BSD sed eats the script as a suffix).
d8="$WORK/sed-gnu"; mkdir -p "$d8"
cat > "$d8/gnu.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
sed -i "s/a/b/" f.txt
EOF
assert_lint "GNU-only in-place sed is an error" "1 0 1" "$d8"

# 9. Attached suffix -> clean. This is the spelling both implementations accept.
d9="$WORK/sed-ok"; mkdir -p "$d9"
cat > "$d9/ok.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
sed -i.bak "s/a/b/" f.txt
rm -f f.txt.bak
EOF
assert_lint "attached-suffix in-place sed passes clean" "0 0 0" "$d9"

# 10. A try-GNU-then-fall-back-to-BSD pair contains BOTH spellings and is
#     nonetheless portable; the portable-sed-ok tag is its escape hatch.
d10="$WORK/sed-marked"; mkdir -p "$d10"
cat > "$d10/marked.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
sed -i "s/a/b/" f 2>/dev/null || sed -i '' "s/a/b/" f  # portable-sed-ok
EOF
assert_lint "portable-sed-ok exempts a deliberate fallback pair" "0 0 0" "$d10"

# 11. test-*.sh carries both spellings as fixture STRINGS (data, not commands),
#     so the whole file is skipped for this check.
d11="$WORK/sed-fixture"; mkdir -p "$d11"
cat > "$d11/test-thing.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
sed -i '' "s/a/b/" f.txt
EOF
assert_lint "test-*.sh fixtures are skipped by the sed check" "0 0 0" "$d11"

# 12-17. Check 6: printf/echo of a variable piped into grep -q under pipefail
#    (#2959). grep -q exits on its first match, the writer takes SIGPIPE, and
#    pipefail reports a hit as a miss. Scope is any *.sh directly inside a
#    tests/ directory, plus <plugin>/hooks/test-*.sh, that enables pipefail.

# 12. Positive: the exact line-77 shape from test-lint-package-references.sh,
#     plus an `echo | grep -qx` in a hook suite -> one ERROR each, exit 1.
d12="$WORK/pipe-grep-q"; mkdir -p "$d12/scripts/tests" "$d12/demo-plugin/hooks"
cat > "$d12/scripts/tests/test-demo.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
out="$(./linter 2>&1)"; status=$?
if [ "$status" -ne 0 ] && printf '%s' "$out" | grep -qF "$rel"; then echo ok; fi
EOF
cat > "$d12/demo-plugin/hooks/test-demo-hook.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
out="$(./hook)"
echo "$out" | grep -qx "STATUS=OK" || exit 1
EOF
assert_lint "printf/echo \"\$var\" | grep -q in a pipefail suite is an error" "2 0 1" "$d12"

# 13. Negative: the here-string fix, a real-command producer, and a comment
#     that merely names the hazard all pass clean.
d13="$WORK/herestring"; mkdir -p "$d13/scripts/tests"
cat > "$d13/scripts/tests/test-demo.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
# Here-string, not `printf '%s' "$out" | grep -q`: see #2959.
out="$(./linter 2>&1)"
if grep -qF "$rel" <<<"$out"; then echo ok; fi
if ./linter | grep -q "STATUS=OK"; then echo ok; fi
printf '%s\n' "$out" | grep -c "x" || true
EOF
assert_lint "here-string, real-command producer, and comments pass clean" "0 0 0" "$d13"

# 14. Negative: the shape inside a heredoc body is fixture DATA written to
#     another file, not a command of this suite.
d14="$WORK/heredoc-body"; mkdir -p "$d14/demo-plugin/hooks"
cat > "$d14/demo-plugin/hooks/test-demo-hook.sh" <<'OUTER'
#!/usr/bin/env bash
set -euo pipefail
cat > "$WORK/fixture-hook.sh" <<'EOF'
INPUT=$(cat)
if echo "$INPUT" | grep -q kubectl; then exit 2; fi
EOF
echo done
OUTER
assert_lint "the shape inside a heredoc fixture body is not flagged" "0 0 0" "$d14"

# 15. Negative: without pipefail the pipeline's status is grep's, so no race.
d15="$WORK/no-pipefail"; mkdir -p "$d15/scripts/tests"
cat > "$d15/scripts/tests/test-demo.sh" <<'EOF'
#!/usr/bin/env bash
set -u
printf '%s' "$out" | grep -q "x" && echo hit
EOF
assert_lint "no pipefail -> not flagged" "0 0 0" "$d15"

# 16. Negative: out of scope (not a scripts/tests or hooks/test-* suite).
d16="$WORK/out-of-scope"; mkdir -p "$d16/scripts"
cat > "$d16/scripts/check-demo.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s' "$out" | grep -q "x" && echo hit
EOF
assert_lint "a non-test script is out of Check 6 scope" "0 0 0" "$d16"

# 17. Empty tree: nothing to scan -> clean, exit 0.
d17="$WORK/empty"; mkdir -p "$d17"
assert_lint "empty tree passes clean" "0 0 0" "$d17"

# 18. Positive: the widened scope. A per-skill suite, a plugin-level suite and
#     an experiment suite each carry the shape -> one ERROR each, exit 1. The
#     experiment suite adds a -q placed after a pattern holding a balanced
#     `(...)` group, which must still read as -q (4 errors in all).
d18="$WORK/wide-scope"
mkdir -p "$d18/demo-plugin/skills/demo-skill/scripts/tests" \
  "$d18/demo-plugin/scripts/tests" "$d18/experiments/demo/tests"
cat > "$d18/demo-plugin/skills/demo-skill/scripts/tests/test-demo-skill.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
out=$(bash ../demo.sh)
echo "$out" | grep -q "^STATUS=OK$" || echo "FAIL"
EOF
cat > "$d18/demo-plugin/scripts/tests/test-demo-plugin.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
out=$(bash ../demo.sh)
if printf '%s\n' "$out" | grep -qF -- "needle"; then echo ok; fi
EOF
cat > "$d18/experiments/demo/tests/test-demo-exp.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
out=$(bash ../demo.sh)
assert "$(printf '%s' "$out" | grep -qE 'x' && echo true || echo false)"
echo "$out" | grep -E "^(OK)$" -q || echo "FAIL"
EOF
assert_lint "printf/echo | grep -q in skill, plugin and experiment suites is an error" "4 0 1" "$d18"

# 19. Negative: in the widened scope, the here-string fix and a `grep -c`
#     inside $(...) followed by `-eq` both pass (the `)` ends grep's words, so
#     -eq is not read as -q), and a non-suite script beside the suites (a
#     tests/fixtures/ file, a skill's own scripts/) is out of scope.
d19="$WORK/wide-scope-clean"
mkdir -p "$d19/demo-plugin/skills/demo-skill/scripts/tests/fixtures"
cat > "$d19/demo-plugin/skills/demo-skill/scripts/tests/test-demo-skill.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
out=$(bash ../demo.sh)
grep -q "^STATUS=OK$" <<<"$out" || echo "FAIL"
[ "$(echo "$out" | grep -c '^LINE=')" -eq 1 ] || echo "FAIL"
EOF
cat > "$d19/demo-plugin/skills/demo-skill/scripts/tests/fixtures/bad.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "$1" | grep -q "x" && echo hit
EOF
cat > "$d19/demo-plugin/skills/demo-skill/scripts/demo.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "$1" | grep -q "x" && echo hit
EOF
assert_lint "here-string, grep -c ... -eq, fixtures/ and non-suite scripts pass clean" "0 0 0" "$d19"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
