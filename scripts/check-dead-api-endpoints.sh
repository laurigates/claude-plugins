#!/usr/bin/env bash
# check-dead-api-endpoints.sh — deny known-retired REST endpoints in skills,
# scripts, and rules.
#
# A retired endpoint is worse than a broken one: `gh api` prints a 410 to
# stderr, the caller swallows it with `2>/dev/null`, and the failure is
# reported as something else entirely. The canonical case is
# /orgs/{org}/settings/billing/actions, whose caller told the reader to obtain
# an `admin:org` scope that would not have helped — a permission error for an
# endpoint that no longer exists.
#
# Same shape as lint-mcp-tool-references.sh (unavailable MCP tools) and
# lint-package-references.sh (nonexistent packages): a curated denylist of
# things that LOOK valid and silently are not. Extend `denylist` when another
# endpoint retires.
#
# Comments and blockquotes are skipped on purpose, so a file may still TEACH the
# hazard — the discrimination check-agent-tool-selection.sh already makes
# between an instruction and an explanation.
#
# Exit: 0 clean or warnings, 1 on findings under --strict, 2 on a bad argument.

set -uo pipefail

STRICT=0
PROJ_DIR="."

while [ $# -gt 0 ]; do
    case "$1" in
        --strict) STRICT=1 ; shift ;;
        --project-dir) PROJ_DIR="${2:-}" ; shift 2 ;;
        -h|--help)
            printf 'usage: %s [--strict] [--project-dir DIR]\n' "${0##*/}"
            exit 0
            ;;
        *)
            printf '%s: unknown argument: %s\n' "${0##*/}" "$1" >&2
            printf 'usage: %s [--strict] [--project-dir DIR]\n' "${0##*/}" >&2
            exit 2
            ;;
    esac
done

if [ ! -d "$PROJ_DIR" ]; then
    printf '%s: --project-dir not found: %s\n' "${0##*/}" "$PROJ_DIR" >&2
    exit 2
fi

# pattern|replacement|reference
denylist=(
    'settings/billing/actions|/orgs/{org}/settings/billing/usage (per-repo line items; sum quantity/netAmount)|HTTP 410 — gh.io/billing-api-updates-org'
    'settings/billing/packages|/orgs/{org}/settings/billing/usage (filter .product == "packages")|HTTP 410 — gh.io/billing-api-updates-org'
    'settings/billing/shared-storage|/orgs/{org}/settings/billing/usage (filter on the storage product)|HTTP 410 — gh.io/billing-api-updates-org'
)

echo "=== DEAD API ENDPOINTS ==="

# Discovery runs from INSIDE the root against RELATIVE paths, so a scan root
# that is itself an agent worktree cannot match its own prune (#2290).
#
# This guard must scan .sh as well as .md — the defect it exists for lived in a
# script, not a doc — so unlike the markdown-only sibling lints it can match its
# own denylist. Excluded by name; the test fixture proves the exclusion is
# narrow enough that a real script is still caught.
SELF_NAME="${0##*/}"
files=()
while IFS= read -r -d '' f; do
    case "${f##*/}" in
        "$SELF_NAME") continue ;;
    esac
    files+=("$f")
#
# Two directories are pruned because their JOB is to carry the broken form:
#   .claude/rules/  — the hazard log; regression-testing.md must name the dead
#                     endpoint to record that it was fixed.
#   scripts/tests/  — a guard's fixtures must contain the very string it
#                     detects, or the test proves nothing.
# Same discrimination check-branch-containment-guidance.sh makes by scanning
# only git-plugin/**/*.md, and check-agent-tool-selection.sh by allowlisting
# its trap-fixture directory: teaching a hazard is not instructing it.
done < <(cd "$PROJ_DIR" && find . \
    -path '*/.claude/worktrees/*' -prune -o \
    -path '*/.claude/rules/*' -prune -o \
    -path './scripts/tests/*' -prune -o \
    -path '*/dist/*' -prune -o \
    -path '*/node_modules/*' -prune -o \
    \( -name '*.md' -o -name '*.sh' \) \
    -type f -print0 | sort -z)

scanned=${#files[@]}
echo "FILES_SCANNED=${scanned}"

plugin_dirs=$(cd "$PROJ_DIR" && find . -maxdepth 1 -type d -name '*-plugin' | wc -l | tr -d ' ')
if [ "$scanned" -eq 0 ]; then
    if [ "${plugin_dirs:-0}" -gt 0 ]; then
        # Plugin dirs present but nothing discovered = the walk misfired. A
        # clean OK over zero files is the failure mode this reports instead.
        echo "ISSUE_COUNT=1"
        echo "ISSUES:"
        echo "  - SEVERITY=ERROR TYPE=nothing_scanned MSG=plugin directories present but no files discovered"
        echo "STATUS=ERROR"
        exit 1
    fi
    echo "SCANNED_EMPTY=true"
    echo "ISSUE_COUNT=0"
    echo "STATUS=OK"
    exit 0
fi

issues=""
count=0

for entry in "${denylist[@]}"; do
    pattern="${entry%%|*}"
    rest="${entry#*|}"
    replacement="${rest%%|*}"
    reference="${rest##*|}"

    while IFS= read -r hit; do
        [ -n "$hit" ] || continue
        file="${hit%%:*}"
        rest_hit="${hit#*:}"
        lineno="${rest_hit%%:*}"
        text="${rest_hit#*:}"

        # Skip a shell comment or a markdown blockquote — those TEACH the
        # hazard rather than instructing it.
        case "$(printf '%s' "$text" | sed 's/^[[:space:]]*//')" in
            '#'*|'>'*) continue ;;
        esac

        count=$((count + 1))
        issues="${issues}  - SEVERITY=ERROR TYPE=dead_endpoint FILE=${file}:${lineno} ENDPOINT=${pattern} USE=${replacement} WHY=${reference}\n"
    # -H is load-bearing, not decoration: with a SINGLE file argument GNU grep
    # omits the filename prefix while BSD grep keeps it, so the FILE:LINE:TEXT
    # parse below silently shifts by one field on Linux and reads the line
    # number as the filename. Passed locally on macOS, failed in CI.
    done < <(cd "$PROJ_DIR" && grep -rHn -F "$pattern" "${files[@]}" 2>/dev/null)
done

echo "ISSUE_COUNT=${count}"
if [ "$count" -gt 0 ]; then
    echo "ISSUES:"
    printf '%b' "$issues"
    echo "STATUS=ERROR"
    [ "$STRICT" -eq 1 ] && exit 1
    exit 0
fi

echo "STATUS=OK"
exit 0
