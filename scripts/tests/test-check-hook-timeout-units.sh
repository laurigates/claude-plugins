#!/usr/bin/env bash
# Regression test for scripts/check-hook-timeout-units.sh (#3079).
#
# Pins: a millisecond-looking hook timeout (>= 1000) is an ERROR in hooks.json,
# hooks/hooks.json and inline plugin.json hooks; second-scale values (5, 15, 600)
# and entries without a timeout pass; an empty tree is STATUS=ERROR, never a
# silent OK; the output carries REASON= on the non-OK path; and the live
# repository passes.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GUARD="$REPO_ROOT/scripts/check-hook-timeout-units.sh"

PASS=0
FAIL=0
pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

TMP_ROOT="$(mktemp -d)"
if [ -z "$TMP_ROOT" ] || [ ! -d "$TMP_ROOT" ]; then
    echo "FATAL: mktemp failed" >&2
    exit 1
fi
trap 'rm -rf "$TMP_ROOT"' EXIT

run_guard() { bash "$GUARD" --project-dir "$1" 2>&1; }
field() { printf '%s\n' "$1" | grep -E "^$2=" | head -1 | cut -d= -f2-; }

# write_hooks <tree> <relpath> <timeout-json>
write_hooks() {
    mkdir -p "$1/$(dirname "$2")"
    jq -n --argjson t "$3" \
        '{hooks: {PreToolUse: [{matcher: "Bash", hooks: [{type: "command", command: "true", timeout: $t}]}]}}' > "$1/$2"
}

# expect <label> <tree> <status> [issue-type]
expect() {
    local out status
    out=$(run_guard "$2"); status=$(field "$out" STATUS)
    if [ "$status" != "$3" ]; then
        fail "$1 (STATUS=$status, want $3)"
        return
    fi
    if [ -n "${4:-}" ] && ! grep -q "TYPE=$4 " <<<"$out"; then
        fail "$1 (no TYPE=$4 in output)"
        return
    fi
    if [ "$3" != "OK" ] && [ -z "$(field "$out" REASON)" ]; then
        fail "$1 (non-OK result has no REASON=)"
        return
    fi
    pass "$1"
}

tree() { mktemp -d "$TMP_ROOT/t.XXXXXX"; }

T=$(tree); write_hooks "$T" "x-plugin/hooks.json" 5000
expect "5000 in hooks.json is flagged" "$T" ERROR ms_timeout

T=$(tree); write_hooks "$T" "x-plugin/hooks/hooks.json" 60000
expect "60000 in hooks/hooks.json is flagged" "$T" ERROR ms_timeout

T=$(tree); mkdir -p "$T/x-plugin/.claude-plugin"
jq -n '{name: "x", hooks: {SessionStart: [{hooks: [{type: "command", command: "true", timeout: 15000}]}]}}' \
    > "$T/x-plugin/.claude-plugin/plugin.json"
expect "15000 in inline plugin.json hooks is flagged" "$T" ERROR ms_timeout

T=$(tree); write_hooks "$T" "x-plugin/hooks.json" 1000
expect "1000 (the threshold) is flagged" "$T" ERROR ms_timeout

T=$(tree); write_hooks "$T" "x-plugin/hooks.json" 5
write_hooks "$T" "y-plugin/hooks.json" 15
write_hooks "$T" "z-plugin/hooks.json" 600
expect "second-scale timeouts pass" "$T" OK

T=$(tree); mkdir -p "$T/x-plugin"
jq -n '{hooks: {PreToolUse: [{matcher: "Bash", hooks: [{type: "command", command: "true"}]}]}}' > "$T/x-plugin/hooks.json"
expect "an entry with no timeout passes" "$T" OK

T=$(tree)
expect "an empty tree is an error, not a silent OK" "$T" ERROR nothing_scanned

expect "the live repository passes" "$REPO_ROOT" OK

echo
echo "PASSED=$PASS FAILED=$FAIL"
[ "$FAIL" -eq 0 ]
