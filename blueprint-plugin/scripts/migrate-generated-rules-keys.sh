#!/usr/bin/env bash
# migrate-generated-rules-keys.sh — detect and fix pre-contract `generated.rules`
# records (issue #2868).
#
# WHY THIS EXISTS
#
# The `generated.rules` contract (see register-generated-rules.sh) keys each
# record by the rule's bare filename INCLUDING `.md` and stores a bare-hex
# `content_hash`. Manifests written by blueprint 3.0.0 (format 3.2.0) predate
# it: keys are `architecture-patterns`, not `architecture-patterns.md`, and no
# record carries a hash. /blueprint:sync resolves "$RULES_DIR/$key", finds no
# file, and reports every rule missing — sync is silently blind. No format
# migration touches `generated.rules`, so upgrading to 3.4.0 does not fix it.
#
# WHAT IT DOES (idempotent; a second run is a no-op)
#
#   key_missing_extension  key lacks `.md` and "$RULES_DIR/<key>.md" exists
#                          -> re-key to `<key>.md`, keeping every other field
#   record_missing_hash    record has no `content_hash` and its file exists
#                          -> backfill the bare sha256 of the CURRENT file and
#                             set `status: "modified"` (the schema enum's word
#                             for user-edited). The file has been edited since
#                             generation and nothing recorded the original hash,
#                             so its content is taken as the user's, never
#                             overwritten.
#   key_unresolved         key lacks `.md` and no `<key>.md` exists -> left
#                          untouched, reported (WARN) for a human
#   key_conflict           both `<key>` and `<key>.md` are registered -> left
#                          untouched, reported (WARN) for a human
#
# An existing `content_hash` is never overwritten; rule files are never touched.
#
# ── OUTPUT ────────────────────────────────────────────────────────────────────
#
# Structured KEY=VALUE per .claude/rules/structured-script-output.md:
#
#   MANIFEST, RULES_DIR, MODE=dry-run|apply, ENTRIES,
#   KEY_MISSING_EXTENSION, RECORD_MISSING_HASH, UNRESOLVED, CONFLICTS,
#   MIGRATED (records rewritten; always 0 under --dry-run),
#   STATUS=OK|WARN|ERROR, REASON (non-OK only), ISSUE_COUNT, ISSUES:
#
# In dry-run every finding is an issue. In apply mode only what is left behind
# (key_unresolved, key_conflict) is. Exit 0 on OK/WARN, 1 on ERROR, 2 on an
# unknown argument (a swallowed flag on a WRITING script — say `--dryrun` —
# would silently write; issue #2057).
#
# Usage:
#   migrate-generated-rules-keys.sh [--project-dir DIR] [--manifest PATH] [--dry-run]

set -u

SECTION="GENERATED RULES KEY MIGRATION"

usage() {
    cat >&2 <<'USAGE'
Usage: migrate-generated-rules-keys.sh [--project-dir DIR] [--manifest PATH] [--dry-run]

Re-keys pre-contract generated.rules entries (no .md extension) and backfills
missing content_hash values. --dry-run reports without writing.
USAGE
}

project_dir="."
manifest=""
dry_run=false

bad_arg() { # <argument as given>
    printf 'migrate-generated-rules-keys.sh: unknown argument: %s\n' "$1" >&2
    usage
    exit 2
}

# A flag whose value is empty or missing is an unknown argument, never a silent
# default: `--project-dir=` root-anchors the rules dir, and a trailing
# `--manifest` used to `shift 2` past the end (which fails without shifting and
# loops forever) or fall back to the project manifest — a swallowed argument
# retargeting which file is written (#2057).
while [ $# -gt 0 ]; do
    case "$1" in
        --project-dir|--manifest)
            if [ $# -lt 2 ] || [ -z "$2" ]; then bad_arg "$1 (missing value)"; fi
            if [ "$1" = "--manifest" ]; then manifest="$2"; else project_dir="$2"; fi
            shift 2
            ;;
        --project-dir=*|--manifest=*)
            [ -n "${1#*=}" ] || bad_arg "$1 (empty value)"
            case "$1" in
                --manifest=*) manifest="${1#*=}" ;;
                *)            project_dir="${1#*=}" ;;
            esac
            shift
            ;;
        --dry-run)       dry_run=true; shift ;;
        -h|--help)       usage; exit 0 ;;
        *)               bad_arg "$1" ;;
    esac
done

mode="apply"
$dry_run && mode="dry-run"

[ -n "$manifest" ] || manifest="${project_dir%/}/docs/blueprint/manifest.json"

emit_fatal() { # <type> <message>
    printf '=== %s ===\n' "$SECTION"
    printf 'MANIFEST=%s\n' "$manifest"
    printf 'MODE=%s\n' "$mode"
    printf 'MIGRATED=0\n'
    printf 'STATUS=ERROR\n'
    printf 'REASON=%s: %s\n' "$1" "$2"
    printf 'ISSUE_COUNT=1\n'
    printf 'ISSUES:\n'
    printf '  - SEVERITY=ERROR TYPE=%s MSG=%s\n' "$1" "$2"
    printf '=== END %s ===\n' "$SECTION"
    exit 1
}

# No manifest means nothing to migrate — sync/status call this on any repo.
if [ ! -f "$manifest" ]; then
    printf '=== %s ===\n' "$SECTION"
    printf 'SOURCE=none\n'
    printf 'MODE=%s\n' "$mode"
    printf 'MIGRATED=0\n'
    printf 'STATUS=OK\n'
    printf 'ISSUE_COUNT=0\n'
    printf '=== END %s ===\n' "$SECTION"
    exit 0
fi

command -v jq >/dev/null 2>&1 || emit_fatal jq_missing "jq is required to read the manifest"
jq -e . "$manifest" >/dev/null 2>&1 || emit_fatal json_parse "manifest is not valid JSON: $manifest"

# Portable bare-hex sha256 (GNU `sha256sum`, BSD `shasum -a 256`) — the same
# form register-generated-rules.sh writes and blueprint-sync compares.
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
rules_abs="${project_dir%/}/${rules_dir}"

rules_type="$(jq -r '.generated.rules | type' "$manifest")"
if [ "$rules_type" != "object" ]; then
    # null (absent) is the common, clean case; any other shape is not ours to fix.
    printf '=== %s ===\n' "$SECTION"
    printf 'MANIFEST=%s\n' "$manifest"
    printf 'RULES_DIR=%s\n' "$rules_dir"
    printf 'MODE=%s\n' "$mode"
    printf 'ENTRIES=0\n'
    printf 'MIGRATED=0\n'
    if [ "$rules_type" = "null" ]; then
        printf 'STATUS=OK\n'
        printf 'ISSUE_COUNT=0\n'
    else
        printf 'STATUS=WARN\n'
        printf 'REASON=generated_rules_not_object: generated.rules is a %s, expected an object map\n' "$rules_type"
        printf 'ISSUE_COUNT=1\n'
        printf 'ISSUES:\n'
        printf '  - SEVERITY=WARN TYPE=generated_rules_not_object MSG=generated.rules is a %s, expected an object map\n' "$rules_type"
    fi
    printf '=== END %s ===\n' "$SECTION"
    exit 0
fi

entries=0
n_ext=0
n_hash=0
n_unresolved=0
n_conflict=0
plan='{}'          # { "<old key>": {"to": "<new key>", "hash": "<hex or empty>"} }
findings=()        # dry-run issues (every finding)
residual=()        # apply-mode issues (what is left behind)

while IFS=$'\t' read -r key has_hash; do
    [ -n "$key" ] || continue
    entries=$((entries + 1))

    case "$key" in
        *.md) target="$key" ;;
        *)    target="${key}.md" ;;
    esac

    if [ "$target" != "$key" ]; then
        if [ ! -f "${rules_abs}/${target}" ]; then
            n_unresolved=$((n_unresolved + 1))
            msg="SEVERITY=WARN TYPE=key_unresolved KEY=$key MSG=no file at ${rules_dir}/${target}; left untouched"
            findings+=("$msg"); residual+=("$msg")
            continue
        fi
        if jq -e --arg k "$target" '.generated.rules | has($k)' "$manifest" >/dev/null 2>&1; then
            n_conflict=$((n_conflict + 1))
            msg="SEVERITY=WARN TYPE=key_conflict KEY=$key MSG=$target is already registered; left untouched"
            findings+=("$msg"); residual+=("$msg")
            continue
        fi
        n_ext=$((n_ext + 1))
        findings+=("SEVERITY=WARN TYPE=key_missing_extension KEY=$key MSG=resolves to ${rules_dir}/${target}; re-key to $target")
    fi

    hash=""
    if [ "$has_hash" != "true" ] && [ -f "${rules_abs}/${target}" ]; then
        n_hash=$((n_hash + 1))
        findings+=("SEVERITY=WARN TYPE=record_missing_hash KEY=$key MSG=no content_hash; backfill from ${rules_dir}/${target} as modified")
        hash="$(sha256_of "${rules_abs}/${target}")"
        [ -n "$hash" ] || emit_fatal hash_unavailable "no sha256sum or shasum on PATH"
    fi

    if [ "$target" != "$key" ] || [ -n "$hash" ]; then
        plan="$(jq -c --arg k "$key" --arg to "$target" --arg h "$hash" \
            '. + {($k): {to: $to, hash: $h}}' <<<"$plan")"
    fi
done < <(jq -r '.generated.rules | to_entries[]
    | [.key, ((.value | type) == "object" and ((.value.content_hash // "") | tostring) != "" | tostring)]
    | @tsv' "$manifest")

migrated="$(jq 'length' <<<"$plan")"

if ! $dry_run && [ "$migrated" -gt 0 ]; then
    tmp="${manifest}.tmp.$$"
    at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    if jq --argjson plan "$plan" --arg at "$at" '
        .generated.rules |= with_entries(
            ($plan[.key]) as $p
            | if $p == null then .
              else .key = $p.to
                   | .value = ((.value // {})
                       + (if $p.hash == "" then {} else {content_hash: $p.hash, status: "modified"} end))
              end)
        | .updated_at = $at
        ' "$manifest" >"$tmp" 2>/dev/null && [ -s "$tmp" ]; then
        mv "$tmp" "$manifest"
    else
        rm -f "$tmp"
        emit_fatal manifest_write_failed "jq update failed for $manifest"
    fi
fi
$dry_run && migrated=0

# `${arr[@]+"${arr[@]}"}`, never a bare "${arr[@]}": with `set -u`, bash < 4.4
# (macOS /bin/bash 3.2) treats an empty array as unbound and aborts — on exactly
# the clean / no-op paths sync and status run on every repo (PR #3052 review).
# The issue count comes from the scalar counters, not `${#issues[@]}`, so the
# empty case never touches an empty array at all.
if $dry_run; then
    issues=(${findings[@]+"${findings[@]}"})
    issue_count=$((n_ext + n_hash + n_unresolved + n_conflict))
else
    issues=(${residual[@]+"${residual[@]}"})
    issue_count=$((n_unresolved + n_conflict))
fi

printf '=== %s ===\n' "$SECTION"
printf 'MANIFEST=%s\n' "$manifest"
printf 'RULES_DIR=%s\n' "$rules_dir"
printf 'MODE=%s\n' "$mode"
printf 'ENTRIES=%d\n' "$entries"
if $dry_run; then
    printf 'KEY_MISSING_EXTENSION=%d\n' "$n_ext"
    printf 'RECORD_MISSING_HASH=%d\n' "$n_hash"
else
    # After an apply, the fixable findings are fixed.
    printf 'KEY_MISSING_EXTENSION=0\n'
    printf 'RECORD_MISSING_HASH=0\n'
fi
printf 'UNRESOLVED=%d\n' "$n_unresolved"
printf 'CONFLICTS=%d\n' "$n_conflict"
printf 'MIGRATED=%d\n' "$migrated"
if [ "$issue_count" -eq 0 ]; then
    printf 'STATUS=OK\n'
    printf 'ISSUE_COUNT=0\n'
else
    first="${issues[0]}"
    first_type="${first#*TYPE=}"; first_type="${first_type%% *}"
    first_msg="${first#*MSG=}"
    reason="${first_type}: ${first_msg}"
    reason="${reason:0:180}"
    [ "$issue_count" -gt 1 ] && reason="${reason} (+$((issue_count - 1)) more)"
    printf 'STATUS=WARN\n'
    printf 'REASON=%s\n' "$reason"
    printf 'ISSUE_COUNT=%d\n' "$issue_count"
    printf 'ISSUES:\n'
    for issue in ${issues[@]+"${issues[@]}"}; do
        printf '  - %s\n' "$issue"
    done
fi
printf '=== END %s ===\n' "$SECTION"
exit 0
