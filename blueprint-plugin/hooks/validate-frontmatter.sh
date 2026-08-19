#!/usr/bin/env bash
# PreToolUse hook — validate a blueprint document against its JSON Schema.
#
# Usage: validate-frontmatter.sh <adr|prd|prp>      (PreToolUse payload on stdin)
#
# THIS FILE DECLARES NO FIELD LIST ON PURPOSE.
#
# It used to. Each of validate-{adr,prd,prp}-frontmatter.sh carried its own
# hand-rolled required-field list, status enum, and id regex, while schemas/
# carried a second description of the same documents. They drifted: the ADR
# schema required `date`, the hook required `created`/`modified`; the schema
# spelled the back-reference `superseded_by`, the hook read `superseded-by`, so
# the "Superseded needs a replacement" check never fired once.
#
# The schema is now the only description. Every rule — required fields, enums,
# id patterns, required `##` sections, which failures merely warn — lives in
# schemas/<kind>.schema.json. scripts/tests/test-schema-field-parity.sh fails
# the build if a field list reappears here.
#
# Fails OPEN: a missing uv/python/jsonschema is an environment gap, not a
# document defect, and a hook that blocks on its own tooling being absent is
# worse than one that stays quiet.

set -euo pipefail

KIND="${1:-}"
case "$KIND" in
    adr|prd|prp) ;;
    *) echo "validate-frontmatter.sh: expected kind adr|prd|prp, got '${KIND}'" >&2; exit 0 ;;
esac

if [ "${BLUEPRINT_SKIP_HOOKS:-0}" = "1" ]; then
    exit 0
fi

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECKER="${HOOK_DIR}/../scripts/check-schema.py"

if [ ! -f "$CHECKER" ]; then
    exit 0
fi

# uv resolves the PEP-723 dependency block; a bare python3 works when
# jsonschema and PyYAML are already installed, and check-schema.py itself
# degrades to STATUS=OK when they are not.
if command -v uv >/dev/null 2>&1; then
    uv run --quiet --script "$CHECKER" --kind "$KIND" --hook
elif command -v python3 >/dev/null 2>&1; then
    python3 "$CHECKER" --kind "$KIND" --hook
else
    exit 0
fi
