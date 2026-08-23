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

# ---------------------------------------------------------------------------
# Fixture: a second tree with tests in DISTINGUISHABLE locations, so a scoped
# run's subset is attributable. Kept separate from $ROOT on purpose — adding
# files there would move CASE 1's TOTAL=6 denominator.
# ---------------------------------------------------------------------------
SCOPEROOT="${WORK}/scope-tree"

write_test "${SCOPEROOT}/alpha-plugin/skills/one/scripts/tests/test-alpha.sh" \
    'echo "PASSED=1"' 'exit 0'
write_test "${SCOPEROOT}/beta-plugin/skills/two/scripts/tests/test-beta.sh" \
    'echo "PASSED=1"' 'exit 0'
write_test "${SCOPEROOT}/beta-plugin/hooks/test-beta-hook.sh" \
    'echo "PASSED=1"' 'exit 0'
write_test "${SCOPEROOT}/gamma-plugin/skills/three/scripts/tests/test-gamma-skips.sh" \
    'echo "SKIP: heavy toolchain not installed"' 'exit 0'
write_test "${SCOPEROOT}/scripts/tests/test-root-guard.sh" \
    'echo "PASSED=1"' 'exit 0'

# ---------------------------------------------------------------------------
# CASE 12 — --only selects the expected subset, and is repeatable
#
# The negative half carries the weight: a scope filter that matched EVERYTHING
# (a no-op) would satisfy every "the wanted test ran" assertion on its own.
#
# DISCOVERED= is asserted alongside TOTAL= in every scoped run below. Scoping
# must FILTER what was discovered, never narrow discovery itself — a "fix" that
# pushed the globs into the `find` would pass the subset assertions while
# destroying the misfire-vs-collapse distinction CASE 13 depends on.
# ---------------------------------------------------------------------------
out="$(bash "$RUNNER" --root "$SCOPEROOT" --only 'alpha-plugin/*' 2>&1)"
rc=$?

check "case 12: a scoped run is otherwise clean" "0" "$rc"
# A scoped run with no skips must be a clean OK. If deferred tests were folded
# into SKIPPED=, this would read WARN while still exiting 0 — a mass-SKIP
# wearing a passing exit code, which is exactly the shape #2219 burned on.
check "case 12: a scoped run with nothing skipped is OK, not WARN" "STATUS=OK" \
    "$(printf '%s\n' "$out" | grep -m1 '^STATUS=')"
check "case 12: only the in-scope test ran" "TOTAL=1" \
    "$(printf '%s\n' "$out" | grep -m1 '^TOTAL=')"
check "case 12: discovery is unchanged by scoping" "DISCOVERED=5" \
    "$(printf '%s\n' "$out" | grep -m1 '^DISCOVERED=')"
check "case 12: the excluded tests are accounted for, not lost" "OUT_OF_SCOPE=4" \
    "$(printf '%s\n' "$out" | grep -m1 '^OUT_OF_SCOPE=')"
check "case 12: the run states that it was scoped" "SCOPED=true" \
    "$(printf '%s\n' "$out" | grep -m1 '^SCOPED=')"
check "case 12: the scope is echoed back" "SCOPE_PATTERN_1=alpha-plugin/*" \
    "$(printf '%s\n' "$out" | grep -m1 '^SCOPE_PATTERN_1=')"
check_contains "case 12: the in-scope test ran" \
    "PASS=./alpha-plugin/skills/one/scripts/tests/test-alpha.sh" "$out"
# The negative half — without these a no-op filter passes everything above.
check_absent "case 12: an out-of-scope sibling did NOT run" \
    "test-beta.sh" "$out"
check_absent "case 12: an out-of-scope hook suite did NOT run" \
    "test-beta-hook.sh" "$out"
check_absent "case 12: an out-of-scope repo-root guard test did NOT run" \
    "test-root-guard.sh" "$out"
# An out-of-scope SKIPPING test must not land in SKIPPED= — deferred, not
# skipped. Folding it in would make every scoped run look like a mass-SKIP.
check "case 12: an out-of-scope skip is deferred, not counted as skipped" "SKIPPED=0" \
    "$(printf '%s\n' "$out" | grep -m1 '^SKIPPED=')"
check_absent "case 12: the deferred test is not reported as SKIP=" \
    "test-gamma-skips.sh" "$out"

# Repeatable: any glob matching wins.
out="$(bash "$RUNNER" --root "$SCOPEROOT" --only 'alpha-plugin/*' --only '*/hooks/test-*.sh' 2>&1)"
rc=$?

check "case 12: two globs select the union" "TOTAL=2" \
    "$(printf '%s\n' "$out" | grep -m1 '^TOTAL=')"
check "case 12: both globs are reported" "SCOPE_PATTERN_COUNT=2" \
    "$(printf '%s\n' "$out" | grep -m1 '^SCOPE_PATTERN_COUNT=')"
check "case 12: the second glob is echoed back" "SCOPE_PATTERN_2=*/hooks/test-*.sh" \
    "$(printf '%s\n' "$out" | grep -m1 '^SCOPE_PATTERN_2=')"
check_contains "case 12: glob 1 selected its test" \
    "PASS=./alpha-plugin/skills/one/scripts/tests/test-alpha.sh" "$out"
check_contains "case 12: glob 2 selected its test" \
    "PASS=./beta-plugin/hooks/test-beta-hook.sh" "$out"
check_absent "case 12: a sibling of glob 2's plugin is still excluded" \
    "test-beta.sh" "$out"
check "case 12: the union run is clean" "0" "$rc"

# `*` crosses `/` (plain `case` glob) — the documented semantics the
# plugin-pr-checks consumer relies on to name a whole class of suite.
out="$(bash "$RUNNER" --root "$SCOPEROOT" --only '*-plugin/hooks/test-*.sh' 2>&1)"
check "case 12: a cross-directory glob selects the hook suites" "TOTAL=1" \
    "$(printf '%s\n' "$out" | grep -m1 '^TOTAL=')"
check_contains "case 12: and it is the hook suite" \
    "PASS=./beta-plugin/hooks/test-beta-hook.sh" "$out"

# ---------------------------------------------------------------------------
# CASE 13 — a scope that matches NOTHING is loud, never a bare pass
#
# This is the anti-mass-SKIP guard. A scoped call that selects zero suites is a
# caller misfire (a typo'd glob, a plugin that moved), which is a stronger
# condition than the greenfield empty corpus of CASE 6 — the caller named the
# scope explicitly. It must not be reachable as exit 0 by any reading.
# ---------------------------------------------------------------------------
out="$(bash "$RUNNER" --root "$SCOPEROOT" --only 'no-such-plugin/*' 2>&1)"
rc=$?

check "case 13: a scope matching nothing fails the run" "1" "$rc"
check "case 13: scanning nothing is stated explicitly" "SCANNED_EMPTY=true" \
    "$(printf '%s\n' "$out" | grep -m1 '^SCANNED_EMPTY=')"
check "case 13: nothing ran" "TOTAL=0" \
    "$(printf '%s\n' "$out" | grep -m1 '^TOTAL=')"
check "case 13: it is an ERROR, not the greenfield WARN" "STATUS=ERROR" \
    "$(printf '%s\n' "$out" | grep -m1 '^STATUS=')"
check_contains "case 13: the misfire is named by type" \
    "TYPE=scope_matched_nothing" "$out"
check_absent "case 13: nothing is reported as having passed" "PASS=./" "$out"
# The discriminator: a scope misfire and a discovery collapse both yield
# TOTAL=0, and they need different fixes. DISCOVERED= tells them apart.
check "case 13: discovery is reported, so a misfire is not a collapse" "DISCOVERED=5" \
    "$(printf '%s\n' "$out" | grep -m1 '^DISCOVERED=')"
check_contains "case 13: the issue row carries the discovery count" \
    "TYPE=scope_matched_nothing DISCOVERED=5" "$out"

# ---------------------------------------------------------------------------
# CASE 13b — EVERY glob must match, not just one of them
#
# The aggregate "did anything match?" guard of CASE 13 is not sufficient. With
# one live glob and one stale one, the stale glob was silently ignored and the
# run reported STATUS=OK / exit 0. That is strictly WEAKER than the hand-written
# `run: bash scripts/tests/test-foo.sh` steps this scoping replaced, which died
# loudly (exit 127) the moment a test was renamed.
#
# The failure mode it enables is the worst one available to a REQUIRED check:
# rename a test, and it silently stops running while the check stays green. So
# the guard is per-pattern, and the load-bearing assertion is that a run with a
# PASSING test alongside a stale glob still fails.
# ---------------------------------------------------------------------------
out="$(bash "$RUNNER" --root "$SCOPEROOT" \
    --only '*/skills/one/scripts/tests/test-alpha.sh' \
    --only 'scripts/tests/test-RENAMED-AWAY.sh' 2>&1)"
rc=$?

check "case 13b: one stale glob fails the run even though another matched" "1" "$rc"
check "case 13b: it is an ERROR" "STATUS=ERROR" \
    "$(printf '%s\n' "$out" | grep -m1 '^STATUS=')"
check_contains "case 13b: the misfire is named per-pattern" \
    "TYPE=scope_pattern_matched_nothing" "$out"
check_contains "case 13b: the offending glob is named" \
    "PATTERN=scripts/tests/test-RENAMED-AWAY.sh" "$out"
# The live glob really did run: this is not "everything failed".
check "case 13b: the matching test still ran" "TOTAL=1" \
    "$(printf '%s\n' "$out" | grep -m1 '^TOTAL=')"
check "case 13b: and it passed" "PASSED=1" \
    "$(printf '%s\n' "$out" | grep -m1 '^PASSED=')"
# Per-pattern accounting is visible, so a reader can see WHICH glob died.
check "case 13b: the live glob reports its match count" "SCOPE_PATTERN_1_MATCHED=1" \
    "$(printf '%s\n' "$out" | grep -m1 '^SCOPE_PATTERN_1_MATCHED=')"
check "case 13b: the stale glob reports zero" "SCOPE_PATTERN_2_MATCHED=0" \
    "$(printf '%s\n' "$out" | grep -m1 '^SCOPE_PATTERN_2_MATCHED=')"
# It is NOT the aggregate misfire — that one only fires when TOTAL=0.
check_absent "case 13b: it is not misreported as the aggregate misfire" \
    "TYPE=scope_matched_nothing DISCOVERED" "$out"

# Guard integrity: all-live globs must still pass, or the rule is just
# "scoping always fails".
out="$(bash "$RUNNER" --root "$SCOPEROOT" \
    --only '*/skills/one/scripts/tests/test-alpha.sh' \
    --only 'scripts/tests/test-root-guard.sh' 2>&1)"
rc=$?
check "case 13b: two live globs still pass" "0" "$rc"
check "case 13b: and report OK" "STATUS=OK" \
    "$(printf '%s\n' "$out" | grep -m1 '^STATUS=')"
check "case 13b: both ran" "TOTAL=2" \
    "$(printf '%s\n' "$out" | grep -m1 '^TOTAL=')"

# A required-manifest entry must NOT count as a match. in_scope() is called over
# the manifest too, so a naive counter would let a manifest declaration mark a
# glob "hit" and mask exactly the stale glob this case exists to catch.
printf '%s\n' 'scripts/tests/test-RENAMED-AWAY.sh' > "${SCOPEROOT}/scripts/required-to-run-tests.txt"
out="$(bash "$RUNNER" --root "$SCOPEROOT" \
    --only '*/skills/one/scripts/tests/test-alpha.sh' \
    --only 'scripts/tests/test-RENAMED-AWAY.sh' 2>&1)"
rc=$?
check "case 13b: a manifest entry does not mask a stale glob" "1" "$rc"
check_contains "case 13b: still named per-pattern with the manifest present" \
    "TYPE=scope_pattern_matched_nothing" "$out"
rm -f "${SCOPEROOT}/scripts/required-to-run-tests.txt"

# Guard integrity, the other direction: the ERROR belongs to the SCOPED caller.
# An UNSCOPED empty corpus keeps its greenfield-safe WARN / exit 0 (CASE 6's
# contract), so the new rule cannot have been implemented as "TOTAL=0 is fatal".
out="$(bash "$RUNNER" --root "$EMPTY" 2>&1)"
rc=$?
check "case 13: an unscoped empty corpus is still greenfield-safe" "0" "$rc"
check "case 13: and still WARNs rather than ERRORing" "STATUS=WARN" \
    "$(printf '%s\n' "$out" | grep -m1 '^STATUS=')"

# ...while a scoped run against that same empty tree is a misfire.
out="$(bash "$RUNNER" --root "$EMPTY" --only 'anything/*' 2>&1)"
rc=$?
check "case 13: a scoped run over an empty tree is a misfire" "1" "$rc"
check "case 13: with discovery reported as genuinely empty" "DISCOVERED=0" \
    "$(printf '%s\n' "$out" | grep -m1 '^DISCOVERED=')"

# ---------------------------------------------------------------------------
# CASE 14 — required-test accounting under a scope
#
# The documented contract: a required test OUTSIDE the scope is DEFERRED — not
# run, not counted as skipped, no violation — and the output says so via
# REQUIRED_IN_SCOPE= / REQUIRED_OUT_OF_SCOPE=. INSIDE the scope the ratchet
# keeps its full teeth.
#
# Both halves are asserted. Without the teeth half, a "fix" that simply
# disabled required accounting whenever --only was passed would pass the
# deferral half and silently drop the ratchet.
# ---------------------------------------------------------------------------
REQ_SCOPE="${WORK}/required-scope.txt"
{
    echo "alpha-plugin/skills/one/scripts/tests/test-alpha.sh"
    echo "gamma-plugin/skills/three/scripts/tests/test-gamma-skips.sh"
} > "$REQ_SCOPE"

# (a) The required test that SKIPs is OUT of scope → deferred, not a violation.
out="$(bash "$RUNNER" --root "$SCOPEROOT" --required-file "$REQ_SCOPE" --only 'alpha-plugin/*' 2>&1)"
rc=$?

check "case 14a: an out-of-scope required test does not fail the run" "0" "$rc"
check "case 14a: no violation is raised for it" "REQUIRED_VIOLATIONS=0" \
    "$(printf '%s\n' "$out" | grep -m1 '^REQUIRED_VIOLATIONS=')"
check_absent "case 14a: it is not reported as skipped" "required_test_skipped" "$out"
check_absent "case 14a: nor as missing" "required_test_missing" "$out"
check "case 14a: the full manifest size is still reported" "REQUIRED_DECLARED=2" \
    "$(printf '%s\n' "$out" | grep -m1 '^REQUIRED_DECLARED=')"
check "case 14a: the output states how much of it was in scope" "REQUIRED_IN_SCOPE=1" \
    "$(printf '%s\n' "$out" | grep -m1 '^REQUIRED_IN_SCOPE=')"
check "case 14a: and how much was deferred" "REQUIRED_OUT_OF_SCOPE=1" \
    "$(printf '%s\n' "$out" | grep -m1 '^REQUIRED_OUT_OF_SCOPE=')"

# (b) TEETH: the same required test, now IN scope, still fails the run.
out="$(bash "$RUNNER" --root "$SCOPEROOT" --required-file "$REQ_SCOPE" --only 'gamma-plugin/*' 2>&1)"
rc=$?

check "case 14b: an in-scope required test that skips still fails" "1" "$rc"
check "case 14b: STATUS still escalates to ERROR" "STATUS=ERROR" \
    "$(printf '%s\n' "$out" | grep -m1 '^STATUS=')"
check "case 14b: the violation is counted" "REQUIRED_VIOLATIONS=1" \
    "$(printf '%s\n' "$out" | grep -m1 '^REQUIRED_VIOLATIONS=')"
check_contains "case 14b: and names the test" \
    "TYPE=required_test_skipped TEST=gamma-plugin/skills/three/scripts/tests/test-gamma-skips.sh" "$out"
check "case 14b: the deferred sibling is still accounted for" "REQUIRED_OUT_OF_SCOPE=1" \
    "$(printf '%s\n' "$out" | grep -m1 '^REQUIRED_OUT_OF_SCOPE=')"

# (c) TEETH: manifest drift INSIDE the scope is still drift.
REQ_SCOPE_DRIFT="${WORK}/required-scope-drift.txt"
echo "alpha-plugin/skills/one/scripts/tests/test-renamed-away.sh" > "$REQ_SCOPE_DRIFT"

out="$(bash "$RUNNER" --root "$SCOPEROOT" --required-file "$REQ_SCOPE_DRIFT" --only 'alpha-plugin/*' 2>&1)"
rc=$?
check "case 14c: an in-scope stale manifest entry still fails" "1" "$rc"
check_contains "case 14c: reported as drift" \
    "TYPE=required_test_missing TEST=alpha-plugin/skills/one/scripts/tests/test-renamed-away.sh" "$out"
check "case 14c: it counted as in scope" "REQUIRED_IN_SCOPE=1" \
    "$(printf '%s\n' "$out" | grep -m1 '^REQUIRED_IN_SCOPE=')"

# (d) The same stale entry OUTSIDE the scope is deferred, not drift — otherwise
#     every scoped run would be a false ERROR over paths it never looked at.
out="$(bash "$RUNNER" --root "$SCOPEROOT" --required-file "$REQ_SCOPE_DRIFT" --only 'beta-plugin/*' 2>&1)"
rc=$?
check "case 14d: an out-of-scope stale entry does not fail the run" "0" "$rc"
check_absent "case 14d: and is not reported as drift" "required_test_missing" "$out"
check "case 14d: it is accounted for as deferred" "REQUIRED_OUT_OF_SCOPE=1" \
    "$(printf '%s\n' "$out" | grep -m1 '^REQUIRED_OUT_OF_SCOPE=')"
check "case 14d: with nothing claimed as in scope" "REQUIRED_IN_SCOPE=0" \
    "$(printf '%s\n' "$out" | grep -m1 '^REQUIRED_IN_SCOPE=')"

# (e) Guard integrity: unscoped, the whole manifest is enforced exactly as before.
out="$(bash "$RUNNER" --root "$SCOPEROOT" --required-file "$REQ_SCOPE" 2>&1)"
rc=$?
check "case 14e: unscoped, the skipping required test still fails the run" "1" "$rc"
check "case 14e: the whole manifest is in scope" "REQUIRED_IN_SCOPE=2" \
    "$(printf '%s\n' "$out" | grep -m1 '^REQUIRED_IN_SCOPE=')"
check "case 14e: nothing is deferred" "REQUIRED_OUT_OF_SCOPE=0" \
    "$(printf '%s\n' "$out" | grep -m1 '^REQUIRED_OUT_OF_SCOPE=')"

# ---------------------------------------------------------------------------
# CASE 15 — malformed scope arguments are rejected, never swallowed (#2057)
# ---------------------------------------------------------------------------
out="$(bash "$RUNNER" --root "$SCOPEROOT" --onlyy 'alpha-plugin/*' 2>&1)"
rc=$?
check "case 15: a misspelled --only exits 2" "2" "$rc"
check_contains "case 15: the misspelled flag is named" "--onlyy" "$out"
check_absent "case 15: nothing was scanned" "TOTAL=" "$out"

out="$(bash "$RUNNER" --root "$SCOPEROOT" --only 2>&1)"
rc=$?
check "case 15: --only with no value exits 2" "2" "$rc"
check_contains "case 15: the missing value is named" "--only needs a value" "$out"
check_absent "case 15: nothing was scanned for a valueless --only" "TOTAL=" "$out"

# An empty glob matches nothing, which would masquerade as a scope misfire
# rather than the argument error it is. It must be rejected at parse time.
out="$(bash "$RUNNER" --root "$SCOPEROOT" --only '' 2>&1)"
rc=$?
check "case 15: an empty --only glob exits 2" "2" "$rc"
check_contains "case 15: and says the glob must be non-empty" "non-empty glob" "$out"
check_absent "case 15: an empty glob is not reported as a scope misfire" \
    "scope_matched_nothing" "$out"

# ---------------------------------------------------------------------------
# CASE 16 — the UNSCOPED default is unchanged
#
# Every assertion in CASES 1-11 already runs unscoped, so the behavioural
# contract is covered. What is pinned here is that the new keys report the
# no-scope state honestly rather than being emitted only when --only is passed
# (a consumer branching on SCOPED= must be able to read it from every run).
# ---------------------------------------------------------------------------
out="$(bash "$RUNNER" --root "$SCOPEROOT" --required-file "$REQ_SCOPE" 2>&1)"

check "case 16: every discovered test runs" "TOTAL=5" \
    "$(printf '%s\n' "$out" | grep -m1 '^TOTAL=')"
check "case 16: TOTAL equals DISCOVERED when unscoped" "DISCOVERED=5" \
    "$(printf '%s\n' "$out" | grep -m1 '^DISCOVERED=')"
check "case 16: the run states it was not scoped" "SCOPED=false" \
    "$(printf '%s\n' "$out" | grep -m1 '^SCOPED=')"
check "case 16: no globs are reported" "SCOPE_PATTERN_COUNT=0" \
    "$(printf '%s\n' "$out" | grep -m1 '^SCOPE_PATTERN_COUNT=')"
check_absent "case 16: and none are echoed back" "SCOPE_PATTERN_1=" "$out"
check "case 16: nothing is excluded" "OUT_OF_SCOPE=0" \
    "$(printf '%s\n' "$out" | grep -m1 '^OUT_OF_SCOPE=')"
check "case 16: the skipping test is still classified as a skip" "SKIPPED=1" \
    "$(printf '%s\n' "$out" | grep -m1 '^SKIPPED=')"
check "case 16: and the passing ones still pass" "PASSED=4" \
    "$(printf '%s\n' "$out" | grep -m1 '^PASSED=')"

echo "=== SUMMARY ==="
echo "PASS_COUNT=${pass}"
echo "FAIL_COUNT=${fail}"
if [ "$fail" -eq 0 ]; then
    echo "STATUS=OK"
    exit 0
fi
echo "STATUS=FAIL"
exit 1
