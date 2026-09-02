#!/usr/bin/env bash
# check-research-radar-grounding.sh — semantic guard for the research-radar
# generator's grounding requirement.
#
# THE DEFECT (#2507)
# `.github/workflows/research-radar.yml` used to instruct the assessing model:
#   "Do not read plugin source files — you are mapping ideas to plugin *names*,
#    not editing them."
# combined with a hardcoded area→plugin table row mapping
# "Prompting techniques, grounding, citations" to `prompt-engineering-plugin`.
# The model therefore suggested stamping a Zero-Shot/Few-Shot/CoT/PoT technique
# catalog onto a plugin that holds 4 files and 1 skill and contains no such
# catalog. `--allowedTools` already granted `Read,Grep,Glob`; only the prompt
# forbade their use, so the radar could not catch this class of error by
# construction.
#
# WHY A SEMANTIC GUARD
# The fix is prose inside a YAML block scalar: a bounded, TOKEN-LEVEL grounding
# requirement (one `Grep` per surfaced paper for the concrete surface the
# suggestion asserts exists; drop or re-target on no hit; state the file and
# pattern in the issue body). A prompt-tightening edit could silently drop it
# while the workflow still parses. Note a path-existence probe would NOT have
# caught the original hallucination — `prompt-engineering-plugin/skills/*/SKILL.md`
# does exist; only a token probe does. This guard asserts both directions: the
# grounding clauses are PRESENT and the old blanket prohibition is ABSENT
# (.claude/rules/regression-testing.md: semantic > syntactic).
#
# Output: structured KEY=VALUE per .claude/rules/structured-script-output.md.
#
# Usage:
#   bash scripts/check-research-radar-grounding.sh [--strict] [DIR]
#
#   --strict   exit 1 when ISSUE_COUNT > 0 (for pre-commit / CI). Default: report.
#   DIR        repo root to scan (default: this script's repo)
#
# Exit codes:
#   0 - no issues (or not --strict)
#   1 - --strict and at least one issue
#   2 - unknown argument

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
STRICT=0

usage() {
    echo "Usage: check-research-radar-grounding.sh [--strict] [DIR]" >&2
}

# An unknown argument is REJECTED, never swallowed (#2057): a silently-ignored
# flag turns a gate into a no-op that still exits 0.
while [ $# -gt 0 ]; do
    case "$1" in
        --strict) STRICT=1; shift ;;
        -h|--help) usage; exit 0 ;;
        -*)
            echo "check-research-radar-grounding.sh: unknown argument: $1" >&2
            usage
            exit 2 ;;
        *)
            if [ ! -d "$1" ]; then
                echo "check-research-radar-grounding.sh: not a directory: $1" >&2
                usage
                exit 2
            fi
            ROOT_DIR="$(cd "$1" && pwd)"; shift ;;
    esac
done

WORKFLOW="$ROOT_DIR/.github/workflows/research-radar.yml"

issue_count=0
declare -a issues=()

# require FILE TOKEN MESSAGE — assert a literal token is PRESENT (file must exist).
require() {
    local file="$1" token="$2" msg="$3" rel
    rel="${file#"$ROOT_DIR"/}"
    if [ ! -f "$file" ]; then
        issue_count=$((issue_count + 1))
        issues+=("  - SEVERITY=ERROR FILE=$rel MSG=missing file ($msg)")
        return
    fi
    if ! grep -qF "$token" "$file"; then
        issue_count=$((issue_count + 1))
        issues+=("  - SEVERITY=ERROR FILE=$rel TOKEN=\"$token\" MSG=$msg")
    fi
}

# forbid FILE TOKEN MESSAGE — assert a literal token is ABSENT (file must exist).
forbid() {
    local file="$1" token="$2" msg="$3" rel
    rel="${file#"$ROOT_DIR"/}"
    if [ ! -f "$file" ]; then
        issue_count=$((issue_count + 1))
        issues+=("  - SEVERITY=ERROR FILE=$rel MSG=missing file ($msg)")
        return
    fi
    if grep -qF "$token" "$file"; then
        issue_count=$((issue_count + 1))
        issues+=("  - SEVERITY=ERROR FILE=$rel TOKEN=\"$token\" MSG=$msg")
    fi
}

require "$WORKFLOW" "Ground every surfaced suggestion" \
    "research-radar prompt lost the per-paper grounding requirement (suggestions can name surfaces that do not exist)"
require "$WORKFLOW" "or drop the paper" \
    "research-radar prompt lost the drop-or-re-target instruction for an ungrounded suggestion"
require "$WORKFLOW" "State the exact file(s) and pattern grepped" \
    "research-radar prompt lost the grounding-evidence disclosure in the issue body"
forbid "$WORKFLOW" "Do not read plugin source files" \
    "research-radar prompt re-introduced the blanket no-source-read clause (#2507 root cause)"

status="OK"
[ "$issue_count" -gt 0 ] && status="ERROR"

echo "=== RESEARCH RADAR GROUNDING ==="
echo "WORKFLOW_PRESENT=$([ -f "$WORKFLOW" ] && echo true || echo false)"
echo "STATUS=$status"
echo "ISSUE_COUNT=$issue_count"
if [ "$issue_count" -gt 0 ]; then
    echo "ISSUES:"
    printf '%s\n' "${issues[@]}"
    echo ""
    echo "FIX: restore the grounding bullets in the 'Efficiency rules' section of"
    echo "     .github/workflows/research-radar.yml; see issue #2507."
fi
echo "=== END RESEARCH RADAR GROUNDING ==="

if [ "$STRICT" -eq 1 ] && [ "$issue_count" -gt 0 ]; then
    exit 1
fi
exit 0
