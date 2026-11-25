#!/usr/bin/env bash
# test-prose-check-email.sh -- regression test for `prose-check.sh --kind email`
# (issue #3740).
#
# Run on a plain-text mailing-list reply, prose-check scored the mail header
# block, the "On <date>, X wrote:" attribution line, the `>`-quoted text and the
# signature as if the author had written them. `--kind email` skips those four
# parts. The fixture lays them out on known lines:
#
#   1-4    header block (line 3 is a folded continuation)
#   6      attribution line
#   7-9    `>`-quoted text
#   11-15  the author's reply body
#   17-19  signature (`-- ` delimiter on line 17)
#
# MSG= text is truncated at 160 characters, so the assertions key on the
# finding's line number, not on its text. `--long-words 8` makes every part of
# the fixture long enough to be flagged, so the doc-mode control proves each
# skipped part WOULD produce a finding; an email-mode finding outside the body
# range then means that part leaked through.
#
# The positional-tics layer needs uv; without it the test SKIPs.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
CHECK="$SKILL_DIR/scripts/prose-check.sh"
FIXTURE="$SKILL_DIR/fixtures/email-reply-draft.txt"
BODY_FIRST=11
BODY_LAST=15

if ! command -v uv >/dev/null 2>&1; then
    echo "SKIP: uv not on PATH; positional-tics layer cannot run"
    exit 0
fi

pass=0
fail=0
ok() { pass=$((pass + 1)); echo "PASS: $1"; }
ko() { fail=$((fail + 1)); echo "FAIL: $1"; }

# finding_lines OUTPUT -- the line numbers of the positional-tics findings.
finding_lines() {
    grep -E '^  - SEVERITY=CANDIDATE TYPE=' <<<"$1" \
        | sed -n "s|.*FILE=$FIXTURE:\([0-9]*\) .*|\1|p" | sort -n | uniq
}

email_low="$(bash "$CHECK" --kind email --long-words 8 "$FIXTURE")"
doc_low="$(bash "$CHECK" --kind doc --long-words 8 "$FIXTURE")"
email_default="$(bash "$CHECK" --kind email "$FIXTURE")"

email_lines="$(finding_lines "$email_low")"
doc_lines="$(finding_lines "$doc_low")"

# Fixture integrity: the signature delimiter is "-- " WITH its trailing space.
# Editors and .editorconfig (trim_trailing_whitespace) strip it silently, which
# turns line 17 into plain prose and fails the leak check for the wrong reason.
if [ "$(sed -n 17p "$FIXTURE")" = "-- " ]; then
    ok "fixture: line 17 is the '-- ' signature delimiter (trailing space intact)"
else
    ko "fixture: line 17 lost its '-- ' delimiter; restore the trailing space"
fi

# Control: doc mode flags every part email mode must skip.
for want in 1 6 17; do
    if grep -qx "$want" <<<"$doc_lines"; then
        ok "control: doc mode flags line $want"
    else
        ko "control: doc mode does not flag line $want (fixture no longer exercises it); got: $(tr '\n' ' ' <<<"$doc_lines")"
    fi
done

# 1. Email mode: every finding lies in the reply body.
if [ -z "$email_lines" ]; then
    ko "email mode produced no findings at all"
else
    leaked=""
    while IFS= read -r ln; do
        if [ "$ln" -lt "$BODY_FIRST" ] || [ "$ln" -gt "$BODY_LAST" ]; then
            leaked="$leaked $ln"
        fi
    done <<<"$email_lines"
    if [ -z "$leaked" ]; then
        ok "email mode reports nothing from the header, attribution, quote or signature"
    else
        ko "email mode reports findings outside the body, at line(s):$leaked"
    fi
fi

# 2. The body is still scored at the default threshold.
if grep -E 'TYPE=long_sentence' <<<"$email_default" | grep -qF bodyzebra; then
    ok "email mode still reports the long body sentence"
else
    ko "email mode lost the long_sentence finding in the reply body"
fi

# 3. Findings name the draft, not a temp copy.
if grep -qF "FILE=$FIXTURE:" <<<"$email_default" && ! grep -q 'prose-check-email\.' <<<"$email_default"; then
    ok "findings name the original file"
else
    ko "findings do not name the original file path"
fi

if grep -q '^KIND=email$' <<<"$email_default"; then
    ok "rollup reports KIND=email"
else
    ko "rollup does not report KIND=email"
fi

echo "PASSED=$pass FAILED=$fail"
[ "$fail" -eq 0 ]
