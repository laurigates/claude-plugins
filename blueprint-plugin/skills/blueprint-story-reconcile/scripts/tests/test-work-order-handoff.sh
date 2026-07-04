#!/usr/bin/env bash
# Regression test for issue #1906: story-reconcile / story-audit referenced
# `/blueprint:work-order` in a way that read as "invoke it via the Skill tool".
#
# Root cause: `blueprint-work-order` carries `disable-model-invocation: true`,
# so it never appears in the model's skill list and cannot be invoked via the
# Skill tool — the model can only SURFACE it for the user to run. A reporter
# searched the list, misread the reference as "skill doesn't exist", and stalled.
#
# The fix reworded both handoff steps to make clear the command is
# user-invocable and must be surfaced, not Skill-tool-invoked. This test pins
# two semantic invariants against a future bulk edit (including this issue's own
# preliminary hint, which wrongly wanted the ref repointed to a different skill):
#
#   1. Both handoff steps still reference the CORRECT command
#      `/blueprint:work-order` (not repointed to blueprint-prp-create/anything).
#   2. Each handoff step carries the clarifying `user-invocable` token so the
#      "surface it, don't Skill-invoke it" intent survives.
#
# Exit 0 on success, non-zero on failure.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
reconcile_skill="${script_dir}/../../SKILL.md"
audit_skill="${script_dir}/../../../blueprint-story-audit/SKILL.md"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }

[ -f "$reconcile_skill" ] || fail "story-reconcile SKILL.md not found at $reconcile_skill"
[ -f "$audit_skill" ]     || fail "story-audit SKILL.md not found at $audit_skill"

# The single line in each skill that hands off the work-order follow-on action.
# story-reconcile Step 9: "Open work-orders for ..." ; story-audit Step 8:
# "Dispatch a work-order for a Tier-1 gap ...". Both point at /blueprint:work-order.
reconcile_handoff="$(grep -m1 'Open work-orders' "$reconcile_skill" || true)"
audit_handoff="$(grep -m1 'Dispatch a work-order' "$audit_skill" || true)"

[ -n "$reconcile_handoff" ] || fail "story-reconcile lost its 'Open work-orders' handoff line"
[ -n "$audit_handoff" ]     || fail "story-audit lost its 'Dispatch a work-order' handoff line"

# Invariant 1: the handoff still names the correct command (guards a repoint to
# a different skill such as blueprint-prp-create).
case "$reconcile_handoff" in
  *'/blueprint:work-order'*) pass "story-reconcile handoff references /blueprint:work-order" ;;
  *) fail "story-reconcile handoff no longer references /blueprint:work-order: $reconcile_handoff" ;;
esac
case "$audit_handoff" in
  *'/blueprint:work-order'*) pass "story-audit handoff references /blueprint:work-order" ;;
  *) fail "story-audit handoff no longer references /blueprint:work-order: $audit_handoff" ;;
esac

# Invariant 2: the handoff clarifies the command is user-invocable / surfaced,
# not Skill-tool-invoked (the #1906 fix). Match case-insensitively on the
# hyphenated token so a rewording of the surrounding prose still passes.
case "${reconcile_handoff,,}" in
  *user-invocable*) pass "story-reconcile handoff clarifies user-invocable" ;;
  *) fail "story-reconcile handoff missing 'user-invocable' clarification (#1906): $reconcile_handoff" ;;
esac
case "${audit_handoff,,}" in
  *user-invocable*) pass "story-audit handoff clarifies user-invocable" ;;
  *) fail "story-audit handoff missing 'user-invocable' clarification (#1906): $audit_handoff" ;;
esac

echo "OK: work-order handoff invariants hold (#1906)"
