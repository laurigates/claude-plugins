#!/usr/bin/env bash
# test-check-dead-api-endpoints.sh — regression suite for
# scripts/check-dead-api-endpoints.sh
#
# SEMANTIC: every case EXECUTES the guard against a planted fixture tree. The
# negative cases carry as much weight as the positives — a guard that flagged
# every mention of a retired endpoint would also flag the files that TEACH the
# hazard, and would be disabled within a week.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD="${SCRIPT_DIR}/../check-dead-api-endpoints.sh"

[ -f "$GUARD" ] || { echo "FAIL: guard not found at $GUARD"; exit 1; }

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n     wanted: %s\n     got:    %s\n' "$1" "$2" "$3"; }
assert_contains() {
    case "$2" in
        *"$3"*) ok "$1" ;;
        *) bad "$1" "output containing '$3'" "$(printf '%s' "$2" | head -c 240)" ;;
    esac
}
assert_lacks() {
    case "$2" in
        *"$3"*) bad "$1" "output WITHOUT '$3'" "$(printf '%s' "$2" | head -c 240)" ;;
        *) ok "$1" ;;
    esac
}
# Runs the command itself rather than inspecting `$?` afterwards, and uses
# if/else rather than `A && B || C` — in an assertion helper the short-circuit
# form runs `bad` whenever `ok` returns non-zero.
assert_exit() {
    local label="$1" want="$2"
    shift 2
    "$@" >/dev/null 2>&1
    local got=$?
    if [ "$got" -eq "$want" ]; then ok "$label"; else bad "$label" "exit $want" "exit $got"; fi
}
assert_ge() {
    if [ "${2:-0}" -ge "$3" ] 2>/dev/null; then ok "$1 ($2)"; else bad "$1" ">=$3" "${2:-<empty>}"; fi
}

FIX=$(mktemp -d)
if [ -z "$FIX" ] || [ ! -d "$FIX" ]; then
    echo "FAIL: no fixture dir"
    exit 1
fi
trap 'rm -rf "$FIX"' EXIT

mkdir -p "$FIX/demo-plugin/skills/thing/scripts"

echo "TEST 1: a live call to a retired endpoint is caught"
cat > "$FIX/demo-plugin/skills/thing/scripts/run.sh" <<'SH'
#!/usr/bin/env bash
gh api "/orgs/$ORG/settings/billing/actions" --jq '.total_minutes_used' 2>/dev/null
SH
out=$(bash "$GUARD" --project-dir "$FIX" 2>&1)
assert_contains "the retired endpoint is reported" "$out" "TYPE=dead_endpoint"
assert_contains "the finding names the file" "$out" "run.sh:2"
assert_contains "the finding names the replacement" "$out" "billing/usage"
assert_exit "--strict exits 1 on a finding" 1 bash "$GUARD" --project-dir "$FIX" --strict

echo "TEST 2: a plain run reports but does not fail the build"
assert_exit "non-strict exits 0" 0 bash "$GUARD" --project-dir "$FIX"

echo "TEST 3: teaching the hazard is NOT a finding"
# Without this, the guard would flag the fix's own explanatory comments, the
# rule that documents the 410, and its own denylist.
rm "$FIX/demo-plugin/skills/thing/scripts/run.sh"
cat > "$FIX/demo-plugin/skills/thing/scripts/run.sh" <<'SH'
#!/usr/bin/env bash
# /settings/billing/actions returns HTTP 410; use /settings/billing/usage.
gh api "/orgs/$ORG/settings/billing/usage" --jq '.usageItems'
SH
cat > "$FIX/demo-plugin/skills/thing/SKILL.md" <<'MD'
# thing

> Historical note: `/orgs/{org}/settings/billing/actions` was retired and now
> returns HTTP 410. Use the usage endpoint instead.
MD
out=$(bash "$GUARD" --project-dir "$FIX" 2>&1)
assert_contains "a tree that only teaches the hazard is clean" "$out" "ISSUE_COUNT=0"
assert_contains "clean tree reports STATUS=OK" "$out" "STATUS=OK"

echo "TEST 4: guard integrity — the corpus was actually read"
# Without this, TEST 3's 'clean' assertions would also pass against a guard
# that discovered nothing at all.
assert_lacks "a non-empty tree is not reported as empty" "$out" "SCANNED_EMPTY=true"
scanned=$(printf '%s' "$out" | sed -n 's/^FILES_SCANNED=//p')
assert_ge "fixture files were scanned" "$scanned" 2

echo "TEST 5: the comment skip is narrow, not a blanket mute"
# A real call must still be caught in a file that ALSO carries an explanatory
# comment — otherwise TEST 3 could pass by muting whole files.
cat >> "$FIX/demo-plugin/skills/thing/scripts/run.sh" <<'SH'
gh api "/orgs/$ORG/settings/billing/packages" --jq '.'
SH
out=$(bash "$GUARD" --project-dir "$FIX" 2>&1)
assert_contains "a live call beside a comment is still caught" "$out" "settings/billing/packages"
assert_contains "exactly one finding in that file" "$out" "ISSUE_COUNT=1"

echo "TEST 6: an empty tree is OK, not an error"
EMPTY=$(mktemp -d)
out=$(bash "$GUARD" --project-dir "$EMPTY" 2>&1)
assert_contains "empty tree marks itself empty" "$out" "SCANNED_EMPTY=true"
assert_contains "empty tree reports STATUS=OK" "$out" "STATUS=OK"
assert_exit "empty tree exits 0 even under --strict" 0 bash "$GUARD" --project-dir "$EMPTY" --strict
rm -rf "$EMPTY"

echo "TEST 7: a misfired walk is distinguishable from a clean one"
MISFIRE=$(mktemp -d)
mkdir -p "$MISFIRE/demo-plugin"
out=$(bash "$GUARD" --project-dir "$MISFIRE" 2>&1)
assert_contains "plugin dirs but no files is an ERROR, not a clean OK" "$out" "TYPE=nothing_scanned"
rm -rf "$MISFIRE"

echo "TEST 8: argument handling"
assert_exit "unknown argument exits 2" 2 bash "$GUARD" --no-such-flag
assert_exit "missing --project-dir exits 2" 2 bash "$GUARD" --project-dir "$FIX/does-not-exist"

echo
echo "=== DEAD API ENDPOINT GUARD TESTS ==="
echo "PASSED=$PASS"
echo "FAILED=$FAIL"
if [ "$FAIL" -gt 0 ]; then
    echo "STATUS=FAIL"
    exit 1
fi
echo "STATUS=OK"
exit 0
