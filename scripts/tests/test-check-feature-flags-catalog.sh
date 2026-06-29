#!/usr/bin/env bash
# shellcheck disable=SC2016   # file-level (must precede first command): the printf format strings intentionally emit literal ${...} / %s into generated fixture scripts
# Regression tests for check-feature-flags-catalog.sh
#
# Run: bash scripts/tests/test-check-feature-flags-catalog.sh
# Exit 0 = all tests pass, Exit 1 = failures
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/check-feature-flags-catalog.sh"
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0
FAIL=0

pass() { printf "  PASS: %s\n" "$1"; PASS=$((PASS + 1)); }
fail() { printf "  FAIL: %s\n" "$1"; FAIL=$((FAIL + 1)); }

# Build a throwaway project: a catalog doc + one hook reading a flag.
# $1 = flag the hook reads, $2 = flag the catalog documents (empty = none).
make_project() {
    local hook_flag="$1" doc_flag="${2:-}"
    local dir; dir="$(mktemp -d)"
    mkdir -p "$dir/hooks-plugin/docs" "$dir/hooks-plugin/hooks"
    {
        echo "# Feature Flags Catalog"
        [ -n "$doc_flag" ] && echo "| \`$doc_flag\` | does a thing | src |"
    } > "$dir/hooks-plugin/docs/feature-flags.md"
    printf '#!/usr/bin/env bash\n[ "${%s:-}" = "1" ] && exit 0\n' "$hook_flag" \
        > "$dir/hooks-plugin/hooks/sample.sh"
    echo "$dir"
}

echo "=== check-feature-flags-catalog tests ==="

# 1. Real repo is clean and strict-passes.
out=$(bash "$SCRIPT" --project-dir "$REPO_ROOT" --strict 2>&1); rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -qx "STATUS=OK"; then
    pass "real repo passes --strict (STATUS=OK, exit 0)"
else
    fail "real repo should pass --strict (got exit $rc): $out"
fi

# 2. A documented flag → OK.
d=$(make_project "CLAUDE_HOOKS_ENABLE_SAMPLE" "CLAUDE_HOOKS_ENABLE_SAMPLE")
out=$(bash "$SCRIPT" --project-dir "$d" --strict 2>&1); rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -qx "MISSING_COUNT=0"; then
    pass "documented flag → STATUS=OK, exit 0"
else
    fail "documented flag should pass (got exit $rc): $out"
fi
rm -rf "$d"

# 3. An UNDOCUMENTED flag → strict fails (exit 1) and names the flag.
d=$(make_project "CLAUDE_HOOKS_ENABLE_SAMPLE" "")
out=$(bash "$SCRIPT" --project-dir "$d" --strict 2>&1); rc=$?
if [ "$rc" -eq 1 ] \
   && echo "$out" | grep -qx "MISSING_COUNT=1" \
   && echo "$out" | grep -q "FLAG=CLAUDE_HOOKS_ENABLE_SAMPLE"; then
    pass "undocumented flag → strict exit 1, names the flag"
else
    fail "undocumented flag should fail --strict (got exit $rc): $out"
fi
rm -rf "$d"

# 4. Without --strict, a gap reports ERROR but still exits 0 (audit-friendly).
d=$(make_project "CLAUDE_TASKWARRIOR_NO_SAMPLE" "")
out=$(bash "$SCRIPT" --project-dir "$d" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -qx "STATUS=ERROR"; then
    pass "gap without --strict → STATUS=ERROR but exit 0"
else
    fail "non-strict gap should exit 0 with STATUS=ERROR (got exit $rc): $out"
fi
rm -rf "$d"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
