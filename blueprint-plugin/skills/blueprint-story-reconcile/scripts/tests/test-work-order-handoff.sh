#!/usr/bin/env bash
# Regression test for the story-reconcile / story-audit work-order handoff.
#
# History:
#   * Issue #1906: `blueprint-work-order` carried `disable-model-invocation:
#     true`, so it was missing from the model's skill listing. A reporter
#     searched the listing, read the handoff's `/blueprint:work-order` reference
#     as "skill doesn't exist", and stalled. The #1906 fix reworded both handoff
#     steps to say the command was user-invocable and must be surfaced to the
#     user rather than invoked via the Skill tool.
#   * Issue #2592 / ADR-0024: the gate was removed from `blueprint-work-order`
#     (and `blueprint-prp-execute`), so the skill is in the listing and the
#     handoff now runs it directly once the user picks the option. The #1906
#     "surface it, don't Skill-invoke it" wording became wrong and was removed.
#
# Invariants pinned against a future bulk edit:
#
#   1. Both handoff steps still reference the CORRECT command
#      `/blueprint:work-order` (not repointed to blueprint-prp-create or
#      anything else — #1906's own preliminary hint wanted that repoint).
#   2. Neither handoff step still carries the gate-era "don't invoke it via the
#      Skill tool" / "user-invocable command" clause (#2592): it would tell the
#      model not to run a skill it can now reach.
#   3. `blueprint-work-order` itself is model-invocable — its frontmatter has
#      no `disable-model-invocation: true`. The handoff tells the agent to run
#      the skill, so re-gating it would turn both handoffs into unreachable
#      delegations; re-gating needs a new ADR and a rewrite of these lines.
#
# Exit 0 on success, non-zero on failure.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
reconcile_skill="${script_dir}/../../SKILL.md"
audit_skill="${script_dir}/../../../blueprint-story-audit/SKILL.md"
work_order_skill="${script_dir}/../../../blueprint-work-order/SKILL.md"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }

[ -f "$reconcile_skill" ]  || fail "story-reconcile SKILL.md not found at $reconcile_skill"
[ -f "$audit_skill" ]      || fail "story-audit SKILL.md not found at $audit_skill"
[ -f "$work_order_skill" ] || fail "work-order SKILL.md not found at $work_order_skill"

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

# Invariant 2: the gate-era clause is gone (#2592). Matched case-insensitively
# on its two load-bearing phrases so a light rewording is still caught.
for pair in "story-reconcile|$reconcile_handoff" "story-audit|$audit_handoff"; do
  label="${pair%%|*}"
  handoff="${pair#*|}"
  case "${handoff,,}" in
    *"don't invoke it via the skill tool"*|*"do not invoke it via the skill tool"*|*"user-invocable command"*)
      fail "$label handoff still carries the gate-era 'surface it, don't Skill-invoke it' clause (#2592 / ADR-0024): $handoff" ;;
    *) pass "$label handoff no longer claims /blueprint:work-order is unreachable" ;;
  esac
done

# Invariant 3: the skill the handoffs run is model-invocable (ADR-0024). Read
# only the frontmatter block, so prose that mentions the flag cannot trip it.
gated="$(awk 'NR==1 && /^---$/ {fm=1; next} fm && /^---$/ {exit} fm && /^disable-model-invocation:[[:space:]]*true/ {print "yes"}' "$work_order_skill")"
if [ -n "$gated" ]; then
  fail "blueprint-work-order carries disable-model-invocation: true, but both handoffs tell the agent to run it (ADR-0024 / #2592)"
fi
pass "blueprint-work-order is model-invocable (ADR-0024)"

echo "OK: work-order handoff invariants hold (#1906, #2592)"
