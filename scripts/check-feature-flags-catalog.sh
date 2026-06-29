#!/usr/bin/env bash
# Guard against drift between the env feature-flags defined in plugin sources and
# the catalog that documents them (hooks-plugin/docs/feature-flags.md).
#
# The catalog is a hand-maintained index, so a newly-added CLAUDE_HOOKS_* /
# CLAUDE_TASKWARRIOR_* flag can silently land in a hook without a catalog entry —
# exactly the drift documentation-authoring.md warns about. This makes the check
# deterministic instead of relying on someone re-running the regeneration grep.
#
# The check: every flag READ in a plugin source must appear in the catalog. A
# new flag added to a hook without a catalog row fails the gate.
#
# Sources scanned: *.sh under plugin dirs + the native-hook templates/ files.
# Excluded: generated copies (dist/), this script, and dedicated tests/ dirs.
# tests/ are excluded because fixtures construct *fake* flags (e.g. a SAMPLE flag
# to prove the gate fires) that would read as undocumented. A name-based test-*.sh
# exclusion is NOT used — it would wrongly drop the real test-verification.sh
# hook; the test-*.sh fixtures that live beside hooks only reference real,
# already-cataloged flags, so scanning them is harmless.
#
# The catalog may legitimately document MORE than the scan finds — e.g. flags
# read by hooks the skills GENERATE into a user's project (permission-request)
# rather than ship as an in-repo .sh — so a "dangling" reverse-check would
# false-positive and is deliberately omitted.
#
# Emits the structured KEY=value / STATUS= convention
# (.claude/rules/structured-script-output.md) so scheduled-audits can roll it up.
#
# Usage:
#   check-feature-flags-catalog.sh [--project-dir <path>] [--strict]
#
#   --project-dir   Repo root to scan (default: git toplevel, else cwd)
#   --strict        Exit 1 when a source flag is missing from the catalog
#                   (default: always exit 0; DANGLING is a warning either way)
set -uo pipefail

PROJECT_DIR=""
STRICT=0
while [ $# -gt 0 ]; do
    case "$1" in
        --project-dir) PROJECT_DIR="$2"; shift 2 ;;
        --strict) STRICT=1; shift ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

if [ -z "$PROJECT_DIR" ]; then
    PROJECT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

DOC_REL="hooks-plugin/docs/feature-flags.md"
DOC="$PROJECT_DIR/$DOC_REL"

FLAG_RE='CLAUDE_HOOKS_[A-Z_]+|CLAUDE_TASKWARRIOR_[A-Z_]+'

echo "=== FEATURE FLAGS CATALOG ==="

if [ ! -f "$DOC" ]; then
    echo "DOC=$DOC_REL"
    echo "STATUS=ERROR"
    echo "ISSUE_COUNT=1"
    echo "ISSUES:"
    echo "  - SEVERITY=ERROR TYPE=missing_doc MSG=catalog not found at $DOC_REL"
    echo "=== END FEATURE FLAGS CATALOG ==="
    [ "$STRICT" = "1" ] && exit 1 || exit 0
fi

# Flags actually read in plugin sources (the authoritative set).
source_flags=$(rg -oN --no-filename "$FLAG_RE" \
    -g '*.sh' -g '**/templates/*' \
    -g '!**/tests/**' -g '!dist/**' -g '!scripts/check-feature-flags-catalog.sh' \
    "$PROJECT_DIR" 2>/dev/null | sort -u)

# Flags named anywhere in the catalog.
catalog_flags=$(rg -oN --no-filename "$FLAG_RE" "$DOC" 2>/dev/null | sort -u)

source_count=$(printf '%s\n' "$source_flags" | grep -c . || true)
catalog_count=$(printf '%s\n' "$catalog_flags" | grep -c . || true)

# MISSING: read in a source, absent from the catalog.
missing=$(comm -23 <(printf '%s\n' "$source_flags") <(printf '%s\n' "$catalog_flags"))
missing_count=$(printf '%s\n' "$missing" | grep -c . || true)

if [ "$missing_count" -gt 0 ]; then
    overall="ERROR"
else
    overall="OK"
fi

echo "DOC=$DOC_REL"
echo "SOURCE_FLAG_COUNT=$source_count"
echo "CATALOG_FLAG_COUNT=$catalog_count"
echo "MISSING_COUNT=$missing_count"
echo "STATUS=$overall"
echo "ISSUE_COUNT=$missing_count"

if [ "$missing_count" -gt 0 ]; then
    echo "ISSUES:"
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        echo "  - SEVERITY=ERROR TYPE=missing_from_catalog FLAG=$f MSG=flag read in a source but absent from $DOC_REL"
    done <<< "$missing"
fi

echo "=== END FEATURE FLAGS CATALOG ==="

if [ "$STRICT" = "1" ] && [ "$missing_count" -gt 0 ]; then
    exit 1
fi
exit 0
