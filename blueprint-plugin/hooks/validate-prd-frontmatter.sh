#!/usr/bin/env bash
# PreToolUse hook for PRD documents.
#
# Thin wrapper kept so hooks.json entries and any hand-wired settings.json
# keep resolving. The implementation — and the schema that owns every rule —
# is validate-frontmatter.sh + schemas/prd.schema.json.
set -euo pipefail
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/validate-frontmatter.sh" prd
