#!/usr/bin/env bash
# validate-frontmatter.sh — validate blueprint documents against their JSON Schema.
#
# Usage: validate-frontmatter.sh [--strict] <file>...
#
# The schema kind comes from the path: docs/prds/*.md -> prd,
# docs/adrs/*.md -> adr, docs/prps/*.md -> prp. Other paths and README.md
# index files are skipped.
#
# Callers:
#   hooks/blueprint-doc-change.sh   PostToolUse after Write, Edit, or a Bash
#                                   edit. Warns; the edit has already happened.
#   .pre-commit-hooks.yaml          `blueprint-doc-schemas`, with --strict.
#                                   Fails the commit on any ERROR.
#
# Validation used to run as a PreToolUse block. It moved here because a
# PreToolUse hook never sees an edit made through Bash, which Claude Code uses
# for file edits in auto mode; a commit-time check covers every writer.
#
# THIS FILE DECLARES NO FIELD LIST ON PURPOSE.
#
# Each of the former validate-{adr,prd,prp}-frontmatter.sh hooks once carried
# its own hand-rolled required-field list, status enum, and id regex, while
# schemas/ carried a second description of the same documents. They drifted:
# the ADR schema required `date`, the hook required `created`/`modified`; the
# schema spelled the back-reference `superseded_by`, the hook read
# `superseded-by`, so the "Superseded needs a replacement" check never fired.
#
# The schema is now the only description. Every rule — required fields, enums,
# id patterns, required `##` sections, which failures merely warn — lives in
# schemas/<kind>.schema.json. scripts/tests/test-check-schema.sh fails the build
# if a field list reappears here.
#
# Tooling: uv resolves check-schema.py's PEP-723 dependencies. Without uv, the
# default mode falls back to python3 and fails OPEN (an environment gap is not
# a document defect). --strict refuses to fall back: a bare python3 without
# jsonschema reports STATUS=OK for every document, which would turn the commit
# gate into a silent pass.
#
# Output: check-schema.py's structured block for each document that is not OK.
# Exit:   0 when every document is OK or WARN; 1 on any ERROR, or in --strict
#         mode when uv is missing.

set -uo pipefail

STRICT=0
if [ "${1:-}" = "--strict" ]; then
    STRICT=1
    shift
fi

if [ "$STRICT" = "0" ] && [ "${BLUEPRINT_SKIP_HOOKS:-0}" = "1" ]; then
    exit 0
fi

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECKER="${HOOK_DIR}/../scripts/check-schema.py"

if [ ! -f "$CHECKER" ]; then
    [ "$STRICT" = "1" ] && { echo "ERROR: check-schema.py not found at ${CHECKER}" >&2; exit 1; }
    exit 0
fi

if command -v uv >/dev/null 2>&1; then
    run_checker() { uv run --quiet --script "$CHECKER" "$@"; }
elif [ "$STRICT" = "0" ] && command -v python3 >/dev/null 2>&1; then
    run_checker() { python3 "$CHECKER" "$@"; }
elif [ "$STRICT" = "1" ]; then
    echo "ERROR: validate-frontmatter.sh --strict needs uv (https://docs.astral.sh/uv/) to resolve jsonschema and PyYAML" >&2
    exit 1
else
    exit 0
fi

rc=0
for doc in "$@"; do
    case "$doc" in
        */README.md|README.md) continue ;;
        docs/prds/*.md|*/docs/prds/*.md) kind=prd ;;
        docs/adrs/*.md|*/docs/adrs/*.md) kind=adr ;;
        docs/prps/*.md|*/docs/prps/*.md) kind=prp ;;
        *) continue ;;
    esac
    [ -f "$doc" ] || continue

    out=$(run_checker --kind "$kind" --file "$doc" 2>&1)
    doc_rc=$?
    if ! printf '%s\n' "$out" | grep -q '^STATUS=OK$'; then
        printf '%s\n' "$out"
    fi
    [ "$doc_rc" -eq 0 ] || rc=1
done

exit "$rc"
