#!/usr/bin/env bash
# shellcheck disable=SC2015   # file-level: `cond && ok … || notok …` is the
# deliberate assertion idiom across this repo's test scripts (ok/notok both
# exit 0, so the || branch only runs on a real failure). Must sit before the
# first command — see .claude/rules/shell-scripting.md.
#
# Regression tests for check-schema.py and the three validate-*-frontmatter.sh
# hooks it backs — the schema/hook reconciliation.
#
# Auto-discovered by scripts/run-skill-script-tests.sh via
# *-plugin/scripts/tests/test-*.sh.
#
# THE THREE DEFECTS THIS PINS (each one shipped, each one silent):
#
#   1. The schema spelled the back-reference `superseded_by`; the hook read
#      `superseded-by`. The "Superseded needs a replacement" check therefore
#      NEVER FIRED — docs/adrs/0014 sits Superseded with no back-link to this
#      day. A test asserting only "the hook exits 2 on a bad ADR" would have
#      passed throughout, so the assertion here is that the specific WARN is
#      RAISED on the hyphen spelling and that the underscore spelling is
#      called out rather than silently ignored.
#
#   2. All three hooks read `.tool_input.content`, which Edit does not carry
#      (it sends old_string/new_string). Every Edit to a PRD/ADR/PRP therefore
#      skipped validation ENTIRELY while exiting 0 — indistinguishable from a
#      clean document. Pinned by feeding a real Edit payload that introduces a
#      violation and requiring exit 2.
#
#   3. Not one ADR in this repo had frontmatter at line 1 (every block sat
#      below the H1), so no standard YAML parser could read them. Pinned by
#      requiring the body-position form to be REJECTED.
#
# SEMANTIC, NOT SYNTACTIC (.claude/rules/regression-testing.md): the schema is
# now the only description of these documents, so the assertions execute the
# validator and read its verdicts. A grep for a field name in the schema would
# pass against a schema nothing consumes — which is precisely the state before
# this change, when adr.schema.json was referenced by nothing at all.
set -u

# Neutralize inherited git context (issue #1745).
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR GIT_NAMESPACE GIT_PREFIX

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CHECKER="${PLUGIN_DIR}/scripts/check-schema.py"
SCHEMA_DIR="${PLUGIN_DIR}/schemas"
HOOK_DIR="${PLUGIN_DIR}/hooks"

pass=0
fail=0
ok()    { pass=$((pass + 1)); printf 'ok   - %s\n' "$1"; }
notok() { fail=$((fail + 1)); printf 'FAIL - %s\n' "$1"; }

if ! command -v uv >/dev/null 2>&1; then
    printf 'SKIP - uv unavailable; check-schema.py needs it (or installed jsonschema + PyYAML)\n'
    exit 0
fi

WORK="$(mktemp -d)" || { echo "FATAL: mktemp failed" >&2; exit 1; }
[ -n "$WORK" ] && [ -d "$WORK" ] || { echo "FATAL: bad mktemp dir" >&2; exit 1; }
trap 'rm -rf "$WORK"' EXIT

run() { # <kind> <file>
    uv run --quiet --script "$CHECKER" --kind "$1" --file "$2" 2>&1
}

has_issue() { # <output> <substring>
    printf '%s\n' "$1" | grep -q -- "$2"
}

severity_of() { # <output> <substring> -> the SEVERITY= token on the matching row
    printf '%s\n' "$1" | grep -F -- "$2" | sed -n 's/.*SEVERITY=\([A-Z]*\).*/\1/p' | head -1
}

# --- fixtures -------------------------------------------------------------
good_adr() { # <path> [status line]
    cat > "$1" <<EOF
---
id: ADR-0099
created: 2026-01-01
modified: 2026-02-02
status: ${2:-Accepted}
deciders: team
domain: architecture
---

# ADR-0099: Title

## Context
c
## Decision
d
## Consequences
q
## Options Considered
o
## Related ADRs
r
EOF
}

# ==========================================================================
# Guard integrity — a conforming document must PASS. Without this every
# "rejected" assertion below could hold against a validator that rejects
# everything, and the suite would be worthless.
# ==========================================================================
good_adr "$WORK/good.md"
out="$(run adr "$WORK/good.md")"
has_issue "$out" "STATUS=OK" \
    && ok "guard integrity: a conforming ADR validates clean" \
    || notok "guard integrity: a conforming ADR validates clean -- got: $out"

has_issue "$out" "SCHEMA_APPLICABLE=true" \
    && ok "guard integrity: the schema was actually applied (not skipped)" \
    || notok "guard integrity: the schema was actually applied -- got: $out"

# ==========================================================================
# DEFECT 1 — the supersession check that never fired
# ==========================================================================
good_adr "$WORK/sup.md" "Superseded"
out="$(run adr "$WORK/sup.md")"
has_issue "$out" "superseded-by" \
    && ok "defect 1: Superseded without a back-reference is reported" \
    || notok "defect 1: Superseded without a back-reference is reported -- got: $out"

[ "$(severity_of "$out" "superseded-by")" = "WARN" ] \
    && ok "defect 1: the missing back-reference WARNs, never blocks" \
    || notok "defect 1: expected SEVERITY=WARN on the back-reference finding"

# The hyphen spelling is the one that satisfies it. If a future edit flipped
# the schema back to the underscore, this document would still be reported.
sed -e 's/^deciders: team/superseded-by: ADR-0100/' "$WORK/sup.md" > "$WORK/sup-ok.md"
out="$(run adr "$WORK/sup-ok.md")"
has_issue "$out" "superseded-by" \
    && notok "defect 1: hyphen superseded-by should satisfy the requirement" \
    || ok "defect 1: hyphen superseded-by satisfies the requirement"

# The underscore spelling must NOT satisfy it, and must say so — silently
# ignoring it is exactly how the original bug stayed invisible.
sed -e 's/^deciders: team/superseded_by: ADR-0100/' "$WORK/sup.md" > "$WORK/sup-us.md"
out="$(run adr "$WORK/sup-us.md")"
has_issue "$out" "superseded_by" \
    && ok "defect 1: the underscore spelling is called out, not ignored" \
    || notok "defect 1: the underscore spelling is called out -- got: $out"

has_issue "$out" "superseded-by" \
    && ok "defect 1: the underscore spelling does not satisfy the requirement" \
    || notok "defect 1: underscore wrongly satisfied the back-reference requirement"

# ==========================================================================
# DEFECT 2 — Edit was never validated
# ==========================================================================
good_adr "$WORK/edit.md"
payload="$(jq -n --arg f "$WORK/edit.md" \
    '{tool_name:"Edit",tool_input:{file_path:$f,old_string:"status: Accepted",new_string:"status: Bogus"}}')"
edit_rc=0
printf '%s' "$payload" | bash "${HOOK_DIR}/validate-adr-frontmatter.sh" >/dev/null 2>&1 || edit_rc=$?
[ "$edit_rc" -eq 2 ] \
    && ok "defect 2: an Edit introducing a violation is blocked (exit 2)" \
    || notok "defect 2: an Edit introducing a violation must exit 2 -- got $edit_rc"

# ...and an Edit that keeps the document valid must not block.
payload="$(jq -n --arg f "$WORK/edit.md" \
    '{tool_name:"Edit",tool_input:{file_path:$f,old_string:"status: Accepted",new_string:"status: Proposed"}}')"
edit_rc=0
printf '%s' "$payload" | bash "${HOOK_DIR}/validate-adr-frontmatter.sh" >/dev/null 2>&1 || edit_rc=$?
[ "$edit_rc" -eq 0 ] \
    && ok "defect 2: a benign Edit still passes" \
    || notok "defect 2: a benign Edit must exit 0 -- got $edit_rc"

# An Edit whose old_string is absent cannot be reconstructed -> fail open.
payload="$(jq -n --arg f "$WORK/edit.md" \
    '{tool_name:"Edit",tool_input:{file_path:$f,old_string:"nowhere-in-this-file",new_string:"x"}}')"
edit_rc=0
printf '%s' "$payload" | bash "${HOOK_DIR}/validate-adr-frontmatter.sh" >/dev/null 2>&1 || edit_rc=$?
[ "$edit_rc" -eq 0 ] \
    && ok "defect 2: an unreconstructable Edit fails open" \
    || notok "defect 2: an unreconstructable Edit must fail open -- got $edit_rc"

# ==========================================================================
# DEFECT 3 — frontmatter below the H1 is not frontmatter
# ==========================================================================
{
    printf '# ADR-0099: Title\n\n'
    cat "$WORK/good.md"
} > "$WORK/below.md"
out="$(run adr "$WORK/below.md")"
has_issue "$out" "frontmatter_missing" \
    && ok "defect 3: a metadata block below the H1 is rejected" \
    || notok "defect 3: a block below the H1 must be rejected -- got: $out"

# ==========================================================================
# Severity lives in the schema, not the hook
# ==========================================================================
sed '/^## Related ADRs$/,+1d' "$WORK/good.md" > "$WORK/nosection.md"
out="$(run adr "$WORK/nosection.md")"
[ "$(severity_of "$out" "/sections")" = "WARN" ] \
    && ok "severity: a missing required section WARNs (hook-block-vs-nudge)" \
    || notok "severity: a missing section must WARN -- got: $out"

sed 's/^status: Accepted/status: Bogus/' "$WORK/good.md" > "$WORK/badstatus.md"
out="$(run adr "$WORK/badstatus.md")"
[ "$(severity_of "$out" "/frontmatter/status")" = "ERROR" ] \
    && ok "severity: an out-of-enum status is an ERROR" \
    || notok "severity: an out-of-enum status must ERROR -- got: $out"

# ==========================================================================
# The hooks declare no field list — the whole point of the reconciliation.
# A regrown enum / id regex / required-field list here is the regression.
# ==========================================================================
for kind in adr prd prp; do
    hook="${HOOK_DIR}/validate-${kind}-frontmatter.sh"
    if grep -Eq 'check_required_field|Valid values:|\^(ADR|PRD|PRP)-\[0-9\]' "$hook"; then
        notok "no field lists: ${kind} hook regrew a field list"
    else
        ok "no field lists: ${kind} hook declares none"
    fi
done

grep -q 'check-schema.py' "${HOOK_DIR}/validate-frontmatter.sh" \
    && ok "no field lists: the shared hook delegates to the validator" \
    || notok "no field lists: the shared hook must call check-schema.py"

# ==========================================================================
# Schemas agree with each other on the shared cross-reference patterns.
# They are separate files by design, so nothing but a check keeps them equal.
# ==========================================================================
relates_patterns="$(for s in adr prd prp; do
    jq -r '.properties.frontmatter.properties["relates-to"].items.pattern' "${SCHEMA_DIR}/${s}.schema.json"
done | sort -u | wc -l | tr -d ' ')"
[ "$relates_patterns" = "1" ] \
    && ok "schema parity: relates-to uses one pattern across all three" \
    || notok "schema parity: relates-to patterns diverged across schemas"

for s in adr prd prp; do
    jq -e '.properties.sections and .properties.frontmatter' "${SCHEMA_DIR}/${s}.schema.json" >/dev/null 2>&1 \
        && ok "schema parity: ${s} projects both frontmatter and sections" \
        || notok "schema parity: ${s} must declare frontmatter and sections"
done

# ==========================================================================
# Degradation contract — a diagnostic must stay quiet rather than wrong.
# ==========================================================================
out="$(uv run --quiet --script "$CHECKER" --schema "${SCHEMA_DIR}/feature-tracker.schema.json" --json-file "$WORK/absent.json" 2>&1)"
has_issue "$out" "STATUS=OK" \
    && ok "degradation: a missing JSON document is OK, not an error" \
    || notok "degradation: a missing JSON document must be OK -- got: $out"

clean_rc=0
uv run --quiet --script "$CHECKER" --kind adr --file "$WORK/good.md" >/dev/null 2>&1 || clean_rc=$?
[ "$clean_rc" -eq 0 ] && ok "degradation: clean run exits 0 (parallel-safe)" \
                      || notok "degradation: clean run must exit 0 -- got $clean_rc"

printf '\nPASSED=%d FAILED=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
