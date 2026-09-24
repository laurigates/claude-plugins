# Adversarial Review — Reference

Supporting material for [SKILL.md](SKILL.md), loaded on demand.

## Audit sweeps: separate the settled facts from the decision before acting

Promoted from the always-loaded `separate-settled-facts-from-decisions.md`
portfolio rule, whose stub keeps the gate line.

An audit of documentation or configuration returns two kinds of finding, and
they look identical in the report. Some the repository can settle on its own —
a command that does not exist, a page that was renamed, a claim the IaC
contradicts. Others only a person can settle — who grants access, whether
reviews are required, which channel receives an incident. Treat them alike and
you get one of two bad outcomes: apply everything and the agent invents policy,
or defer everything and nothing gets fixed even where the answer was never in
doubt.

The fix is a pass between finding and fixing, whose only job is to *reduce* each
undecided finding to the part a person actually has to answer.

### Three passes, in order

1. **Find**, with independent lenses over the same corpus. One lens per journey
   or per theme, not per file.
2. **Verify adversarially.** Each finding goes to skeptics told to refute it,
   re-opening every cited source at the ref rather than trusting the quote.
   Refute on: the defect is absent at the ref, the evidence is misquoted or from
   the wrong branch, a claimed absence is contradicted elsewhere, or a
   "superseded by" cites an ADR that is only proposed. (This is SKILL.md's
   isolated reviewer with the inverted objective, applied per finding.)
3. **Resolve the facts.** For every finding marked *needs-decision*, settle
   everything the configuration answers and write the residue as one question.
   Record settled facts with evidence, and record separately any fact a checker
   found overreaching — those must never be written into the docs.

Only then edit: apply the clear findings in full, and apply the undecided ones
**only where the settled facts make a change policy-neutral** — correcting a
wrong fact, deleting a false claim, adding a step whose content is settled.
Never name an owner, route or policy that the residue still covers, and never
write "TBD" into published text. Each editor reports what it left open.

### Why the middle pass pays

It moves findings in both directions, and both are wins:

- A question can dissolve. One finding asked how developers enrol in a bot; the
  configuration showed the bot's code does not exist, so the page was simply
  wrong and the fix needed no decision at all.
- A question can shrink. "Who grants GitHub access?" splits into a fact (org
  owners invite by hand; no `github_membership` resource exists) and a decision
  (who *should* own it). The fact belongs in the docs today; only the decision
  waits.

> Example (an onboarding sweep across a wiki, an IaC repo and an org config
> repo): a small fraction of findings (a few percent) were refuted in
> adversarial verification — including one claiming a file had drifted from its
> source when it was copied verbatim, errors included — while verifiers
> corrected the *proposed fix* in roughly nine of every ten first-round
> findings, so the fix text was wrong far more often than the finding was.
> About three quarters of the findings had a single right answer and shipped;
> the rest became a handful of tracking issues, and editors recorded explicit
> deferrals naming exactly what remained open. No page was held back merely
> because one sentence in it needed a decision.

### When it bites

- Any sweep where "the docs say X" meets "the config does Y" — the gap is
  sometimes a doc bug and sometimes a policy gap, and only reading the config
  tells you which.
- Onboarding and compliance audits especially, where most findings are about
  ownership and routes, so a naive pass either invents them or defers the lot.
- Anywhere a fix template demands a field the repository cannot supply: that
  demand is what makes an agent write a plausible owner, and a plausible owner
  is indistinguishable from a real one to the next reader.

Portfolio incident evidence is kept privately (repos-claude-config docs/rule-evidence/separate-settled-facts-from-decisions.md).

### Related

- `agent-patterns-plugin:parallel-agent-dispatch` `references/verifier-shared-state.md`
  — a verifier that reads the builder's working tree is not independent;
  establish base state from the ref
- `~/.claude/rules/verify-license-position-before-declaring-blocked.md` — same
  instinct one layer out: read the actual position before declaring a blocker
- `~/.claude/rules/workflow-agent-scale.md` — group the editors by theme; the
  cost of this shape is agent count, not context
- `agent-patterns-plugin:tool-result-traps` — control-test the negatives the
  audit rests on
