#!/usr/bin/env bash
# check-loop-integrity.sh — semantic guard for the loop-integrity convention.
#
# THE CONVENTION (.claude/rules/loop-integrity.md)
# Long-running / self-continuing loops carry two invariants:
#   Pillar 1 — the stop condition is judged INDEPENDENTLY (a fresh verifier, not
#              the worker, decides "done"; else the loop optimises for completion
#              over correctness).
#   Pillar 2 — each iteration leaves a COMPACT STATE PACKET (objective, ref,
#              files-in-scope, exit condition, verifier result, changed-since)
#              so a context-free successor can re-enter cleanly.
#
# WHY A SEMANTIC GUARD
# These invariants live as prose + a plan-file schema across four files. A
# bulk-edit agent "tightening" the checkpoint skill could silently drop the
# Verifier-result field or the independent-verifier step, reverting the skill to
# a self-judged loop with a passing YAML parse. A syntactic check would miss it.
# This guard asserts the load-bearing tokens survive (regression-testing.md:
# semantic > syntactic).
#
# Output: structured KEY=VALUE per .claude/rules/structured-script-output.md.
#   --strict  exit 1 when ISSUE_COUNT > 0 (for pre-commit / CI). Default: report.

set -uo pipefail

STRICT=0
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
for arg in "$@"; do
    case "$arg" in
        --strict) STRICT=1 ;;
        *) [ -d "$arg" ] && ROOT_DIR="$arg" ;;
    esac
done

RULE="$ROOT_DIR/.claude/rules/loop-integrity.md"
CHECKPOINT="$ROOT_DIR/workflow-orchestration-plugin/skills/workflow-checkpoint-refactor/SKILL.md"
TEST_LOOP="$ROOT_DIR/project-plugin/skills/project-test-loop/SKILL.md"
ADVERSARIAL="$ROOT_DIR/agent-patterns-plugin/skills/adversarial-review/SKILL.md"

issue_count=0
declare -a issues=()

# require FILE TOKEN MESSAGE — assert a literal token is present (file must exist).
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

# Rule file — both pillars must remain articulated.
require "$RULE" "independently" "Pillar 1 (independent stop condition) dropped from the rule"
require "$RULE" "compact state packet" "Pillar 2 (state packet) dropped from the rule"
require "$RULE" "Verifier result" "state-packet field list dropped from the rule"

# Checkpoint skill — the plan file IS the state packet; gate stays independent.
require "$CHECKPOINT" "Verifier result" "checkpoint plan format lost the Verifier-result field (reverts to self-judged done)"
require "$CHECKPOINT" "Changed since last run" "checkpoint plan format lost the changed-since field (resume redoes/undoes work)"
require "$CHECKPOINT" "Exit condition" "checkpoint plan format lost the top-level exit condition"
require "$CHECKPOINT" "independent verifier" "checkpoint phase gate lost the independent-verifier step"
require "$CHECKPOINT" "loop-integrity.md" "checkpoint skill lost its loop-integrity cross-reference"

# Sibling skills — keep the cross-reference so the convention stays discoverable.
require "$TEST_LOOP" "loop-integrity.md" "project-test-loop lost its loop-integrity cross-reference"
require "$ADVERSARIAL" "loop-integrity.md" "adversarial-review lost its loop-integrity (Pillar 1) cross-reference"

status="OK"
[ "$issue_count" -gt 0 ] && status="ERROR"

echo "=== LOOP INTEGRITY ==="
echo "RULE_PRESENT=$([ -f "$RULE" ] && echo true || echo false)"
echo "STATUS=$status"
echo "ISSUE_COUNT=$issue_count"
if [ "$issue_count" -gt 0 ]; then
    echo "ISSUES:"
    printf '%s\n' "${issues[@]}"
    echo ""
    echo "FIX: restore the missing token; see .claude/rules/loop-integrity.md"
fi
echo "=== END LOOP INTEGRITY ==="

if [ "$STRICT" -eq 1 ] && [ "$issue_count" -gt 0 ]; then
    exit 1
fi
exit 0
