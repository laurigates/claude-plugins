#!/usr/bin/env bash
# Regression tests for register-generated-rules.sh — the shared writer both
# /blueprint:init Step 8a and /blueprint:generate-rules Step 5 invoke (#2331).
#
# Auto-discovered by scripts/run-skill-script-tests.sh via
# *-plugin/scripts/tests/test-*.sh.
#
# SEMANTIC, not syntactic: every case EXECUTES the script against a real
# sandbox manifest and asserts on what actually lands in the JSON. The defect
# this guards is a missing or malformed WRITE, and a grep for some literal inside
# the script would pass against a writer that produced the wrong shape — the
# #1417 -> #1819 lesson.
#
# The invariants pinned here are the ones every consumer depends on:
#   - generated.rules is an OBJECT map (to_entries[] finds the record)
#   - keys are BARE FILENAMES relative to generated_rules_path, WITH `.md`
#   - "$RULES_DIR/$key" resolves to a real file — appending `.md` does not
#   - content_hash is BARE lowercase hex sha256 (no `sha256:` prefix)
set -u

# Neutralize inherited git context so a sandbox op can never reach the shared
# checkout (issue #1745).
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR GIT_NAMESPACE GIT_PREFIX

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${SCRIPT_DIR}/../register-generated-rules.sh"

if ! command -v jq >/dev/null 2>&1; then
    echo "SKIP: jq not available"
    exit 0
fi

pass=0
fail=0
ok()    { pass=$((pass + 1)); printf 'ok   - %s\n' "$1"; }
notok() { fail=$((fail + 1)); printf 'FAIL - %s\n' "$1"; }

assert_eq() { # <label> <expected> <actual>
    if [ "$2" = "$3" ]; then ok "$1"; else notok "$1 (expected '$2', got '$3')"; fi
}
assert_contains() { # <label> <needle> <haystack>
    case "$3" in *"$2"*) ok "$1" ;; *) notok "$1 (missing '$2')" ;; esac
}
assert_not_contains() { # <label> <needle> <haystack>
    case "$3" in *"$2"*) notok "$1 (unexpectedly found '$2')" ;; *) ok "$1" ;; esac
}

sha_of() { # <file>
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

# Build a sandbox project. $1 = generated_rules_path (empty => omit the field).
make_project() { # <rules_path_or_empty>
    local p_dir
    p_dir="$(mktemp -d)" || { echo "FATAL: mktemp failed" >&2; exit 1; }
    [ -n "$p_dir" ] || { echo "FATAL: empty mktemp dir" >&2; exit 1; }
    [ -d "$p_dir" ] || { echo "FATAL: mktemp dir missing" >&2; exit 1; }
    mkdir -p "$p_dir/docs/blueprint"
    if [ -n "$1" ]; then
        printf '{"format_version":"3.4.0","structure":{"generated_rules_path":"%s"}}\n' "$1" \
            >"$p_dir/docs/blueprint/manifest.json"
        mkdir -p "$p_dir/${1%/}"
    else
        printf '{"format_version":"3.4.0","structure":{}}\n' >"$p_dir/docs/blueprint/manifest.json"
        mkdir -p "$p_dir/.claude/rules"
    fi
    printf '%s' "$p_dir"
}

manifest_of() { printf '%s/docs/blueprint/manifest.json' "$1"; }

# ── CASE 1: object map, key form, hash form, non-default rules dir ────────────
proj="$(make_project '.claude/rules/blueprint/')"
printf 'TDD workflow\n'   >"$proj/.claude/rules/blueprint/development.md"
printf 'coverage rules\n' >"$proj/.claude/rules/blueprint/testing.md"

out="$(bash "$SCRIPT" --project-dir "$proj" --source blueprint-init --plugin-version 3.4.0 \
        development.md testing.md 2>&1)"
rc=$?
assert_eq "case1: exits 0 on a clean registration" "0" "$rc"
assert_contains "case1: reports the resolved non-default RULES_DIR" \
    "RULES_DIR=.claude/rules/blueprint" "$out"
assert_contains "case1: REGISTERED counts both rules" "REGISTERED=2" "$out"
assert_contains "case1: STATUS=OK" "STATUS=OK" "$out"

man="$(manifest_of "$proj")"

# generated.rules must be an OBJECT — the shape manifest.schema.json defines and
# the shape blueprint-sync / blueprint-drift-probe.sh iterate with to_entries[].
assert_eq "case1: generated.rules is an object, not an array" \
    "object" "$(jq -r '.generated.rules | type' "$man")"

# The consumer-side read, executed verbatim.
keys="$(jq -r '(.generated.rules // {}) | to_entries[] | .key' "$man" | sort | tr '\n' ' ')"
assert_eq "case1: to_entries[] yields the .md-suffixed bare filenames" \
    "development.md testing.md " "$keys"

expected_hash="$(sha_of "$proj/.claude/rules/blueprint/development.md")"
actual_hash="$(jq -r '.generated.rules["development.md"].content_hash' "$man")"
assert_eq "case1: content_hash is the file's sha256" "$expected_hash" "$actual_hash"
assert_not_contains "case1: content_hash carries no sha256: prefix" "sha256:" "$actual_hash"
assert_eq "case1: status is current" "current" \
    "$(jq -r '.generated.rules["development.md"].status' "$man")"
assert_eq "case1: source is recorded" "blueprint-init" \
    "$(jq -r '.generated.rules["development.md"].source' "$man")"
assert_eq "case1: plugin_version is recorded" "3.4.0" \
    "$(jq -r '.generated.rules["development.md"].plugin_version' "$man")"
assert_eq "case1: no source_hash when none supplied" "null" \
    "$(jq -r '.generated.rules["development.md"].source_hash // "null"' "$man")"

# ── CASE 2: the round trip a consumer performs — "$RULES_DIR/$key" ────────────
# This is the double-suffix bug, expressed as behaviour rather than as a string
# match: resolving key AS-IS finds the file; appending `.md` does not.
rules_dir="$(jq -r '.structure.generated_rules_path' "$man")"
rules_dir="${rules_dir%/}"
key="$(jq -r '(.generated.rules // {}) | to_entries[0].key' "$man")"
if [ -f "$proj/$rules_dir/$key" ]; then
    ok "case2: \"\$RULES_DIR/\$key\" resolves to a real file"
else
    notok "case2: \"\$RULES_DIR/\$key\" did not resolve ($rules_dir/$key)"
fi
if [ -f "$proj/$rules_dir/$key.md" ]; then
    notok "case2: the double-suffixed path unexpectedly exists"
else
    ok "case2: \"\$RULES_DIR/\$key.md\" does NOT exist (double-suffix is a dead path)"
fi

# ── CASE 3: idempotent re-registration picks up an edit ──────────────────────
printf 'TDD workflow, revised\n' >"$proj/.claude/rules/blueprint/development.md"
out="$(bash "$SCRIPT" --project-dir "$proj" --source blueprint-init development.md 2>&1)"
new_hash="$(jq -r '.generated.rules["development.md"].content_hash' "$man")"
assert_eq "case3: re-running updates content_hash to the new content" \
    "$(sha_of "$proj/.claude/rules/blueprint/development.md")" "$new_hash"
assert_eq "case3: the sibling record is untouched" "1" \
    "$(jq -r '[.generated.rules["testing.md"]] | length' "$man")"
assert_eq "case3: no duplicate key created" "2" \
    "$(jq -r '.generated.rules | length' "$man")"
rm -rf "$proj"

# ── CASE 4: source_hash flows through (the generate-rules staleness axis) ────
proj="$(make_project '')"
printf 'arch\n' >"$proj/.claude/rules/architecture-patterns.md"
out="$(bash "$SCRIPT" --project-dir "$proj" --source 'docs/prds/*' \
        --source-hash 'deadbeefcafe' architecture-patterns.md 2>&1)"
man="$(manifest_of "$proj")"
assert_contains "case4: default RULES_DIR when generated_rules_path is absent" \
    "RULES_DIR=.claude/rules" "$out"
assert_eq "case4: source_hash is stored" "deadbeefcafe" \
    "$(jq -r '.generated.rules["architecture-patterns.md"].source_hash' "$man")"
assert_eq "case4: updated_at is refreshed" "false" \
    "$(jq -r '(.updated_at // "") == ""' "$man")"
rm -rf "$proj"

# ── CASE 5: bad inputs are rejected loudly, good siblings still land ─────────
proj="$(make_project '')"
printf 'dev\n' >"$proj/.claude/rules/development.md"
out="$(bash "$SCRIPT" --project-dir "$proj" development.md absent.md 2>&1)"
rc=$?
man="$(manifest_of "$proj")"
assert_eq "case5: exits 1 when a named rule file is missing" "1" "$rc"
assert_contains "case5: names the missing rule" "TYPE=rule_file_missing" "$out"
assert_eq "case5: the present rule is still registered" "1" \
    "$(jq -r '.generated.rules | length' "$man")"

out="$(bash "$SCRIPT" --project-dir "$proj" '.claude/rules/development.md' 2>&1)"
assert_contains "case5: a key with a directory component is rejected" \
    "TYPE=key_not_bare_filename" "$out"

out="$(bash "$SCRIPT" --project-dir "$proj" development 2>&1)"
assert_contains "case5: a key without the .md extension is rejected" \
    "TYPE=key_missing_extension" "$out"

out="$(bash "$SCRIPT" --project-dir "$proj" 2>&1)"
rc=$?
assert_eq "case5: exits 1 when no rule filenames are supplied" "1" "$rc"
assert_contains "case5: names the empty-input condition" "TYPE=no_rules_given" "$out"
rm -rf "$proj"

# ── CASE 6: unknown argument exits 2 and writes nothing (issue #2057) ────────
proj="$(make_project '')"
printf 'dev\n' >"$proj/.claude/rules/development.md"
man="$(manifest_of "$proj")"
before="$(cat "$man")"
out="$(bash "$SCRIPT" --project-dir "$proj" --only-rules=dev development.md 2>&1)"
rc=$?
assert_eq "case6: unknown flag exits 2, never swallowed" "2" "$rc"
assert_contains "case6: names the unknown flag" "unknown argument: --only-rules=dev" "$out"
assert_eq "case6: the manifest is untouched" "$before" "$(cat "$man")"
rm -rf "$proj"

# ── CASE 7: a missing manifest is an ERROR, not a silent no-op ───────────────
proj="$(mktemp -d)" || { echo "FATAL: mktemp failed" >&2; exit 1; }
[ -n "$proj" ] || { echo "FATAL: empty mktemp dir" >&2; exit 1; }
out="$(bash "$SCRIPT" --project-dir "$proj" development.md 2>&1)"
rc=$?
assert_eq "case7: exits 1 when the manifest is absent" "1" "$rc"
assert_contains "case7: names the missing manifest" "TYPE=manifest_missing" "$out"
rm -rf "$proj"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
