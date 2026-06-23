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

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
