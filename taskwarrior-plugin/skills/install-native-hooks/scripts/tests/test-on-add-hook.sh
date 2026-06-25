#!/usr/bin/env bash
# test-on-add-hook.sh — regression tests for the on-add native hook template's
# `ghid` auto-link behaviour (issue #1809) plus its inherited invariants.
#
# The hook receives ONE line of task JSON on stdin and must echo the task JSON
# back as the first line of stdout. These tests pin:
#   1. trailing `#N` in description     → ghid:N set
#   2. no `#N`                          → ghid stays unset
#   3. ghid already set                 → untouched (no clobber)
#   4. project auto-stamp still works   → no regression on the inherited step
#   5. fails open on bad JSON           → echoes stdin unchanged, exits 0
#   6. no network calls in the template → pure text extraction (gh/curl absent)
#
# The hook is run directly as the script it is installed as — no taskwarrior
# needed; only `jq` (which the hook itself requires).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/../../templates/on-add-taskwarrior-plugin"

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

if ! command -v jq >/dev/null 2>&1; then
    echo "SKIP: jq not available" >&2
    exit 0
fi
[ -f "$HOOK" ] || { echo "FAIL: hook template not found at $HOOK" >&2; exit 1; }

# Run the hook with one JSON line on stdin; return the echoed task (first line).
run_hook() { # run_hook <json>
    printf '%s\n' "$1" | bash "$HOOK" 2>/dev/null | head -n 1
}

# 1. Trailing #N → ghid:N (project set so the stamp step is inert here).
out=$(run_hook '{"description":"fix the drift cache #1417","project":"x"}')
check "trailing #N sets ghid" "1417" "$(printf '%s' "$out" | jq -r '.ghid // "unset"')"

# 2. No #N → ghid stays unset.
out=$(run_hook '{"description":"plain task no reference","project":"x"}')
check "no #N leaves ghid unset" "unset" "$(printf '%s' "$out" | jq -r '.ghid // "unset"')"

# 3. ghid already set → not clobbered by a different trailing #N.
out=$(run_hook '{"description":"already linked #999","project":"x","ghid":42}')
check "existing ghid untouched" "42" "$(printf '%s' "$out" | jq -r '.ghid // "unset"')"

# 4. Project auto-stamp regression: no project → stamped to cwd basename, and a
#    trailing #N is still linked in the same pass.
expected_proj="$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")"
out=$(run_hook '{"description":"unscoped add #88"}')
check "project still auto-stamped" "$expected_proj" "$(printf '%s' "$out" | jq -r '.project // "unset"')"
check "ghid linked alongside stamp" "88" "$(printf '%s' "$out" | jq -r '.ghid // "unset"')"

# 5. Fail open: malformed JSON is echoed back unchanged, hook exits 0.
bad='{not valid json #5'
out=$(printf '%s\n' "$bad" | bash "$HOOK" 2>/dev/null; echo "exit:$?")
check "bad JSON echoed unchanged" "$bad" "$(printf '%s' "$out" | head -n 1)"
check "bad JSON exits 0" "exit:0" "$(printf '%s' "$out" | tail -n 1)"

# 6. No network in the template (semantic invariant: validation is the skill's job).
if grep -Eq '(^|[^_[:alnum:]])(gh|curl|wget)([^_[:alnum:]]|$)' "$HOOK"; then
    check "template makes no network calls" "absent" "present"
else
    check "template makes no network calls" "absent" "absent"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
