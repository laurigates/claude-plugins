#!/usr/bin/env bash
# Regression test for scripts/check-hook-matchers.sh.
#
# Pins: permission-rule syntax in a tool-event matcher is an ERROR (the
# blueprint-plugin `Write(docs/adrs/**)` matchers that never fired); exact names,
# name lists and compiling regexes pass; a regex that cannot compile is an
# ERROR; non-tool events (SessionStart "startup", PreCompact "auto") are not
# judged as tool names; inline plugin.json hooks are scanned; an empty tree is
# STATUS=ERROR, never a silent OK; and the live repository passes.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GUARD="$REPO_ROOT/scripts/check-hook-matchers.sh"

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

# write_hooks <tree> <relpath> <event> <matcher>
write_hooks() {
    mkdir -p "$1/$(dirname "$2")"
    jq -n --arg e "$3" --arg m "$4" \
        '{hooks: {($e): [{matcher: $m, hooks: [{type: "command", command: "true"}]}]}}' > "$1/$2"
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
    pass "$1"
}

# A fresh directory per case. (A counter incremented inside $(…) would run in a
# subshell and hand every case the same tree.)
tree() { mktemp -d "$TMP_ROOT/t.XXXXXX"; }

T=$(tree); write_hooks "$T" "x-plugin/hooks.json" PostToolUse 'Write(docs/adrs/**)'
expect "permission-rule matcher with a path is flagged" "$T" ERROR permission_rule_matcher

T=$(tree); write_hooks "$T" "x-plugin/hooks.json" PreToolUse 'Skill(prp-execute)'
expect "permission-rule matcher that compiles as a regex is still flagged" "$T" ERROR permission_rule_matcher

T=$(tree); write_hooks "$T" "x-plugin/hooks/hooks.json" PostToolUse 'Write|Edit|Bash'
expect "exact tool-name list passes" "$T" OK

T=$(tree); write_hooks "$T" "x-plugin/hooks.json" PreToolUse 'mcp__memory__.*'
expect "compiling regex matcher passes" "$T" OK

T=$(tree); write_hooks "$T" "x-plugin/hooks.json" PreToolUse 'Bash|(Edit'
expect "regex matcher that does not compile is flagged" "$T" ERROR invalid_regex_matcher

T=$(tree); write_hooks "$T" "x-plugin/hooks.json" SessionStart 'startup'
write_hooks "$T" "y-plugin/hooks.json" PreCompact 'auto'
expect "non-tool events are not judged as tool names" "$T" OK

T=$(tree); mkdir -p "$T/x-plugin/.claude-plugin"
jq -n '{name: "x", hooks: {PreToolUse: [{matcher: "Edit(src/**)", hooks: [{type: "command", command: "true"}]}]}}' \
    > "$T/x-plugin/.claude-plugin/plugin.json"
expect "inline plugin.json hooks are scanned" "$T" ERROR permission_rule_matcher

T=$(tree)
expect "an empty tree is an error, not a silent OK" "$T" ERROR nothing_scanned

expect "the live repository passes" "$REPO_ROOT" OK

echo
echo "PASSED=$PASS FAILED=$FAIL"
[ "$FAIL" -eq 0 ]
