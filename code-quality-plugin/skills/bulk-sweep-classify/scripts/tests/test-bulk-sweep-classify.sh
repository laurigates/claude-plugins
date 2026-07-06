#!/usr/bin/env bash
# test-bulk-sweep-classify.sh — semantic regression test for the
# bulk-sweep-classify skill's code-vs-prose routing (issue #2013).
#
# The skill routes code-targeted bulk sweeps (API renames, call-site migrations,
# import-path changes in source files) through structural matching
# (`ast-grep`, delegating to `code-quality-plugin:ast-grep-search`) so that the
# category-2 false-positive bucket (strings/comments/URLs that merely match the
# text) shrinks to near-zero — while the four-category discipline stays the
# unchanged core case for prose/docs/mixed sweeps.
#
# This test pins the semantic invariants a bulk edit could silently break:
#   1. The code-vs-prose routing decision appears BEFORE Step 1 (Step 0).
#   2. The code route delegates transform mechanics to ast-grep-search by name.
#   3. The four-category discipline is still present (categories 1–4 retained).
#   4. The Step 5 verification note covers the code route's preserved set
#      (strings/comments/URLs the structural matcher legitimately leaves).
#
# Pure text-invariant checks — no external tooling required.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_FILE="${SCRIPT_DIR}/../../SKILL.md"

pass=0
fail=0

check() { # check <description> <condition-exit-status>
    if [ "$1" -eq 0 ]; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        printf 'FAIL: %s\n' "$2" >&2
    fi
}

if [ ! -f "$SKILL_FILE" ]; then
    echo "FAIL: SKILL.md not found at $SKILL_FILE" >&2
    exit 1
fi

# Byte offsets of the anchoring headings, so we can assert ordering.
routing_line=$(grep -n '^### Step 0: Route by sweep target' "$SKILL_FILE" | head -1 | cut -d: -f1)
step1_line=$(grep -n '^### Step 1:' "$SKILL_FILE" | head -1 | cut -d: -f1)

# 1. Routing decision exists AND precedes Step 1.
if [ -n "$routing_line" ] && [ -n "$step1_line" ] && [ "$routing_line" -lt "$step1_line" ]; then
    check 0 ""
else
    check 1 "code-vs-prose routing (Step 0) must appear before Step 1 (routing=${routing_line:-none} step1=${step1_line:-none})"
fi

# 2. The code route delegates to ast-grep-search by name-based cross-reference.
grep -q 'code-quality-plugin:ast-grep-search' "$SKILL_FILE"
check $? "code route must delegate transform mechanics to code-quality-plugin:ast-grep-search"

# The routing text must actually name the structural ast-grep transform.
grep -q "ast-grep -p '<old>' -r '<new>' --lang" "$SKILL_FILE"
check $? "code route must show the ast-grep -p/-r structural transform form"

# 3. The four-category discipline is retained (all four categories present).
grep -q '^## The Four Categories' "$SKILL_FILE"
check $? "the four-category section heading must remain"

for cat in \
    '1. Genuine stale target' \
    '2. False positive' \
    '3. Out-of-scope design' \
    '4. Immutable / historical record'; do
    grep -qF "$cat" "$SKILL_FILE"
    check $? "category retained: ${cat}"
done

# The prose/docs route must explicitly keep the four-category discipline.
grep -qi 'four-category discipline' "$SKILL_FILE"
check $? "prose/docs route must explicitly retain the four-category discipline"

# 4. Step 5 verification note covers the code route's preserved set.
grep -qi 'code route' "$SKILL_FILE"
check $? "Step 5 verification must reference the code route's preserved set"

grep -qi 'strings, comments, or URLs' "$SKILL_FILE"
check $? "Step 5 must describe the structural-match preserved set (strings/comments/URLs)"

echo "bulk-sweep-classify routing test: ${pass} passed, ${fail} failed"
[ "$fail" -eq 0 ]
