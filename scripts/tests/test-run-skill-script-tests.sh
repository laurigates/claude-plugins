#!/usr/bin/env bash
# Regression test for scripts/run-skill-script-tests.sh (issues #2221, #2219).
#
# #2221 — the runner printed `PASS=<file>` for a test that SKIPped, so a
# gate whose dependency was absent on the runner was indistinguishable, in the
# CI log, from a gate that ran and passed. The foundryvtt template-parity test
# sat in that state for weeks.
#
# #2219 (CASE 9) — discovery pruned `.claude/worktrees/` with a bare glob against
# an ABSOLUTE base, so a scan root that was ITSELF an agent worktree matched its
# own prune and the whole walk was skipped: TOTAL=0, reading as "no tests here".
#
# This test is SEMANTIC, not syntactic: it EXECUTES the real runner against
# planted fixture trees and asserts on its structured output. A grep for the
# string "SKIP=" in the runner would pass against a half-fix that never
# classifies anything as a skip.
#
# Guard integrity: every "was not counted as a pass" assertion is paired with a
# positive control (PASSED > 0, a genuinely-passing test still reported PASS=),
# so the suite cannot degrade into a no-op against a runner that classifies
# everything as a skip — or scans nothing at all.

set -uo pipefail

# Inherited git context must not reach the fixture trees (#1745). Nothing here
# runs git, but the sandbox discipline is cheap and non-negotiable.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR GIT_NAMESPACE GIT_PREFIX

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER="${SCRIPT_DIR}/../run-skill-script-tests.sh"

pass=0
fail=0

check() { # check <description> <expected> <actual>
    if [ "$2" = "$3" ]; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
    fi
}

check_contains() { # check_contains <description> <needle> <haystack>
    if printf '%s' "$3" | grep -qF -- "$2"; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        printf 'FAIL: %s\n  expected to contain: %s\n' "$1" "$2" >&2
    fi
}

check_absent() { # check_absent <description> <needle> <haystack>
    if printf '%s' "$3" | grep -qF -- "$2"; then
        fail=$((fail + 1))
        printf 'FAIL: %s\n  expected NOT to contain: %s\n' "$1" "$2" >&2
    else
        pass=$((pass + 1))
    fi
}

if [ ! -f "$RUNNER" ]; then
    echo "FAIL: runner not found at $RUNNER" >&2
    exit 1
fi

WORK="$(mktemp -d)" || { echo "FAIL: mktemp failed" >&2; exit 1; }
if [ -z "$WORK" ] || [ ! -d "$WORK" ]; then
    echo "FAIL: bad sandbox dir" >&2
    exit 1
fi
trap 'rm -rf "$WORK"' EXIT

write_test() { # write_test <abs-path> <body...>
    local target="$1"; shift
    mkdir -p "$(dirname "$target")"
    {
        printf '#!/usr/bin/env bash\n'
        printf '%s\n' "$@"
    } > "$target"
    chmod +x "$target"
}

# ---------------------------------------------------------------------------
# Fixture: one tree carrying every classification the runner must distinguish.
# ---------------------------------------------------------------------------
ROOT="${WORK}/tree"
RELDIR="demo-plugin/skills/alpha/scripts/tests"
TDIR="${ROOT}/${RELDIR}"

# Discovery runs from inside --root against relative paths (#2219), so the
# runner reports `./<repo-relative>` no matter how --root was spelled. Assert on
# that form, not on the absolute fixture path.
REPDIR="./${RELDIR}"

# Real work happened → PASS.
write_test "${TDIR}/test-aaa-passes.sh" \
    'echo "=== ALPHA ==="' 'echo "STATUS=OK"' 'exit 0'

# Whole-suite skip, colon form (the common shape).
write_test "${TDIR}/test-bbb-skips.sh" \
    'echo "SKIP: widget CLI not available"' 'exit 0'

# Whole-suite skip, dash form (blueprint-plugin's check-manifest-schema uses
# `SKIP - ...`; a colon-only matcher misses it and reports a pass).
write_test "${TDIR}/test-ccc-skips-dash.sh" \
    'printf "SKIP - uv unavailable; needs it\n"' 'exit 0'

# Whole-suite skip followed by an INDENTED continuation line — the exact shape
# hooks-plugin/hooks/test-bash-antipatterns.sh emits. A naive "every line must
# start with SKIP" rule reports this as a pass.
write_test "${TDIR}/test-ddd-skips-continuation.sh" \
    'echo "SKIP: ast-grep not installed; structural assertions require it."' \
    'echo "      Install: npm install -g @ast-grep/cli"' 'exit 0'

# PARTIAL skip inside a suite that otherwise ran → must stay a PASS. This is
# the false-positive guard: over-eager skip detection would silently stop
# counting real coverage.
write_test "${TDIR}/test-eee-partial-skip.sh" \
    'echo "=== SECTION ONE ==="' \
    'echo "SKIP: optional sub-check needs docker"' \
    'echo "PASS_COUNT=3"' 'exit 0'

# Skips emitted to stderr still count (the runner merges 2>&1).
write_test "${TDIR}/test-fff-skips-stderr.sh" \
    'echo "SKIP: cargo-generate not available" >&2' 'exit 0'

# A .claude/worktrees/ clone must be pruned, not double-counted (#1492/#1548).
write_test "${ROOT}/.claude/worktrees/agent-deadbeef/demo-plugin/skills/alpha/scripts/tests/test-aaa-passes.sh" \
    'echo "STATUS=OK"' 'exit 0'

# ---------------------------------------------------------------------------
# CASE 1 — classification, no required set
# ---------------------------------------------------------------------------
out="$(bash "$RUNNER" --root "$ROOT" 2>&1)"
rc=$?

check "case 1: exit 0 (skips warn, they do not fail)" "0" "$rc"
check "case 1: TOTAL counts every discovered test once" "TOTAL=6" \
    "$(printf '%s\n' "$out" | grep -m1 '^TOTAL=')"
# Guard integrity: without a real pass, every "not a pass" assertion below is
# vacuous, and a runner that classified EVERYTHING as a skip would sail through.
check "case 1: genuinely-passing tests still counted (guard integrity)" "PASSED=2" \
    "$(printf '%s\n' "$out" | grep -m1 '^PASSED=')"
check "case 1: skips counted separately, not folded into PASS" "SKIPPED=4" \
    "$(printf '%s\n' "$out" | grep -m1 '^SKIPPED=')"
check "case 1: no failures" "FAILED=0" \
    "$(printf '%s\n' "$out" | grep -m1 '^FAILED=')"
check "case 1: a run with skips is not silently OK" "STATUS=WARN" \
    "$(printf '%s\n' "$out" | grep -m1 '^STATUS=')"

# The headline defect, asserted per test file.
check_contains "case 1: colon-form skip reported as SKIP=" \
    "SKIP=${REPDIR}/test-bbb-skips.sh" "$out"
check_absent "case 1: colon-form skip NOT reported as PASS=" \
    "PASS=${REPDIR}/test-bbb-skips.sh" "$out"
check_contains "case 1: dash-form skip reported as SKIP=" \
    "SKIP=${REPDIR}/test-ccc-skips-dash.sh" "$out"
check_contains "case 1: skip with indented continuation reported as SKIP=" \
    "SKIP=${REPDIR}/test-ddd-skips-continuation.sh" "$out"
check_contains "case 1: stderr-only skip reported as SKIP=" \
    "SKIP=${REPDIR}/test-fff-skips-stderr.sh" "$out"

# False-positive guard: a partial skip is a pass, not a skip.
check_contains "case 1: partial skip stays a PASS" \
    "PASS=${REPDIR}/test-eee-partial-skip.sh" "$out"
check_absent "case 1: partial skip is NOT reported as SKIP=" \
    "SKIP=${REPDIR}/test-eee-partial-skip.sh" "$out"

# The reason has to survive to the summary, or the operator cannot act on it.
check_contains "case 1: SKIPS: block present" "SKIPS:" "$out"
check_contains "case 1: skip reason surfaced" "widget CLI not available" "$out"

check_absent "case 1: .claude/worktrees/ clone pruned, not scanned" \
    ".claude/worktrees" "$out"

# ---------------------------------------------------------------------------
# CASE 2 — a required test that SKIPs is an ERROR, not a warning
# ---------------------------------------------------------------------------
REQ="${WORK}/required-skipping.txt"
{
    echo "# comment lines and blanks are ignored"
    echo ""
    echo "demo-plugin/skills/alpha/scripts/tests/test-bbb-skips.sh"
} > "$REQ"

out="$(bash "$RUNNER" --root "$ROOT" --required-file "$REQ" 2>&1)"
rc=$?

check "case 2: required test skipping fails the run" "1" "$rc"
check "case 2: STATUS escalates to ERROR" "STATUS=ERROR" \
    "$(printf '%s\n' "$out" | grep -m1 '^STATUS=')"
check "case 2: one violation counted" "REQUIRED_VIOLATIONS=1" \
    "$(printf '%s\n' "$out" | grep -m1 '^REQUIRED_VIOLATIONS=')"
check_contains "case 2: violation names the test and its type" \
    "TYPE=required_test_skipped TEST=demo-plugin/skills/alpha/scripts/tests/test-bbb-skips.sh" "$out"
check_contains "case 2: manifest size reported" "REQUIRED_DECLARED=1" "$out"

# ---------------------------------------------------------------------------
# CASE 3 — a required test that PASSES raises nothing (guard integrity)
# ---------------------------------------------------------------------------
REQ_OK="${WORK}/required-passing.txt"
echo "demo-plugin/skills/alpha/scripts/tests/test-aaa-passes.sh" > "$REQ_OK"

out="$(bash "$RUNNER" --root "$ROOT" --required-file "$REQ_OK" 2>&1)"
rc=$?

check "case 3: required test that runs raises nothing" "0" "$rc"
check "case 3: no violations" "REQUIRED_VIOLATIONS=0" \
    "$(printf '%s\n' "$out" | grep -m1 '^REQUIRED_VIOLATIONS=')"
check_absent "case 3: no required_test_skipped issue" "required_test_skipped" "$out"

# ---------------------------------------------------------------------------
# CASE 4 — manifest drift: a listed path that matches no discovered test
# ---------------------------------------------------------------------------
REQ_DRIFT="${WORK}/required-drift.txt"
echo "demo-plugin/skills/alpha/scripts/tests/test-renamed-away.sh" > "$REQ_DRIFT"

out="$(bash "$RUNNER" --root "$ROOT" --required-file "$REQ_DRIFT" 2>&1)"
rc=$?

check "case 4: a stale manifest entry fails the run" "1" "$rc"
check_contains "case 4: drift reported by type and path" \
    "TYPE=required_test_missing TEST=demo-plugin/skills/alpha/scripts/tests/test-renamed-away.sh" "$out"

# ---------------------------------------------------------------------------
# CASE 5 — a genuine failure still fails, and outranks the skip WARN
# ---------------------------------------------------------------------------
FAILROOT="${WORK}/failtree"
FTDIR="${FAILROOT}/demo-plugin/skills/alpha/scripts/tests"
write_test "${FTDIR}/test-aaa-passes.sh" 'echo "STATUS=OK"' 'exit 0'
write_test "${FTDIR}/test-bbb-skips.sh" 'echo "SKIP: nope"' 'exit 0'
write_test "${FTDIR}/test-ccc-fails.sh" 'echo "assertion blew up"' 'exit 1'

out="$(bash "$RUNNER" --root "$FAILROOT" 2>&1)"
rc=$?

check "case 5: a failing test fails the run" "1" "$rc"
check "case 5: STATUS=ERROR outranks the skip WARN" "STATUS=ERROR" \
    "$(printf '%s\n' "$out" | grep -m1 '^STATUS=')"
check "case 5: failure counted" "FAILED=1" \
    "$(printf '%s\n' "$out" | grep -m1 '^FAILED=')"
check "case 5: skip still counted alongside the failure" "SKIPPED=1" \
    "$(printf '%s\n' "$out" | grep -m1 '^SKIPPED=')"
check_contains "case 5: failure log still echoed" "assertion blew up" "$out"

# ---------------------------------------------------------------------------
# CASE 6 — greenfield: no tests found stays exit 0, but is never a clean OK
#
# The denominator half of #2221 (and the same hole #2255/#2290 found in the
# check-*.sh guards): "found nothing" and "checked nothing" must not look alike.
# Exit stays 0 so the runner is still safe to wire in before any test exists.
# ---------------------------------------------------------------------------
EMPTY="${WORK}/empty"
mkdir -p "$EMPTY"
out="$(bash "$RUNNER" --root "$EMPTY" 2>&1)"
rc=$?
check "case 6: empty corpus still exits 0 (greenfield-safe)" "0" "$rc"
check "case 6: empty corpus is flagged, not a clean OK" "STATUS=WARN" \
    "$(printf '%s\n' "$out" | grep -m1 '^STATUS=')"
check "case 6: scanning nothing is stated explicitly" "SCANNED_EMPTY=true" \
    "$(printf '%s\n' "$out" | grep -m1 '^SCANNED_EMPTY=')"
check "case 6: nothing discovered" "TOTAL=0" \
    "$(printf '%s\n' "$out" | grep -m1 '^TOTAL=')"

# Guard integrity: SCANNED_EMPTY must actually discriminate. A runner that
# hardcoded `true` would pass every assertion above.
out="$(bash "$RUNNER" --root "$ROOT" 2>&1)"
check "case 6: a non-empty corpus reports SCANNED_EMPTY=false" "SCANNED_EMPTY=false" \
    "$(printf '%s\n' "$out" | grep -m1 '^SCANNED_EMPTY=')"

# A declared manifest turns a discovery collapse into an ERROR by construction:
# every entry raises required_test_missing. This is what makes the CI side fail
# loudly rather than warn when discovery breaks.
out="$(bash "$RUNNER" --root "$EMPTY" --required-file "$REQ" 2>&1)"
rc=$?
check "case 6: empty corpus + declared manifest is an ERROR, not a WARN" "1" "$rc"
check_contains "case 6: the collapse names the undiscovered required test" \
    "TYPE=required_test_missing" "$out"

# ---------------------------------------------------------------------------
# CASE 7 — an unknown argument is rejected, never swallowed (#2057)
# ---------------------------------------------------------------------------
out="$(bash "$RUNNER" --root "$ROOT" --requiredd-file "$REQ" 2>&1)"
rc=$?
check "case 7: unknown argument exits 2" "2" "$rc"
check_contains "case 7: the unknown flag is named" "--requiredd-file" "$out"
check_contains "case 7: usage printed" "Usage:" "$out"
check_absent "case 7: nothing was scanned" "TOTAL=" "$out"

# ---------------------------------------------------------------------------
# CASE 8 — the repo's own manifest resolves (paths exist on disk)
# ---------------------------------------------------------------------------
REPO_ROOT="${SCRIPT_DIR}/../.."
MANIFEST="${REPO_ROOT}/scripts/required-to-run-tests.txt"
if [ -f "$MANIFEST" ]; then
    missing=0
    declared=0
    while IFS= read -r line; do
        line="${line%%#*}"
        line="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        [ -n "$line" ] || continue
        declared=$((declared + 1))
        [ -f "${REPO_ROOT}/${line}" ] || { missing=$((missing + 1)); echo "  missing: $line" >&2; }
    done < "$MANIFEST"
    check "case 8: every required-to-run entry exists on disk" "0" "$missing"
    # Guard integrity: an empty manifest would make the check above vacuous.
    if [ "$declared" -gt 0 ]; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        echo "FAIL: case 8: manifest declares nothing (assertion would be vacuous)" >&2
    fi
else
    echo "FAIL: case 8: scripts/required-to-run-tests.txt not found" >&2
    fail=$((fail + 1))
fi

# ---------------------------------------------------------------------------
# CASE 9 — the scan root is ITSELF an agent worktree (#2219)
#
# The defect: discovery ran `find "$root_dir"` against an ABSOLUTE base while
# pruning the bare glob `*/.claude/worktrees/*`. When the root's own path
# contains `/.claude/worktrees/`, every descendant matches the prune, the whole
# walk is skipped, and the runner reports TOTAL=0 — a discovery collapse that
# reads as "this tree has no tests".
#
# This is the shape an agent hits verifying its own change: worktree-isolated
# subagents are this repo's normal way of doing plugin work, so `--root "$PWD"`
# from inside one was structurally incapable of finding a test.
# ---------------------------------------------------------------------------
WTROOT="${WORK}/host/.claude/worktrees/agent-f00dcafe"
write_test "${WTROOT}/${RELDIR}/test-aaa-passes.sh" 'echo "STATUS=OK"' 'exit 0'
write_test "${WTROOT}/${RELDIR}/test-bbb-skips.sh" 'echo "SKIP: widget CLI not available"' 'exit 0'

out="$(bash "$RUNNER" --root "$WTROOT" 2>&1)"
rc=$?

check "case 9: a worktree-shaped root still discovers its tests" "TOTAL=2" \
    "$(printf '%s\n' "$out" | grep -m1 '^TOTAL=')"
check "case 9: discovery did not collapse to an empty corpus" "SCANNED_EMPTY=false" \
    "$(printf '%s\n' "$out" | grep -m1 '^SCANNED_EMPTY=')"
# Guard integrity: TOTAL=2 alone would hold for a runner that discovered the
# files but ran none of them. The tests must actually EXECUTE and classify.
check "case 9: the discovered test actually ran (guard integrity)" "PASSED=1" \
    "$(printf '%s\n' "$out" | grep -m1 '^PASSED=')"
check_contains "case 9: classification still works from a worktree-shaped root" \
    "SKIP=${REPDIR}/test-bbb-skips.sh" "$out"
check "case 9: run is otherwise clean" "0" "$rc"

# The manifest is matched on the repo-relative form, so a required test declared
# under a worktree-shaped root must still resolve. Pre-fix this raised
# `required_test_missing` for every entry, because nothing was ever discovered.
out="$(bash "$RUNNER" --root "$WTROOT" --required-file "$REQ_OK" 2>&1)"
rc=$?
check "case 9: required-test matching survives a worktree-shaped root" "0" "$rc"
check_absent "case 9: no phantom manifest drift" "required_test_missing" "$out"

# Guard integrity, the other direction: the fix must not have simply disabled
# pruning. A worktree clone NESTED below the root is still pruned, even when the
# root is itself worktree-shaped.
write_test "${WTROOT}/.claude/worktrees/agent-nested/${RELDIR}/test-aaa-passes.sh" \
    'echo "STATUS=OK"' 'exit 0'
out="$(bash "$RUNNER" --root "$WTROOT" 2>&1)"
check "case 9: a nested worktree clone is still pruned" "TOTAL=2" \
    "$(printf '%s\n' "$out" | grep -m1 '^TOTAL=')"
check_absent "case 9: no nested worktree path leaks into the report" \
    "agent-nested" "$out"

# ---------------------------------------------------------------------------
# CASE 10 — a --root that does not resolve fails fast
#
# It must not read as "found nothing": a typo'd root reporting SCANNED_EMPTY /
# WARN / exit 0 is the same silent-empty-corpus failure #2219 is about.
# ---------------------------------------------------------------------------
out="$(bash "$RUNNER" --root "${WORK}/no-such-tree" 2>&1)"
rc=$?
check "case 10: an unresolvable --root exits 2" "2" "$rc"
check_contains "case 10: the bad root is named" "no-such-tree" "$out"
check_absent "case 10: it is not reported as an empty scan" "SCANNED_EMPTY=true" "$out"

# ---------------------------------------------------------------------------
# CASE 11 — repo-root `scripts/tests/test-*.sh` is discovered (#2333)
#
# The three original globs (`*/skills/*/scripts/tests/`, `*-plugin/scripts/tests/`,
# `*/hooks/`) all missed repo-root `scripts/tests/`, where the self-tests of the
# whole-repo `check-*.sh` guards live. A guard there therefore had no CI signal
# unless somebody hand-wired a step into plugin-pr-checks.yml — which is how the
# same class shipped three times (#2219, #2221, #2333).
#
# The glob is ANCHORED (`./scripts/tests/…`), not `*/scripts/tests/…`: discovery
# runs from inside the root against `.`-relative paths (#2219), so `./scripts`
# names this tree's scripts dir and nothing else. Both halves are asserted —
# discovery AND the anchor — because a `*/`-spelled fix would pass the first
# assertion while quietly swallowing every nested `scripts/tests/` in the tree.
# ---------------------------------------------------------------------------
ROOTSCRIPTS="${WORK}/rootscripts"

# The target: a repo-root guard self-test.
write_test "${ROOTSCRIPTS}/scripts/tests/test-check-widget.sh" \
    'echo "PASSED=3"' 'exit 0'
# A repo-root test that skips must classify as a SKIP here too, not a PASS.
write_test "${ROOTSCRIPTS}/scripts/tests/test-check-gadget.sh" \
    'echo "SKIP: gadget CLI not available"' 'exit 0'
# Anchor guard: a `scripts/tests/` nested somewhere else in the tree is NOT the
# repo-root one and must stay undiscovered. `tools/` is deliberately not a
# `*-plugin` dir, so no other glob can claim it either.
write_test "${ROOTSCRIPTS}/tools/scripts/tests/test-nested-widget.sh" \
    'echo "PASSED=1"' 'exit 0'
# Guard integrity: the pre-existing globs must keep working alongside the new
# one, so a discovery count is attributable rather than a coincidence.
write_test "${ROOTSCRIPTS}/demo-plugin/skills/alpha/scripts/tests/test-skill-local.sh" \
    'echo "PASSED=1"' 'exit 0'

out="$(bash "$RUNNER" --root "$ROOTSCRIPTS" 2>&1)"
rc=$?

check_contains "case 11: a repo-root guard self-test is discovered and run" \
    "PASS=./scripts/tests/test-check-widget.sh" "$out"
check_contains "case 11: a repo-root test that skips is classified SKIP" \
    "SKIP=./scripts/tests/test-check-gadget.sh" "$out"
check_absent "case 11: the skipping repo-root test is NOT reported as PASS=" \
    "PASS=./scripts/tests/test-check-gadget.sh" "$out"
check_absent "case 11: the glob is anchored — a nested scripts/tests/ is not swallowed" \
    "test-nested-widget.sh" "$out"
# The denominator: 2 repo-root + 1 skill-local, and NOT the nested decoy. An
# exact TOTAL is safe here because this fixture tree is planted by this test.
check "case 11: TOTAL counts the repo-root tests and excludes the nested decoy" "TOTAL=3" \
    "$(printf '%s\n' "$out" | grep -m1 '^TOTAL=')"
check "case 11: the pre-existing globs still discover their own tests" "PASSED=2" \
    "$(printf '%s\n' "$out" | grep -m1 '^PASSED=')"
check "case 11: run is otherwise clean (a skip warns, it does not fail)" "0" "$rc"

# A repo-root test is manifest-eligible like any other discovered test — the
# entry is matched on the same repo-relative form the runner reports.
REQ_ROOT="${WORK}/required-root.txt"
echo "scripts/tests/test-check-gadget.sh" > "$REQ_ROOT"
out="$(bash "$RUNNER" --root "$ROOTSCRIPTS" --required-file "$REQ_ROOT" 2>&1)"
rc=$?
check "case 11: a required repo-root test that skips fails the run" "1" "$rc"
check_contains "case 11: the violation names the repo-root path" \
    "TYPE=required_test_skipped TEST=scripts/tests/test-check-gadget.sh" "$out"

# Composes with #2219: a worktree-shaped root must find its OWN scripts/tests/.
# Absolute-path spellings of the new glob break here, quietly.
WTSCRIPTS="${WORK}/host2/.claude/worktrees/agent-beefcafe"
write_test "${WTSCRIPTS}/scripts/tests/test-check-widget.sh" 'echo "PASSED=1"' 'exit 0'
out="$(bash "$RUNNER" --root "$WTSCRIPTS" 2>&1)"
check "case 11: worktree-shaped root still discovers its repo-root tests" "TOTAL=1" \
    "$(printf '%s\n' "$out" | grep -m1 '^TOTAL=')"
check_contains "case 11: and actually runs them" \
    "PASS=./scripts/tests/test-check-widget.sh" "$out"

echo "=== SUMMARY ==="
echo "PASS_COUNT=${pass}"
echo "FAIL_COUNT=${fail}"
if [ "$fail" -eq 0 ]; then
    echo "STATUS=OK"
    exit 0
fi
echo "STATUS=FAIL"
exit 1
