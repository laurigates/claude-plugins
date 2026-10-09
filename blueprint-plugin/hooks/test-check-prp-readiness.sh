#!/usr/bin/env bash
# Regression tests for check-prp-readiness.sh, ported from the dormant
# spec/check_prp_readiness_spec.sh (ShellSpec never ran in CI — see
# docs/hook-design-decisions.md). Auto-discovered via */hooks/test-*.sh.
#
# Pins the skill filter that the hooks.json move made necessary: the hook is
# registered on the bare "Skill" matcher (a matcher sees only the tool name,
# and the former "Skill(prp-execute)" never fired), so it now sees every skill
# call and must gate prp-execute alone.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/check-prp-readiness.sh"

pass=0
fail=0
ok() { pass=$((pass + 1)); printf 'ok   - %s\n' "$1"; }
notok() { fail=$((fail + 1)); printf 'FAIL - %s\n' "$1"; }

PROJ=$(mktemp -d)
if [ -z "$PROJ" ] || [ ! -d "$PROJ" ]; then
    echo "FATAL: mktemp failed" >&2
    exit 1
fi
trap 'rm -rf "$PROJ"' EXIT
mkdir -p "$PROJ/docs/prps"

write_prp() {
    # write_prp <name> <confidence>
    cat > "$PROJ/docs/prps/$1.md" <<EOF
---
created: 2025-01-20
modified: 2025-01-20
reviewed: 2025-01-20
status: ready
confidence: $2/10
domain: auth
feature-codes:
  - FR1.1
related: []
---

# PRP

## Context Framing

Context.

## AI Documentation

Docs.

## Implementation Blueprint

Steps.

## Test Strategy

Tests.

## Validation Gates

Gates.

## Success Criteria

Criteria.
EOF
}

# check <label> <want-exit> <want-stderr|""> <skill> <args|""> [env...]
# A block is asserted by its message, not only its exit code
# (scripts/check-hook-message-pins.sh, #2715).
check() {
    local label="$1" want="$2" msg="$3" skill="$4" args="$5" payload out rc
    shift 5
    if [ -n "$args" ]; then
        payload=$(jq -nc --arg s "$skill" --arg a "$args" '{tool_name: "Skill", tool_input: {skill: $s, args: $a}}')
    else
        payload=$(jq -nc --arg s "$skill" '{tool_name: "Skill", tool_input: {skill: $s}}')
    fi
    out=$(cd "$PROJ" && printf '%s' "$payload" | env "$@" bash "$HOOK" 2>&1 >/dev/null)
    rc=$?
    if [ "$rc" -ne "$want" ]; then
        notok "$label (exit $rc, want $want)"
    elif [ -n "$msg" ] && ! printf '%s\n' "$out" | grep -qF -- "$msg"; then
        notok "$label (stderr lacks '$msg': $out)"
    else
        ok "$label"
    fi
}

write_prp ready 8
write_prp low-conf 5

check "a ready PRP passes" 0 "INFO: PRP readiness check passed" blueprint-plugin:blueprint-prp-execute ready
check "a PRP below confidence 7 is blocked" 2 "ERROR: Confidence score" blueprint-plugin:blueprint-prp-execute low-conf
check "a missing PRP is blocked" 2 "ERROR: PRP file not found" blueprint-plugin:blueprint-prp-execute nonexistent
check "the short prp-execute alias is gated too" 2 "ERROR: PRP file not found" prp-execute nonexistent
check "another skill whose args name a missing PRP passes untouched" 0 "" blueprint-plugin:blueprint-status nonexistent
check "no args lets the skill report the error" 0 "" blueprint-plugin:blueprint-prp-execute ""
check "BLUEPRINT_SKIP_HOOKS=1 bypasses the gate" 0 "" blueprint-plugin:blueprint-prp-execute nonexistent BLUEPRINT_SKIP_HOOKS=1

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
