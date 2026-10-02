#!/usr/bin/env bash
# check-loop-integrity.sh — semantic guard for the loop-integrity convention.
#
# THE CONVENTION (.claude/rules/loop-integrity.md)
# Long-running / self-continuing loops carry two invariants:
#   Pillar 1 — the stop condition is judged INDEPENDENTLY (a fresh verifier, not
#              the worker, decides "done"; else the loop optimises for completion
#              over correctness).
#   Pillar 2 — each iteration leaves a COMPACT STATE PACKET (objective, ref,
#              files-in-scope, exit condition, verifier result, changed-since,
#              ordering / preconditions, next target) so a context-free
#              successor can re-enter cleanly (#2693 added the last two).
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
EXEC_REVIEW="$ROOT_DIR/agent-patterns-plugin/skills/execution-grounded-review/SKILL.md"

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
require "$RULE" "Ordering / preconditions" "state packet lost the ordering field (successor acts out of order) (#2693)"
require "$RULE" "Next target" "state packet lost the next-target field (successor re-derives target selection) (#2693)"

# Checkpoint skill — the plan file IS the state packet; gate stays independent.
require "$CHECKPOINT" "Verifier result" "checkpoint plan format lost the Verifier-result field (reverts to self-judged done)"
require "$CHECKPOINT" "Changed since last run" "checkpoint plan format lost the changed-since field (resume redoes/undoes work)"
require "$CHECKPOINT" "Exit condition" "checkpoint plan format lost the top-level exit condition"
require "$CHECKPOINT" "Ordering / preconditions" "checkpoint plan format lost the per-phase ordering field (#2693)"
require "$CHECKPOINT" "Next target" "checkpoint plan format lost the next-target field (#2693)"
require "$CHECKPOINT" "independent verifier" "checkpoint phase gate lost the independent-verifier step"
require "$CHECKPOINT" "loop-integrity.md" "checkpoint skill lost its loop-integrity cross-reference"

# Sibling skills — keep the cross-reference so the convention stays discoverable.
require "$TEST_LOOP" "loop-integrity.md" "project-test-loop lost its loop-integrity cross-reference"
require "$ADVERSARIAL" "loop-integrity.md" "adversarial-review lost its loop-integrity (Pillar 1) cross-reference"
require "$EXEC_REVIEW" "loop-integrity.md" "execution-grounded-review lost its loop-integrity (Pillar 1) cross-reference"
# The attribution step must stay bounded (loop-integrity.md "Bounding runaway")
# and must report a checkable span, not an impression (#2694).
require "$EXEC_REVIEW" "Attribution bound" "execution-grounded-review attribution search lost its stated upper bound (#2694)"
require "$EXEC_REVIEW" "evidenceSpan" "execution-grounded-review LEDGER lost the evidenceSpan field (#2694)"
# The report must declare narrative-changing limitations before the verdict,
# with "none" stated explicitly rather than omitted (#2870).
require "$EXEC_REVIEW" '"limitations"' "execution-grounded-review LEDGER lost the required limitations field (#2870)"
require "$EXEC_REVIEW" "LIMITATIONS:" "execution-grounded-review report lost the LIMITATIONS block before VERDICT (#2870)"
# The one mitigation the paper measured: a literal honesty instruction in the
# verifier brief. A "tighten the brief" edit that drops it loses the evidence-
# backed part of #2870.
require "$EXEC_REVIEW" "never omit the field. Be honest in your response." "execution-grounded-review verifier brief lost the honesty instruction (#2870)"
# Eval run on PR #2871 (f1b36ab): a pass verdict was issued with the typecheck
# unrun, a no-inputs request produced a fail ledger instead of an abstention,
# and speculative caveats made "none" unreachable on a clean run.
require "$EXEC_REVIEW" "every Step 1 step ran to completion" "execution-grounded-review verdict no longer requires Step 1 to complete before a pass (#2871)"
require "$EXEC_REVIEW" "stop: emit no ledger and no" "execution-grounded-review lost its no-inputs abstain path (#2871)"
require "$EXEC_REVIEW" "Speculative risks" "execution-grounded-review lost the grounded-limitations rule against speculative caveats (#2871)"
# A red suite fails the verdict only on failures that are new against the
# merge-base, via an implicit no-regression criterion (PR #2871 eval, finding 3).
require "$EXEC_REVIEW" "passes on the merge-base fails on the head" "execution-grounded-review lost its implicit no-regression criterion"
require "$EXEC_REVIEW" "separate new failures from pre-existing ones" "execution-grounded-review lost the Step 1 merge-base comparison"

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
