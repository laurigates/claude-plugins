---
id: ADR-0024
date: 2026-10-09
created: 2026-10-09
modified: 2026-10-09
status: Accepted
deciders: claude-plugins team
domain: automation
relates-to:
  - ADR-0020  # autonomy levels; this ADR partially supersedes its permanent work-order gate
  - ADR-0005  # blueprint development methodology (the PRP -> work-order flow both skills implement)
github-issues:
  - 2592  # adjudicate the declared delegation-reachability residuals in blueprint-plugin
  - 2483  # widened the reachability guard to the whole marketplace and declared the residuals
  - 1906  # a reporter misread the gated work-order reference as a missing skill
---

# ADR-0024: Make `/blueprint:work-order` and `/blueprint:prp-execute` Model-Invocable

## Context

ADR-0020 kept `disable-model-invocation: true` on `/blueprint:work-order` and
`/blueprint:prp-execute` "permanently" (its § The draft-issue side channel). Its
reason was that work-order creation is a mutating, possibly sensitive act: the
work-order file is gitignored and may carry sensitive detail, and committing a
work order writes `tasks.pending` and the `id_registry`. Automation was to
*draft* proposals only, and a human would promote them.

The gate turned out to block more than automation. It removes both skills from
the model's skill listing altogether, so every blueprint skill that routes to
them hands the model an instruction it cannot carry out:

- `scripts/check-delegation-reachability.sh`, widened to the whole marketplace
  by #2483, found **13 references across 9 blueprint skills** that present one
  of the two gated skills as an agent action. One was a heading (exempted as
  Class D); the other 12 had to be **declared** in `DELEGATION_ALLOWLIST_DEFAULT`
  so the guard could stay green on `main`. Including skill sidecars, the
  declared set later suppressed 17 findings.
- Two of them are the main path of the methodology, not side remarks:
  `blueprint-execute` routes a single ready PRP to `/blueprint:prp-execute`, and
  `blueprint-prp-execute` routes the "create a work order" choice to
  `/blueprint:work-order --from-prp`. Both fail silently: the delegation is
  prose, so no tool call is refused and nothing is logged.
- #1906: a reporter searched the skill listing for `blueprint-work-order`,
  did not find it, and concluded the referenced skill did not exist. The
  `user-invocable` wording added to the handoff lines treated the symptom.

The flag also guarded less than ADR-0020 expected. It stops only the model
invoking the skill. It does not stop a user from asking for a work order, which
is the normal way one is created. The autopilot "drafts only" rule was already
written as an instruction in `blueprint-autopilot`. The level-3 executor's real
gate is the deterministic `blueprint-wo-guard.sh` (the `work-order-approved`
label, `autonomy_level >= 3`, `auto_execute`, budgets), not this flag.

The decision was recorded on #2592 at triage on 2026-09-20: un-gate both
skills, and record the reversal in an ADR so the corpus stops teaching the old
rule.

## Decision

**Remove `disable-model-invocation: true` from `blueprint-work-order` and
`blueprint-prp-execute`.** Both skills become model-invocable like every other
blueprint skill.

This supersedes the following parts of ADR-0020. Everything else in ADR-0020
stands, including the level model, the manifest `automation` block, the
deterministic runner, interaction modes and the safety rails:

| ADR-0020 text | Status |
|---|---|
| § Context, "work orders are human-only *by design*" | Superseded: work-order creation is a normal skill invocation |
| § The draft-issue side channel, "`disable-model-invocation: true` stays on it (and on `/blueprint:prp-execute`) permanently" | Superseded: the flag is removed from both |
| § Options Considered, option 4 rejection ("drop `disable-model-invocation`") | Superseded for the flag. The rejection of *autonomous* creation stands, as automation policy |

**The automation policy does not change; only where it is enforced changes.**
Ambient automation still drafts and does not commit:

- `blueprint-autopilot` (level 2) files `work-order-draft` proposals and does
  not run `/blueprint:work-order` or `/blueprint:prp-execute` itself. Promotion
  is a separate `/blueprint:work-order --from-issue N` step taken after a draft
  is reviewed. Closing a draft remains a veto.
- The level-3 `Blueprint: Autorun` pass drafts the same way. The level-3
  executor still runs only on a `work-order-approved` label, checked by
  `blueprint-wo-guard.sh`.

These rules now live in the instructions of the skills and templates that
automate, and no longer in a frontmatter flag on the skills they automate.

`DELEGATION_ALLOWLIST_DEFAULT` in `scripts/check-delegation-reachability.sh` is
emptied. Once the targets are not gated, every declared key matches nothing,
and the guard reports such a key as `stale_allowlist_entry`. The guard keeps
its full marketplace scope with no declared residuals (`ALLOWLISTED=0`).

ADR-0020 links to this ADR through `relates-to` and a banner. It does not use
`superseded-by`: `/blueprint:adr-validate` expects the target of a `supersedes`
link to have status `Superseded`, and ADR-0020 as a whole is still in force.

## Options Considered

### Option 1: Reword every residual into the recommendation form (rejected)

Rewrite all 12 sites as "recommend the user run …", the #2442 precedent.

**Pros:** Keeps ADR-0020 intact. No new decision.

**Cons:** #2442 fitted `/git:pr-feedback`, which posts to other people's PRs
and fans out pushing subagents, so a deliberate human start made sense. Here
the gated skills are the main step of the methodology. Rewording would turn
`blueprint-execute`'s single-PRP route and `prp-execute`'s own work-order
choice into hand-offs back to the user. That would also leave the #1906
discoverability defect in place, because the skills would stay out of the
listing.

### Option 2: Add structural exemption classes to the guard (rejected)

Exempt choice menus, explanatory tables and text the agent writes for a human,
as #2592 sketched for its groups (b), (c) and (d).

**Pros:** Clears most of the residuals mechanically.

**Cons:** It cannot clear group (a), the two real imperatives. Each new class
also widens what the guard cannot see. And the defect that matters stays: the
model is told to run skills it cannot reach.

### Option 3: Un-gate both skills (chosen)

**Pros:** All 12 declared residuals become reachable delegations, so the
allowlist empties and the guard runs with nothing suppressed. Both skills
appear in the skill listing, which removes the #1906 root cause. The
methodology's own routes work as written.

**Cons:** The harness no longer refuses a model-initiated work order. See
§ Consequences.

## Consequences

### Positive

- `check-delegation-reachability.sh` reports `ALLOWLISTED=0 STATUS=OK` over
  the full marketplace. Any new unreachable delegation is an error without
  exception.
- `blueprint-execute`, `blueprint-prp-create`, `blueprint-prp-execute`,
  `blueprint-development`, `confidence-scoring`, `document-detection` and
  `blueprint-story-reconcile` reach their targets.
- The two story skills' handoff lines no longer need a "don't invoke it via the
  Skill tool" clause.

### Negative

- **A model-initiated work order is no longer refused by the harness.** The
  model can now write a work-order file, update `tasks.pending` and the
  `id_registry`, and open a GitHub issue without a user typing the command.
  The "automation drafts only" rule is now an instruction in
  `blueprint-autopilot` and the level-3 autorun template rather than a flag.
- The skill listing grows by two descriptions.

### Mitigations

| Issue | Mitigation |
|-------|------------|
| Automation committing a work order | `blueprint-autopilot` and the level-3 autorun prompt still say "draft only"; both are bounded per pass. The level-3 executor stays behind the deterministic `blueprint-wo-guard.sh` label and budget gate |
| A work order created without review | Both skills keep their closing `AskUserQuestion` menus in normal interaction mode, and a direct slash command stays fully interactive at every level (ADR-0020 § Interaction mode) |
| The corpus teaching the reversed rule | Rewritten in the same commit: `blueprint-autopilot`, `blueprint-autonomy-level3/REFERENCE.md`, the autorun template prompt, the v3.3-to-v3.4 migration, `blueprint-plugin/README.md`, the two story-skill handoffs and their #1906 test, and the guard's header comment |

## Related ADRs

- [ADR-0020: Blueprint Autonomy Levels](0020-blueprint-autonomy-levels.md) — partially superseded by this ADR, as listed in § Decision
- [ADR-0005: Blueprint Development Methodology](0005-blueprint-development-methodology.md) — the PRP-to-work-order flow both skills implement

## References

- [Issue #2592](https://github.com/laurigates/claude-plugins/issues/2592) — the residual adjudication and the recorded decision
- [Issue #2483](https://github.com/laurigates/claude-plugins/issues/2483) — the marketplace-wide guard and the declared residuals
- [Issue #1906](https://github.com/laurigates/claude-plugins/issues/1906) — the work-order reference misread as a missing skill
- `.claude/rules/pr-branch-sync.md` § Gated siblings are recommended, never delegated to — the rule the guard enforces
