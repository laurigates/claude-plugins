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
#
# GUARD INTEGRITY: `STATUS=OK` alone is a VACUOUS assertion — it is exactly what
# a checker that opened no file reports, and that is not hypothetical. This guard
# used `rg` with its stderr swallowed; ripgrep is absent from GitHub's
# ubuntu-latest image, so in CI both counts read 0, MISSING_COUNT was 0, STATUS
# was OK, and this assertion passed while asserting nothing (#2333). The
# FILES_SCANNED / SCANNED_EMPTY anchors below are what make the OK mean
# something, so they are checked here and beside every fixture case.
out=$(bash "$SCRIPT" --project-dir "$REPO_ROOT" --strict 2>&1); rc=$?
scanned=$(printf '%s\n' "$out" | grep -m1 '^FILES_SCANNED=' | cut -d= -f2)
if [ "$rc" -eq 0 ] && echo "$out" | grep -qx "STATUS=OK"; then
    pass "real repo passes --strict (STATUS=OK, exit 0)"
else
    fail "real repo should pass --strict (got exit $rc): $out"
fi
if [ -n "${scanned:-}" ] && [ "$scanned" -gt 0 ] 2>/dev/null; then
    pass "real repo scan is non-vacuous (FILES_SCANNED=$scanned > 0)"
else
    fail "real repo reported no scanned files — a clean STATUS would be meaningless: $out"
fi
if echo "$out" | grep -qx "SCANNED_EMPTY=false"; then
    pass "real repo reports SCANNED_EMPTY=false"
else
    fail "real repo should report SCANNED_EMPTY=false: $out"
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
# The DENY above must be attributable to the flag, not to a walk that happened
# to read the one hook and nothing else.
if echo "$out" | grep -qx "FILES_SCANNED=1"; then
    pass "the fixture's single hook is exactly what was scanned (FILES_SCANNED=1)"
else
    fail "fixture should report FILES_SCANNED=1: $out"
fi
rm -rf "$d"

# 3b. NOTHING SCANNED → ERROR, never a clean OK.
#
# This is the case the pre-#2333 guard could not distinguish from "clean": with
# no ripgrep on the runner it produced FILES_SCANNED's moral equivalent (zero
# flags from zero files) and reported STATUS=OK / exit 0, so tests 3 and 4 could
# not fail by construction. A catalog resolved but no scannable source means the
# walk misfired, and the only honest verdict is ERROR.
d=$(mktemp -d)
mkdir -p "$d/hooks-plugin/docs"
printf '# Feature Flags Catalog\n' > "$d/hooks-plugin/docs/feature-flags.md"
out=$(bash "$SCRIPT" --project-dir "$d" --strict 2>&1); rc=$?
if [ "$rc" -eq 1 ] \
   && echo "$out" | grep -qx "STATUS=ERROR" \
   && echo "$out" | grep -qx "SCANNED_EMPTY=true" \
   && echo "$out" | grep -q "TYPE=nothing_scanned"; then
    pass "zero scannable sources → ERROR + nothing_scanned, not a clean OK"
else
    fail "empty source tree should be an ERROR, not OK (got exit $rc): $out"
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
