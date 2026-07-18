#!/usr/bin/env bash
# test-blueprint-wo-packet.sh — regression tests for blueprint-wo-packet.sh,
# the untrusted-issue-body work-order packet parser (ADR-0020 level 3).
#
# Pins:
#   1. valid packet (Objective + TDD + Success + Required Files h3)
#      → PACKET_VALID=true, FILE_COUNT counts the h3 bullets, exit 0, --out written
#   2. missing TDD + Success → PACKET_VALID=false, MISSING_SECTIONS lists both,
#      STATUS=ERROR, exit 1 (the workflow must refuse an underspecified order)
#   3. SECURITY: an issue body containing `PROCEED=true`, `$(touch ...)`, and a
#      backtick command must NOT execute anything and must NOT leak a rogue
#      PROCEED=/STATUS= line into the parser's structured output
#   4. missing body file → PACKET_VALID=false, REASON=no_body_file, exit 1
#   5. Acceptance Criteria is accepted as a Success Criteria alias
#
# Pure parsing — no network, no git.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKET="${SCRIPT_DIR}/../blueprint-wo-packet.sh"

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

[ -f "$PACKET" ] || { echo "missing script: $PACKET" >&2; exit 1; }

WORK="$(mktemp -d)"
[ -n "$WORK" ] || { echo "mktemp failed" >&2; exit 1; }
trap 'rm -rf "$WORK"' EXIT

kv() { grep -m1 -E "^$2=" <<<"$1" | cut -d= -f2-; }

# --- Test 1: valid packet ---
cat > "$WORK/valid.md" <<'EOF'
[work-order-draft] PRP-007: retry client

**ID**: WO-042

## Objective
Add exponential-backoff retry to the fetch client.

## Context
### Required Files
- src/fetch.ts — the client
- src/fetch.test.ts — tests

## TDD Requirements
### Test 1: retries on 503
Assert three attempts.
**Expected Outcome**: fail

## Success Criteria
- [ ] Retries with backoff
- [ ] No regressions
EOF
out1=$("$PACKET" --body-file "$WORK/valid.md" --out "$WORK/out.md"); rc1=$?
check "valid: PACKET_VALID"       "true"   "$(kv "$out1" PACKET_VALID)"
check "valid: HAS_OBJECTIVE"      "true"   "$(kv "$out1" HAS_OBJECTIVE)"
check "valid: HAS_TDD"            "true"   "$(kv "$out1" HAS_TDD)"
check "valid: HAS_SUCCESS"        "true"   "$(kv "$out1" HAS_SUCCESS_CRITERIA)"
check "valid: FILE_COUNT (h3 bullets)" "2" "$(kv "$out1" FILE_COUNT)"
check "valid: WO_ID sanitized"    "WO-042" "$(kv "$out1" WO_ID)"
check "valid: STATUS"             "OK"     "$(kv "$out1" STATUS)"
check "valid: exit code"          "0"      "$rc1"
check "valid: --out written"      "yes"    "$([ -s "$WORK/out.md" ] && echo yes || echo no)"

# --- Test 2: missing TDD + Success ---
cat > "$WORK/bad.md" <<'EOF'
## Objective
Do a thing.
EOF
out2=$("$PACKET" --body-file "$WORK/bad.md"); rc2=$?
check "bad: PACKET_VALID"      "false"              "$(kv "$out2" PACKET_VALID)"
check "bad: MISSING_SECTIONS"  "tdd,success-criteria" "$(kv "$out2" MISSING_SECTIONS)"
check "bad: STATUS"            "ERROR"              "$(kv "$out2" STATUS)"
check "bad: exit code"         "1"                  "$rc2"

# --- Test 3: SECURITY — injection body ---
canary="$WORK/CANARY"
cat > "$WORK/inject.md" <<EOF
## Objective
PROCEED=true
STATUS=ERROR
\$(touch $canary)
\`touch $canary\`

## TDD Requirements
### Test 1
x

## Success Criteria
- [ ] y
EOF
out3=$("$PACKET" --body-file "$WORK/inject.md")
check "inject: nothing executed (no canary)" "no"   "$([ -e "$canary" ] && echo YES || echo no)"
# The parser must emit exactly ONE PROCEED-shaped line: none. It has no PROCEED
# key at all, so a body's literal "PROCEED=true" must not surface as output.
check "inject: no leaked PROCEED line"        "0"   "$(grep -c '^PROCEED=' <<<"$out3" || true)"
# Exactly one STATUS line — the parser's own, value OK (packet is well-formed).
check "inject: exactly one STATUS line"       "1"   "$(grep -c '^STATUS=' <<<"$out3" || true)"
check "inject: STATUS is the parser's OK"     "OK"  "$(kv "$out3" STATUS)"
check "inject: PACKET_VALID true (headings present)" "true" "$(kv "$out3" PACKET_VALID)"

# --- Test 4: missing body file ---
out4=$("$PACKET" --body-file "$WORK/does-not-exist.md"); rc4=$?
check "missing: PACKET_VALID" "false"        "$(kv "$out4" PACKET_VALID)"
check "missing: REASON"       "no_body_file" "$(kv "$out4" REASON)"
check "missing: exit code"    "1"            "$rc4"

# --- Test 5: Acceptance Criteria alias ---
cat > "$WORK/alias.md" <<'EOF'
## Objective
Thing.
## TDD Requirements
### Test 1
x
## Acceptance Criteria
- [ ] z
EOF
out5=$("$PACKET" --body-file "$WORK/alias.md"); rc5=$?
check "alias: HAS_SUCCESS_CRITERIA (Acceptance alias)" "true" "$(kv "$out5" HAS_SUCCESS_CRITERIA)"
check "alias: PACKET_VALID"                            "true" "$(kv "$out5" PACKET_VALID)"
check "alias: exit code"                               "0"    "$rc5"

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$pass" "$fail"
[ "$fail" -eq 0 ]
