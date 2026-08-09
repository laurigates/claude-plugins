#!/usr/bin/env bash
# register-generated-rules.sh — write `generated.rules` provenance records for
# rule files blueprint just created (issue #2331).
#
# WHY THIS EXISTS
#
# Two skills write into the generated-rules directory: `blueprint-init`
# (Step 8, the initial development/testing/document-management rules) and
# `blueprint-generate-rules` (Step 5, the four PRD-derived domain rules). Only
# the second registered its output, so `/blueprint:sync` — which detects drift
# by comparing a REGISTERED record's `content_hash` against the file — was
# structurally blind to everything `init` created: a local edit was undetectable,
# a template revision never propagated, and the sync run reported clean over a
# set it could not see. None of it surfaced as an error.
#
# Rather than have each skill hand-roll the same jq, both invoke this script.
# One implementation means the two producers cannot drift apart again, and the
# hash is computed exactly one way.
#
# ── THE CONTRACT (all four sites must agree; see #2331) ───────────────────────
#
#   SHAPE      `generated.rules` is an OBJECT map, per
#              blueprint-plugin/schemas/manifest.schema.json
#              (`generatedBucket`: filename -> `generatedRecord`). It is not an
#              array. Consumers iterate it with `to_entries[]`.
#
#   KEY FORM   The key is the rule's BARE FILENAME, RELATIVE to
#              `structure.generated_rules_path`, INCLUDING the `.md` extension —
#              e.g. `development.md`, never `development` and never
#              `.claude/rules/development.md`.
#
#              Relative, because the registry then survives a change to
#              `generated_rules_path` (the path lives in `structure`, exactly
#              once). With the extension, because that is the form
#              `blueprint-generate-rules` already ships, so no existing manifest
#              needs migrating.
#
#              A consumer resolves a file as "$RULES_DIR/$key" and MUST NOT
#              append `.md` — doing so yields `development.md.md`, which never
#              exists, so every rule silently reads as missing.
#
#   HASH FORM  `content_hash` is a BARE lowercase hex sha256 digest, with no
#              `sha256:` prefix. Both readers (`blueprint-sync` Step 2b and
#              `blueprint-plugin/hooks/blueprint-drift-probe.sh`) compare the
#              raw output of `sha256sum`/`shasum -a 256` against this field, so
#              a prefixed value can never match and every rule reads as
#              perpetually modified.
#
# ── OUTPUT ────────────────────────────────────────────────────────────────────
#
# Structured KEY=VALUE per .claude/rules/structured-script-output.md.
#
#   MANIFEST=<path>              the manifest written
#   RULES_DIR=<path>             resolved from structure.generated_rules_path
#   KEY_FORM=filename-with-extension
#   REGISTERED=<int>             number of records written
#   RULE_<n>_KEY=<filename>      the manifest key
#   RULE_<n>_PATH=<path>         "$RULES_DIR/$key" — the file the key resolves to
#   RULE_<n>_CONTENT_HASH=<hex>  bare sha256
#   STATUS=OK|ERROR
#   ISSUE_COUNT=<int>
#
# Exit 0 on OK, 1 on ERROR, 2 on an unknown argument (a swallowed flag on a
# WRITING script silently changes what lands — see issue #2057).
#
# Usage:
#   register-generated-rules.sh [--project-dir DIR] [--manifest PATH]
#                               [--source STR] [--source-hash STR]
#                               [--plugin-version STR] [--status STR]
#                               <rule-filename> [<rule-filename> ...]

set -u

SECTION="GENERATED RULES REGISTRATION"

usage() {
    cat >&2 <<'USAGE'
Usage: register-generated-rules.sh [--project-dir DIR] [--manifest PATH]
                                   [--source STR] [--source-hash STR]
                                   [--plugin-version STR] [--status STR]
                                   <rule-filename> [<rule-filename> ...]

Rule filenames are BARE and relative to structure.generated_rules_path,
including the .md extension (e.g. development.md).
USAGE
}

project_dir="."
manifest=""
rec_source="blueprint-init"
rec_source_hash=""
rec_plugin_version=""
rec_status="current"
rules=()

while [ $# -gt 0 ]; do
    case "$1" in
        --project-dir)      project_dir="${2:-.}"; shift 2 ;;
        --project-dir=*)    project_dir="${1#*=}"; shift ;;
        --manifest)         manifest="${2:-}"; shift 2 ;;
        --manifest=*)       manifest="${1#*=}"; shift ;;
        --source)           rec_source="${2:-}"; shift 2 ;;
        --source=*)         rec_source="${1#*=}"; shift ;;
        --source-hash)      rec_source_hash="${2:-}"; shift 2 ;;
        --source-hash=*)    rec_source_hash="${1#*=}"; shift ;;
        --plugin-version)   rec_plugin_version="${2:-}"; shift 2 ;;
        --plugin-version=*) rec_plugin_version="${1#*=}"; shift ;;
        --status)           rec_status="${2:-}"; shift 2 ;;
        --status=*)         rec_status="${1#*=}"; shift ;;
        -h|--help)          usage; exit 0 ;;
        --)                 shift; while [ $# -gt 0 ]; do rules+=("$1"); shift; done ;;
        -*)
            printf 'register-generated-rules.sh: unknown argument: %s\n' "$1" >&2
            usage
            exit 2
            ;;
        *)                  rules+=("$1"); shift ;;
    esac
done

emit_fatal() { # <message>
    printf '=== %s ===\n' "$SECTION"
    printf 'REGISTERED=0\n'
    printf 'STATUS=ERROR\n'
    printf 'ISSUE_COUNT=1\n'
    printf 'ISSUES:\n'
    printf '  - SEVERITY=ERROR TYPE=%s MSG=%s\n' "$1" "$2"
    printf '=== END %s ===\n' "$SECTION"
    exit 1
}

[ "${#rules[@]}" -gt 0 ] || emit_fatal no_rules_given "no rule filenames supplied"

[ -n "$manifest" ] || manifest="${project_dir%/}/docs/blueprint/manifest.json"

command -v jq >/dev/null 2>&1 || emit_fatal jq_missing "jq is required to write the manifest"
[ -f "$manifest" ] || emit_fatal manifest_missing "manifest not found: $manifest"

# Portable bare-hex sha256 (BSD `shasum` on macOS, GNU `sha256sum` on Linux).
# The reader side computes the same value; see the HASH FORM note above.
sha256_of() { # <file>
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" 2>/dev/null | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'
    else
        printf ''
    fi
}

rules_dir="$(jq -r '.structure.generated_rules_path // ".claude/rules/"' "$manifest" 2>/dev/null)"
[ -n "$rules_dir" ] && [ "$rules_dir" != "null" ] || rules_dir=".claude/rules/"
rules_dir="${rules_dir%/}"

generated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

issues=()
registered=0
out_lines=()

for key in "${rules[@]}"; do
    # The key is a bare filename relative to $RULES_DIR. Reject a directory
    # component up front: a key like `.claude/rules/development.md` would
    # resolve to `$RULES_DIR/.claude/rules/development.md` for every consumer.
    case "$key" in
        */*) issues+=("SEVERITY=ERROR TYPE=key_not_bare_filename KEY=$key MSG=key must be a bare filename relative to generated_rules_path"); continue ;;
    esac
    case "$key" in
        *.md) ;;
        *) issues+=("SEVERITY=ERROR TYPE=key_missing_extension KEY=$key MSG=key must include the .md extension"); continue ;;
    esac

    rule_path="${project_dir%/}/${rules_dir}/${key}"
    if [ ! -f "$rule_path" ]; then
        issues+=("SEVERITY=ERROR TYPE=rule_file_missing KEY=$key MSG=no file at ${rules_dir}/${key}")
        continue
    fi

    content_hash="$(sha256_of "$rule_path")"
    if [ -z "$content_hash" ]; then
        issues+=("SEVERITY=ERROR TYPE=hash_unavailable KEY=$key MSG=no sha256sum or shasum on PATH")
        continue
    fi

    tmp="${manifest}.tmp.$$"
    if jq \
        --arg key "$key" \
        --arg src "$rec_source" \
        --arg srchash "$rec_source_hash" \
        --arg at "$generated_at" \
        --arg pv "$rec_plugin_version" \
        --arg ch "$content_hash" \
        --arg st "$rec_status" \
        '
        .generated = (.generated // {})
        | .generated.rules = (.generated.rules // {})
        | .generated.rules[$key] = (
            ((.generated.rules[$key] // {}))
            + {source: $src, generated_at: $at, content_hash: $ch, status: $st}
            + (if $srchash == "" then {} else {source_hash: $srchash} end)
            + (if $pv == "" then {} else {plugin_version: $pv} end)
          )
        | .updated_at = $at
        ' "$manifest" >"$tmp" 2>/dev/null && [ -s "$tmp" ]; then
        mv "$tmp" "$manifest"
    else
        rm -f "$tmp"
        issues+=("SEVERITY=ERROR TYPE=manifest_write_failed KEY=$key MSG=jq update failed")
        continue
    fi

    registered=$((registered + 1))
    out_lines+=("RULE_${registered}_KEY=${key}")
    out_lines+=("RULE_${registered}_PATH=${rules_dir}/${key}")
    out_lines+=("RULE_${registered}_CONTENT_HASH=${content_hash}")
done

printf '=== %s ===\n' "$SECTION"
printf 'MANIFEST=%s\n' "$manifest"
printf 'RULES_DIR=%s\n' "$rules_dir"
printf 'KEY_FORM=filename-with-extension\n'
printf 'REGISTERED=%d\n' "$registered"
for line in ${out_lines+"${out_lines[@]}"}; do
    printf '%s\n' "$line"
done
if [ "${#issues[@]}" -eq 0 ]; then
    printf 'STATUS=OK\n'
    printf 'ISSUE_COUNT=0\n'
    printf '=== END %s ===\n' "$SECTION"
    exit 0
fi
printf 'STATUS=ERROR\n'
printf 'ISSUE_COUNT=%d\n' "${#issues[@]}"
printf 'ISSUES:\n'
for issue in "${issues[@]}"; do
    printf '  - %s\n' "$issue"
done
printf '=== END %s ===\n' "$SECTION"
exit 1
