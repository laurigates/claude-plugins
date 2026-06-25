#!/usr/bin/env bash
# test-uuid-capture.sh — semantic regression test for the task-add skill's
# "capture the stable UUID after add" ergonomic (issue #1417).
#
# The #1417 fix originally documented `task +LATEST _get uuid`, but `_get` is a
# DOM accessor that takes `<id>.<attribute>` references — NOT a `<filter> _get
# <attribute>` form. Given a tag filter it silently returns EMPTY (exit 0), so
# the skill captured no UUID and quietly reverted to the very numeric-ID drift
# #1417 was meant to fix. The compliance-check guard pinned the literal string
# but never verified the command worked — a syntactic-only gate (see
# `.claude/rules/regression-testing.md` § syntactic vs semantic).
#
# This test closes that gap by EXECUTING the commands against a scratch store:
#   1. the broken `_get uuid` filter form returns empty (documents the failure)
#   2. the working `+LATEST uuids` form returns a valid UUID
#   3. the SKILL.md actually uses the working form, not the broken one
#
# Requires the real `task` CLI; SKIPs cleanly when taskwarrior is unavailable.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_FILE="${SCRIPT_DIR}/../../SKILL.md"

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

if ! command -v task >/dev/null 2>&1; then
    echo "SKIP: task CLI not available" >&2
    exit 0
fi

UUID_RE='^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'

# Isolated scratch store — never touches the user's real taskwarrior data.
SCRATCH="$(mktemp -d)"
[ -n "$SCRATCH" ] || { echo "mktemp failed" >&2; exit 1; }
trap 'rm -rf "$SCRATCH"' EXIT
export TASKDATA="$SCRATCH" TASKRC="${SCRATCH}/.taskrc"
printf 'data.location=%s\n' "$SCRATCH" > "$TASKRC"

task rc.confirmation=no add "first scratch task" </dev/null >/dev/null 2>&1
task rc.confirmation=no add "second scratch task" </dev/null >/dev/null 2>&1

# 1. The broken form (`_get` + tag filter) returns empty — this is WHY we changed it.
broken=$(task +LATEST _get uuid 2>/dev/null)
check "broken '_get uuid' filter form returns empty" "empty" "${broken:-empty}"

# 2. The working form returns a valid UUID for the most-recently-added task.
captured=$(task +LATEST uuids 2>/dev/null)
if [[ "$captured" =~ $UUID_RE ]]; then
    check "working '+LATEST uuids' returns a UUID" "uuid" "uuid"
else
    check "working '+LATEST uuids' returns a UUID" "uuid" "got:'${captured}'"
fi

# 3. The SKILL.md must use the working form and must NOT ship the broken one.
if grep -q 'task +LATEST uuids' "$SKILL_FILE"; then
    check "SKILL.md uses working '+LATEST uuids'" "present" "present"
else
    check "SKILL.md uses working '+LATEST uuids'" "present" "absent"
fi
# Blockquote lines (gotcha callouts) may cite the broken form; non-quoted
# lines (the actual recommended command) must not — matches the repo's
# hyphenated-tag / mcp-tool lint convention.
if grep -v '^[[:space:]]*>' "$SKILL_FILE" | grep -q 'task +LATEST _get uuid'; then
    check "SKILL.md drops broken '_get uuid' outside callouts" "absent" "present"
else
    check "SKILL.md drops broken '_get uuid' outside callouts" "absent" "absent"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
