#!/usr/bin/env bash
# shellcheck disable=SC2015   # file-level: `cond && ok … || notok …` is the
# deliberate assertion idiom (ok/notok both exit 0) — see test-frontmatter-rows-bwk-floor.sh.
# Meta-test for the zsh floor in test-bare-declaration-guard.sh (#3629).
#
# The guard suite runs its fixture table in bash and, when zsh is installed, in
# zsh. `local $names` lists parameters in zsh only, so the zsh column is the
# only evidence for four of its rows. The `Test: Skill scripts` workflow
# installs zsh for it, and scripts/required-to-run-tests.txt lists the suite,
# so a run without zsh must reach the runner as a SKIP (an ERROR for a
# required suite), never as a PASS over the bash half alone.
#
# Cases:
#   1. BARE_DECL_TEST_NO_ZSH=1: the suite exits 0, indents its own output and
#      ends on one unindented SKIP line.
#   2. The real runner, scoped to the suite with the real manifest, reports
#      that run as `required_test_skipped` and exits 1.
#   3. zsh removed from PATH (not the variable): same SKIP, so the suite's own
#      `command -v zsh` lookup is exercised.
#   4. Control, when zsh is installed: the suite runs the zsh rows, prints no
#      SKIP line, and the runner reports it as a PASS. This is what CI checks.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUITE="${SCRIPT_DIR}/test-bare-declaration-guard.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RUNNER="${REPO_ROOT}/scripts/run-skill-script-tests.sh"
REL="hooks-plugin/hooks/test-bare-declaration-guard.sh"

pass=0
fail=0
ok() { pass=$((pass + 1)); printf 'ok   - %s\n' "$1"; }
notok() { fail=$((fail + 1)); printf 'FAIL - %s\n' "$1"; }

work=$(mktemp -d)
if [ -z "$work" ] || [ ! -d "$work" ]; then
    echo "FATAL: mktemp failed" >&2
    exit 1
fi
trap 'rm -rf "$work"' EXIT

# unindented <text> — the lines a runner reads as the suite's own verdict.
unindented() { grep -E '^[^[:space:]]' <<<"$1" || true; }

# 1. The variable hides zsh: indented output, one SKIP line, exit 0.
out=$(env BARE_DECL_TEST_NO_ZSH=1 bash "$SUITE" 2>&1); rc=$?
top=$(unindented "$out")
[ "$rc" -eq 0 ] && [ "$(wc -l <<<"$top")" -eq 1 ] && grep -qE '^SKIP: .*zsh' <<<"$top" \
    && ok "BARE_DECL_TEST_NO_ZSH=1: exit 0 and one unindented SKIP line" \
    || notok "BARE_DECL_TEST_NO_ZSH=1: rc=$rc; unindented lines: $(head -3 <<<"$top")"
grep -qE '^  Results: [0-9]+ passed, 0 failed' <<<"$out" \
    && ok "BARE_DECL_TEST_NO_ZSH=1: the bash half still runs and passes" \
    || notok "BARE_DECL_TEST_NO_ZSH=1: no indented passing Results line"

# 2. The runner, with the real manifest, turns that skip into an ERROR.
out=$(env BARE_DECL_TEST_NO_ZSH=1 bash "$RUNNER" --root "$REPO_ROOT" --only "$REL" 2>&1); rc=$?
[ "$rc" -eq 1 ] && grep -qF "TYPE=required_test_skipped TEST=${REL}" <<<"$out" \
    && ok "runner: a zsh-less run of the required suite is required_test_skipped, exit 1" \
    || notok "runner without zsh: rc=$rc; $(grep -E '^(STATUS|SKIP|PASS|FAIL)=|TYPE=' <<<"$out" | head -4)"

# 3. zsh removed from PATH. Every PATH directory holding zsh is replaced by a
#    shadow directory of links to everything else in it.
path_without() {     # <cmd> <PATH>
    local cmd="$1" outp="" dir shadow f
    local -a dirs
    IFS=: read -r -a dirs <<<"$2"
    for dir in "${dirs[@]}"; do
        if [ -n "$dir" ] && [ -x "$dir/$cmd" ]; then
            shadow=$(mktemp -d "$work/shadow.XXXXXX")
            for f in "$dir"/*; do
                [ "${f##*/}" = "$cmd" ] || ln -s "$f" "$shadow/${f##*/}"
            done
            dir="$shadow"
        fi
        outp="${outp:+$outp:}$dir"
    done
    printf '%s' "$outp"
}
no_zsh_path=$(path_without zsh "$PATH")
if [ -z "$(PATH="$no_zsh_path" command -v zsh)" ]; then
    out=$(env -u BARE_DECL_TEST_NO_ZSH PATH="$no_zsh_path" bash "$SUITE" 2>&1); rc=$?
    top=$(unindented "$out")
    [ "$rc" -eq 0 ] && [ "$(wc -l <<<"$top")" -eq 1 ] && grep -qE '^SKIP: .*zsh' <<<"$top" \
        && ok "zsh off PATH: exit 0 and one unindented SKIP line" \
        || notok "zsh off PATH: rc=$rc; unindented lines: $(head -3 <<<"$top")"
else
    notok "PATH simulation did not take: zsh still at $(PATH="$no_zsh_path" command -v zsh)"
fi

# 4. Control: with zsh installed the floor is satisfiable and the zsh rows run.
if command -v zsh >/dev/null 2>&1; then
    out=$(env -u BARE_DECL_TEST_NO_ZSH bash "$SUITE" 2>&1); rc=$?
    [ "$rc" -eq 0 ] && ! grep -qE '^SKIP' <<<"$out" && grep -qE '^  PASS: zsh ' <<<"$out" \
        && ! grep -qF 'zsh column not run' <<<"$out" \
        && ok "zsh installed: the zsh rows run and no SKIP line is printed" \
        || notok "zsh installed: rc=$rc; $(unindented "$out" | tail -3)"
    out=$(env -u BARE_DECL_TEST_NO_ZSH bash "$RUNNER" --root "$REPO_ROOT" --only "$REL" 2>&1); rc=$?
    [ "$rc" -eq 0 ] && grep -qF "PASS=./${REL}" <<<"$out" \
        && ok "runner: with zsh installed the required suite is a PASS" \
        || notok "runner with zsh: rc=$rc; $(grep -E '^(STATUS|SKIP|PASS|FAIL)=|TYPE=' <<<"$out" | head -4)"
else
    printf 'SKIP - zsh not installed; the satisfiable-floor control needs it (CI installs it)\n'
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
exit 0
