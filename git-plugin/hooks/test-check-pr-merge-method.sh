#!/usr/bin/env bash
# shellcheck disable=SC2016  # fixtures are the LITERAL, unexpanded command text a hook receives
# shellcheck disable=SC2015  # `cond && pass || fail` is this repo's assertion idiom
# Regression tests for check-pr-merge-method.sh
#
# Run: bash git-plugin/hooks/test-check-pr-merge-method.sh
# Exit 0 = all tests pass, Exit 1 = failures
#
# The decision itself is pinned by git-plugin/scripts/tests/test-pr-merge-method.sh.
# Here PR_MERGE_METHOD_CMD points at a stub that prints a fixed KEY=VALUE
# result, so these cases test only what the hook adds: finding each
# `gh pr merge`, reading its method flag, -R and selector, and blocking on a
# mismatch. The parsed-trigger cases need ast-grep; the raw-text fallback cases
# force CLAUDE_HOOKS_PARSED_TRIGGER_NO_ASTGREP=1.
set -euo pipefail

# Listed in scripts/required-to-run-tests.txt: without a working ast-grep only
# the fallback half runs, so the suite re-runs itself indented and ends on ONE
# unindented SKIP line, which the runner reports as a skip (an ERROR for a
# required suite) rather than a pass (same wrapper as test-check-pr-metadata-on-push.sh).
if [ -z "${PARSED_SUITE_INNER:-}" ] && {
    [ "${CLAUDE_HOOKS_PARSED_TRIGGER_NO_ASTGREP:-}" = 1 ] ||
        ! { command -v ast-grep >/dev/null 2>&1 ||
            { command -v sg >/dev/null 2>&1 && sg --version 2>/dev/null | grep -qi '^ast-grep'; }; }
}; then
    suite_rc=0
    suite_out=$(PARSED_SUITE_INNER=1 bash "$0" "$@" 2>&1) || suite_rc=$?
    printf '%s\n' "$suite_out" | sed 's/^/  /'
    [ "$suite_rc" -eq 0 ] || exit "$suite_rc"
    echo "SKIP: no working ast-grep (or CLAUDE_HOOKS_PARSED_TRIGGER_NO_ASTGREP=1); the parsed-trigger cases require it"
    exit 0
fi

unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
  GIT_COMMON_DIR GIT_NAMESPACE GIT_PREFIX

HOOK="$(cd "$(dirname "$0")" && pwd)/check-pr-merge-method.sh"
PASS=0
FAIL=0
SKIP=0

TMPDIR=$(mktemp -d) || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "$TMPDIR"' EXIT

STUB="$TMPDIR/decide"
cat >"$STUB" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_LOG"
if [ "${STUB_STATUS:-OK}" = ERROR ]; then
    printf '=== PR MERGE METHOD ===\nMETHOD=unknown\nSTATUS=ERROR\nREASON=fetch_failed\n'
    exit 1
fi
printf '=== PR MERGE METHOD ===\nPR=o/r#5\nMETHOD=%s\nRULE=9\nREASON=%s\nDETAIL=stub detail\nOVERRIDE=%s\nBODY_LINT=%s\nSTATUS=OK\n=== END PR MERGE METHOD ===\n' \
    "$STUB_METHOD" "${STUB_REASON:-independent_commits}" "${STUB_OVERRIDE:-none}" "${STUB_LINT:-0}"
EOF
chmod +x "$STUB"
# A non-executable stub would make the hook fall through to exit 0 on every
# case, and every "passes" assertion below would be vacuous.
[ -x "$STUB" ] || { echo "stub is not executable" >&2; exit 1; }
export PR_MERGE_METHOD_CMD="$STUB" STUB_LOG="$TMPDIR/log"

have_astgrep() {
    [ "${CLAUDE_HOOKS_PARSED_TRIGGER_NO_ASTGREP:-}" != 1 ] || return 1
    command -v ast-grep >/dev/null 2>&1 ||
        { command -v sg >/dev/null 2>&1 && sg --version 2>/dev/null | grep -qi '^ast-grep'; }
}

payload() { jq -nc --arg c "$1" --arg d "$TMPDIR" '{tool_input: {command: $c}, cwd: $d}'; }

# run <command> -> sets RC and ERR
run() {
    RC=0
    ERR=$(payload "$1" | bash "$HOOK" 2>&1 >/dev/null) || RC=$?
}

check() {
    local desc=$1 want=$2 cmd=$3
    run "$cmd"
    if [ "$RC" -eq "$want" ]; then
        printf '  PASS: %s\n' "$desc"
        PASS=$((PASS + 1))
    else
        printf '  FAIL: %s (expected exit %d, got %d)\n%s\n' "$desc" "$want" "$RC" "$ERR"
        FAIL=$((FAIL + 1))
    fi
}

contains() {
    local desc=$1 needle=$2
    if grep -qF -- "$needle" <<<"$ERR"; then
        printf '  PASS: %s\n' "$desc"
        PASS=$((PASS + 1))
    else
        printf '  FAIL: %s (no %q in)\n%s\n' "$desc" "$needle" "$ERR"
        FAIL=$((FAIL + 1))
    fi
}

suite() {
    echo "--- mismatch blocks ---"
    STUB_METHOD=rebase check "--squash when METHOD=rebase blocks" 2 'gh pr merge 5 --squash --delete-branch'
    contains "block headline" 'MERGE METHOD: o/r#5 should be merged with --rebase, not --squash.'
    contains "block names the corrected command" 'gh pr merge 5 --rebase --delete-branch'
    contains "block names the override label" '--add-label merge:squash'
    STUB_METHOD=squash check "-r when METHOD=squash blocks" 2 'gh pr merge 5 -r'
    STUB_METHOD=rebase check "--merge blocks" 2 'gh pr merge 5 --merge'
    contains "--merge has no override label" 'there is no label for them'
    STUB_METHOD=rebase check "second of two chained merges is checked" 2 'gh pr merge 4 --rebase && gh pr merge 5 --squash'
    STUB_METHOD=squash STUB_LINT=2 check "squash body lint is surfaced" 2 'gh pr merge 5 --rebase'
    contains "lint finding count shown" '2 lint finding(s)'

    echo "--- match or override passes ---"
    STUB_METHOD=rebase check "--rebase when METHOD=rebase passes" 0 'gh pr merge 5 --rebase --delete-branch'
    STUB_METHOD=squash STUB_OVERRIDE=merge:squash STUB_REASON=override_label \
        check "override label matching the flag passes" 0 'gh pr merge 5 --squash'
    STUB_METHOD=squash STUB_OVERRIDE=merge:squash STUB_REASON=override_label \
        check "flag contradicting the override label blocks" 2 'gh pr merge 5 --rebase'
    contains "override is named as the reason" 'the merge:squash label'

    echo "--- not applicable passes ---"
    STUB_METHOD=rebase check "no method flag passes" 0 'gh pr merge 5 --auto'
    STUB_METHOD=rebase check "--disable-auto passes" 0 'gh pr merge 5 --disable-auto --squash'
    STUB_METHOD=rebase check "non-merge gh command passes" 0 'gh pr view 5 --json mergeable'
    STUB_METHOD=rebase STUB_STATUS=ERROR check "decider ERROR fails open" 0 'gh pr merge 5 --squash'

    echo "--- arguments reach the decider ---"
    : >"$STUB_LOG"
    STUB_METHOD=rebase check "-R before merge" 0 'gh pr -R o/r merge 5 --rebase'
    grep -qx -- '--repo o/r --pr 5' "$STUB_LOG" && { printf '  PASS: decider got --repo o/r --pr 5\n'; PASS=$((PASS + 1)); } ||
        { printf '  FAIL: decider args: %s\n' "$(cat "$STUB_LOG")"; FAIL=$((FAIL + 1)); }
    : >"$STUB_LOG"
    STUB_METHOD=rebase check "--repo= and URL selector" 0 'gh pr merge https://github.com/o/r/pull/5 --repo=o/r --rebase'
    grep -qx -- '--repo o/r --pr https://github.com/o/r/pull/5' "$STUB_LOG" && { printf '  PASS: decider got URL selector\n'; PASS=$((PASS + 1)); } ||
        { printf '  FAIL: decider args: %s\n' "$(cat "$STUB_LOG")"; FAIL=$((FAIL + 1)); }
    : >"$STUB_LOG"
    STUB_METHOD=rebase check "--subject value is not the selector" 0 'gh pr merge --subject x --rebase'
    grep -qx -- '' "$STUB_LOG" && { printf '  PASS: no selector -> current branch\n'; PASS=$((PASS + 1)); } ||
        { printf '  FAIL: decider args: %s\n' "$(cat "$STUB_LOG")"; FAIL=$((FAIL + 1)); }
}

echo "=== parsed trigger (ast-grep) ==="
if have_astgrep; then
    suite
    STUB_METHOD=rebase check "a quoted mention is not a merge" 0 'gh issue comment 5 --body "then run gh pr merge 5 --squash"'
    STUB_METHOD=rebase check "bash -c wrapper is a merge" 2 "bash -c 'gh pr merge 5 --squash'"
else
    echo "SKIP - no working ast-grep; parsed-trigger cases not run"
    SKIP=$((SKIP + 1))
fi

echo "=== raw-text fallback (no ast-grep) ==="
export CLAUDE_HOOKS_PARSED_TRIGGER_NO_ASTGREP=1
suite
unset CLAUDE_HOOKS_PARSED_TRIGGER_NO_ASTGREP

echo "PASSED=$PASS FAILED=$FAIL SKIPPED=$SKIP"
[ "$FAIL" -eq 0 ]
