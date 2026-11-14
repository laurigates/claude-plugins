#!/usr/bin/env bash
# shellcheck disable=SC2015   # file-level: `cond && ok … || notok …` is the
# deliberate assertion idiom (ok/notok both exit 0) — see test-check-schema.sh.
# Meta-test for the BWK-awk floor in test-frontmatter-rows.sh (#3549).
#
# The BWK row compares the shared frontmatter parser under original-awk, the
# awk macOS ships. A host without original-awk must not drop that row
# silently: locally the suite prints a SKIP line, and under CI=true or
# GITHUB_ACTIONS it fails. FRONTMATTER_ROWS_AWK_VARIANTS removes original-awk
# from the candidate list, which is what an unpatched runner looks like.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUITE="${SCRIPT_DIR}/test-frontmatter-rows.sh"

pass=0
fail=0
ok() { pass=$((pass + 1)); printf 'ok   - %s\n' "$1"; }
notok() { fail=$((fail + 1)); printf 'FAIL - %s\n' "$1"; }

no_bwk='mawk|gawk|/usr/bin/awk'

# run_suite <CI value> <GITHUB_ACTIONS value> [variants]; sets out and rc.
run_suite() {
    local ci="$1" gha="$2"
    if [ $# -gt 2 ]; then
        out=$(env -u CI -u GITHUB_ACTIONS ${ci:+CI="$ci"} ${gha:+GITHUB_ACTIONS="$gha"} \
            FRONTMATTER_ROWS_AWK_VARIANTS="$3" bash "$SUITE" 2>&1)
    else
        out=$(env -u CI -u GITHUB_ACTIONS -u FRONTMATTER_ROWS_AWK_VARIANTS \
            ${ci:+CI="$ci"} ${gha:+GITHUB_ACTIONS="$gha"} bash "$SUITE" 2>&1)
    fi
    rc=$?
}

# 1. Local, original-awk absent: SKIP line, suite stays green.
run_suite "" "" "$no_bwk"
[ "$rc" -eq 0 ] && grep -q '^SKIP - original-awk' <<<"$out" \
    && ok "local run without original-awk prints SKIP and passes" \
    || notok "local run without original-awk: rc=$rc; $(grep -E '^(SKIP|FAIL)' <<<"$out" | head -4)"

# 2. CI=true, original-awk absent: the suite fails on the BWK floor.
run_suite "true" "" "$no_bwk"
[ "$rc" -eq 1 ] && grep -q '^FAIL - BWK awk variant (original-awk) did not run in CI' <<<"$out" \
    && ok "CI=true without original-awk fails" \
    || notok "CI=true without original-awk: rc=$rc; $(grep -E '^(SKIP|FAIL)' <<<"$out" | head -4)"

# 3. GITHUB_ACTIONS set, CI unset, original-awk absent: also fails.
run_suite "" "true" "$no_bwk"
[ "$rc" -eq 1 ] && grep -q '^FAIL - BWK awk variant (original-awk) did not run in CI' <<<"$out" \
    && ok "GITHUB_ACTIONS without original-awk fails" \
    || notok "GITHUB_ACTIONS without original-awk: rc=$rc; $(grep -E '^(SKIP|FAIL)' <<<"$out" | head -4)"

# 4. Control: CI=true with the default list passes when original-awk is
#    installed (CI installs it), so the floor is satisfiable.
if command -v original-awk >/dev/null 2>&1; then
    run_suite "true" ""
    [ "$rc" -eq 0 ] && grep -q '^ok   - BWK awk variant ran in CI' <<<"$out" \
        && ok "CI=true with original-awk installed passes the floor" \
        || notok "CI=true with original-awk installed: rc=$rc; $(grep -E '^(SKIP|FAIL)' <<<"$out" | head -4)"
else
    printf 'SKIP - original-awk not installed; the satisfiable-floor control needs it\n'
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
exit 0
