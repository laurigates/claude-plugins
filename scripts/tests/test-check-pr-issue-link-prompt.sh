#!/usr/bin/env bash
# Self-test for scripts/check-pr-issue-link-prompt.sh (issues #3404, #3413).
#
# Runs the guard over the real git-plugin/hooks.json, over the pre-#3404 prompt
# (fails on the three opt-out and three non-closing-ref rules), over the
# pre-#3413 prompt (fails on exactly the three non-closing-ref rules), and over single
# mutations of the fixed prompt, so a guard that stops seeing a rule fails here.
#
# Run: bash scripts/tests/test-check-pr-issue-link-prompt.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GUARD="$ROOT_DIR/scripts/check-pr-issue-link-prompt.sh"
CONTRACT="$ROOT_DIR/scripts/check-structured-output-contract.sh"
REAL="$ROOT_DIR/git-plugin/hooks.json"
MATCHER="mcp__github__create_pull_request"

WORK=$(mktemp -d) || { echo "mktemp -d failed" >&2; exit 1; }
if [ -z "$WORK" ] || [ ! -d "$WORK" ]; then echo "mktemp -d returned no directory" >&2; exit 1; fi
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); echo "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "FAIL: $1"; }

assert_contains() {
    if grep -qF -- "$2" <<<"$3"; then pass "$1"; else fail "$1 (missing: $2)"; fi
}
assert_lacks() {
    if grep -qF -- "$2" <<<"$3"; then fail "$1 (unexpected: $2)"; else pass "$1"; fi
}
assert_exit() {
    local label="$1" want="$2" rc=0
    shift 2
    "$@" >/dev/null 2>&1 || rc=$?
    if [ "$rc" -eq "$want" ]; then pass "$label"; else fail "$label (exit $rc, want $want)"; fi
}
assert_valid_contract() {
    local rc=0
    bash "$CONTRACT" --validate <<<"$2" >/dev/null 2>&1 || rc=$?
    if [ "$rc" -eq 0 ]; then pass "$1"; else fail "$1 (--validate exit $rc)"; fi
}

# write_fixture NAME PROMPT -- a hooks.json carrying PROMPT for the PR matcher.
write_fixture() {
    jq -n --arg m "$MATCHER" --arg p "$2" \
        '{hooks: {PreToolUse: [{matcher: $m, hooks: [{type: "prompt", prompt: $p, timeout: 15}]}]}}' \
        >"$WORK/$1.json"
    echo "$WORK/$1.json"
}

real_prompt=$(jq -r --arg m "$MATCHER" \
    '[.hooks.PreToolUse[] | select(.matcher == $m) | .hooks[] | select(.type == "prompt") | .prompt][0]' "$REAL")

# A: the real hooks.json passes.
out=$(bash "$GUARD" --hooks-json "$REAL")
assert_contains "A1: real hooks.json STATUS=OK" "STATUS=OK" "$out"
assert_contains "A2: real hooks.json ISSUE_COUNT=0" "ISSUE_COUNT=0" "$out"
assert_exit "A3: real hooks.json exits 0 under --strict" 0 bash "$GUARD" --hooks-json "$REAL" --strict
assert_valid_contract "A4: OK output satisfies the structured-output contract" "$out"

# B: the pre-fix prompt (origin/main before #3404) fails on the opt-out rules only.
prefix_prompt='Check the '"'"'body'"'"' field in tool_input for GitHub issue closing keywords: closes, fixes, resolves (case-insensitive, followed by #N or owner/repo#N). If the body already contains closing keywords, return {"ok": true}. If the PR title or body is clearly for infrastructure, documentation, or dependency updates with no bug or feature issue to close, return {"ok": true}. If the title or body describes a bug fix or feature implementation but the body lacks closing keywords, return {"ok": false, "reason": "PR body is missing issue closing keywords. Add '"'"'Closes #N'"'"', '"'"'Fixes #N'"'"', or '"'"'Resolves #N'"'"' to automatically close the related issue when this PR merges to the default branch. Use '"'"'Fixes'"'"' for bugs, '"'"'Closes'"'"' for features/enhancements, '"'"'Resolves'"'"' for general issues. For multiple issues repeat the keyword: Fixes #1, Fixes #2."}'
f=$(write_fixture prefix "$prefix_prompt")
out=$(bash "$GUARD" --hooks-json "$f")
assert_contains "B1: pre-fix STATUS=ERROR" "STATUS=ERROR" "$out"
assert_contains "B2: pre-fix ISSUE_COUNT=6 (three opt-out + three non-closing-ref rules)" "ISSUE_COUNT=6" "$out"
assert_contains "B3: pre-fix names optout_phrase" "TYPE=optout_phrase" "$out"
assert_contains "B4: pre-fix names optout_passes" "TYPE=optout_passes" "$out"
assert_contains "B5: pre-fix names reason_names_optout" "TYPE=reason_names_optout" "$out"
assert_lacks "B6: pre-fix keeps the existing contract" "TYPE=contract_" "$out"
assert_exit "B7: pre-fix exits 1 under --strict" 1 bash "$GUARD" --hooks-json "$f" --strict
assert_valid_contract "B8: ERROR output satisfies the structured-output contract" "$out"

# F: the pre-#3413 prompt (origin/main after #3404) fails on exactly the
# three non-closing-reference rules: it has the opt-out but blocks `Refs #N`.
IFS= read -r -d '' pre3413_prompt <<'EOF' || true
Check the 'body' field in tool_input for GitHub issue closing keywords: closes, fixes, resolves (case-insensitive, followed by #N or owner/repo#N). If the body already contains closing keywords, return {"ok": true}. If the body contains a line starting 'No linked issue:' (case-insensitive) followed by a reason, the author is stating that no issue exists for this PR, so return {"ok": true}; do not judge whether the reason is good enough. If the PR title or body is clearly for infrastructure, documentation, or dependency updates with no bug or feature issue to close, return {"ok": true}. If the title or body describes a bug fix or feature implementation but the body has neither closing keywords nor a 'No linked issue:' line, return {"ok": false, "reason": "PR body is missing issue closing keywords. Add 'Closes #N', 'Fixes #N', or 'Resolves #N' to automatically close the related issue when this PR merges to the default branch. Use 'Fixes' for bugs, 'Closes' for features/enhancements, 'Resolves' for general issues. For multiple issues repeat the keyword: Fixes #1, Fixes #2. If no issue exists for this work, add a line 'No linked issue: <reason>' instead; do not create an issue only to close it."}
EOF
pre3413_prompt="${pre3413_prompt%$'\n'}"
f=$(write_fixture pre3413 "$pre3413_prompt")
out=$(bash "$GUARD" --hooks-json "$f")
assert_contains "F1: pre-#3413 STATUS=ERROR" "STATUS=ERROR" "$out"
assert_contains "F2: pre-#3413 ISSUE_COUNT=3" "ISSUE_COUNT=3" "$out"
assert_contains "F3: pre-#3413 names nonclosing_ref_phrase" "TYPE=nonclosing_ref_phrase" "$out"
assert_contains "F4: pre-#3413 names nonclosing_ref_passes" "TYPE=nonclosing_ref_passes" "$out"
assert_contains "F5: pre-#3413 names reason_names_nonclosing_ref" "TYPE=reason_names_nonclosing_ref" "$out"
assert_lacks "F6: pre-#3413 keeps the opt-out rules" "TYPE=optout" "$out"
assert_exit "F7: pre-#3413 exits 1 under --strict" 1 bash "$GUARD" --hooks-json "$f" --strict
assert_valid_contract "F8: pre-#3413 output satisfies the structured-output contract" "$out"

# G: dropping only the non-closing-ref hint from the block reason fails reason_names_nonclosing_ref alone.
ref_hint=" If the PR is part of a larger issue it should not close, reference it with 'Refs #N' or 'Part of #N' instead of a closing keyword."
grep -qF -- "$ref_hint" <<<"$real_prompt" || fail "G0: real prompt carries the exact ref hint G removes"
mutated="${real_prompt/"$ref_hint"/}"
f=$(write_fixture no-ref-hint "$mutated")
out=$(bash "$GUARD" --hooks-json "$f")
assert_contains "G1: ref-hint-less reason names reason_names_nonclosing_ref" "TYPE=reason_names_nonclosing_ref" "$out"
assert_contains "G2: ref-hint-less reason is the only finding" "ISSUE_COUNT=1" "$out"

# C: dropping only the opt-out hint from the block reason fails reason_names_optout alone.
mutated="${real_prompt% If no issue exists*}\"}"
f=$(write_fixture no-hint "$mutated")
out=$(bash "$GUARD" --hooks-json "$f")
assert_contains "C1: hint-less reason names reason_names_optout" "TYPE=reason_names_optout" "$out"
assert_contains "C2: hint-less reason is the only finding" "ISSUE_COUNT=1" "$out"

# D: dropping the closing-keyword check is caught even with the opt-out present.
f=$(write_fixture no-keywords "${real_prompt/closes, fixes, resolves/a closing keyword}")
out=$(bash "$GUARD" --hooks-json "$f")
assert_contains "D1: missing keyword list names closing_keywords" "TYPE=closing_keywords" "$out"

# E: no prompt hook for the matcher is an error, not a silent pass.
jq -n '{hooks: {PreToolUse: []}}' >"$WORK/empty.json"
out=$(bash "$GUARD" --hooks-json "$WORK/empty.json")
assert_contains "E1: absent prompt names prompt_count" "TYPE=prompt_count" "$out"
assert_exit "E2: unknown argument exits 2" 2 bash "$GUARD" --bogus

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
